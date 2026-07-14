import '../../../data/repositories/budgets_repository.dart';
import '../../../data/repositories/reports_repository.dart';
import '../domain/ai_mention_resolver.dart';
import '../domain/ai_payload_builder.dart';

/// The outcome of executing one tool call. [body] is the JSON the LLM sees
/// (anonymized on success; `{'error': …}` on a validation/execution failure).
/// [amounts] and [names] are the figures/names the body emitted (success only)
/// so the gatekeeper can accept a final reply that quotes them. [isError]
/// marks a structured error to feed back to the LLM for self-correction.
class AiToolResult {
  const AiToolResult({
    required this.body,
    this.amounts = const <double>{},
    this.names = const <String>{},
    this.isError = false,
  });
  final Map<String, Object?> body;
  final Set<double> amounts;
  final Set<String> names;
  final bool isError;
}

/// Executes a named, fixed on-device query for an LLM tool-call. Safety is in
/// the closed tool set — the LLM never authors SQL. Steps per call:
/// validate → resolve labels to real ids (on-device) → run a fixed repo query
/// → anonymize results back to labels (or real names when [shareNames]) → cap.
/// Never reads `note`/`receipt_path`; never touches `due_*`/`ai_*`/`goals`/
/// `recurring_items` tables (goals/bills come from the in-memory aggregates
/// passed in, not a table query).
class AiToolExecutor {
  AiToolExecutor({
    required this.reports,
    required this.budgets,
    required this.directory,
    required this.goals,
    required this.bills,
    required this.labelToId,
    required this.shareNames,
  });

  final ReportsRepository reports;
  final BudgetsRepository budgets;
  final AiMentionData directory;
  final List<GoalSummary> goals;
  final List<BillSummary> bills;
  final Map<String, String> labelToId;
  final bool shareNames;

  static const int _maxRows = 20;
  static const int _maxGroup = 10;
  static const int _maxMonths = 24;

  // Accumulators for the current call. Reset at the start of [execute] so a
  // second call on the same executor instance never inherits the first call's
  // figures/names.
  Set<double> _amounts = <double>{};
  Set<String> _names = <String>{};

  void _emit(double amt) => _amounts.add(amt);
  void _emitName(String n) => _names.add(n);

  Future<AiToolResult> execute(String tool, Map<String, Object?> args) async {
    _amounts = <double>{};
    _names = <String>{};
    try {
      switch (tool) {
        case 'list_entities':
          return _listEntities(args);
        case 'breakdown':
          return await _breakdown(args);
        case 'monthly_totals':
          return await _monthlyTotals(args);
        case 'filtered_totals':
          return await _filteredTotals(args);
        case 'budget_status':
          return await _budgetStatus(args);
        case 'goals_overview':
          return _goalsOverview();
        case 'bills_overview':
          return _billsOverview();
        default:
          return AiToolResult(body: {'error': 'Unknown tool: $tool'}, isError: true);
      }
    } on _ToolError catch (e) {
      return AiToolResult(body: {'error': e.message}, isError: true);
    } catch (e) {
      return AiToolResult(body: {'error': 'Tool failed: $e'}, isError: true);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _resolveLabel(String label, String kind) {
    final id = labelToId[label];
    if (id == null) throw _ToolError('Unknown $kind label: $label');
    return id;
  }

  /// id → display token. Label by default; real name when shareNames.
  String _labelOf(String id, String kind) {
    if (shareNames) {
      final name = _nameOf(id, kind);
      if (name != null) return name;
    }
    // Invert labelToId for the anonymized default.
    final entry = labelToId.entries.firstWhere(
      (e) => e.value == id,
      orElse: () => MapEntry('', id),
    );
    return entry.key.isNotEmpty ? entry.key : id;
  }

  String? _nameOf(String id, String kind) {
    switch (kind) {
      case 'category':
        return directory.categories.firstWhere(
          (c) => c.id == id, orElse: () => (id: id, name: id)).name;
      case 'account':
        return directory.accounts.firstWhere(
          (a) => a.id == id, orElse: () => (id: id, name: id)).name;
      case 'mode':
        return directory.modes.firstWhere(
          (m) => m.id == id, orElse: () => (id: id, name: id)).name;
      case 'tag':
        return directory.tags.firstWhere(
          (t) => t.id == id, orElse: () => (id: id, name: id)).name;
      case 'goal':
        return goals.firstWhere(
          (g) => g.id == id,
          orElse: () => (id: id, name: id, target: 0, saved: 0,
              monthsLeft: null, monthlyCommitment: null)).name;
      case 'bill':
        return bills.firstWhere(
          (b) => b.id == id,
          orElse: () => (id: id, name: id, amount: 0, cadence: '',
              nextDueInDays: null, source: '')).name;
    }
    return null;
  }

  ({String from, String to}) _dateRange(Map<String, Object?> args) {
    final from = _isoDate(args, 'from');
    final to = _isoDate(args, 'to');
    if (from.compareTo(to) > 0) {
      throw _ToolError('Invalid date range: from ($from) is after to ($to).');
    }
    return (from: from, to: to);
  }

  String _isoDate(Map<String, Object?> args, String key) {
    final v = args[key];
    if (v is! String) throw _ToolError('Missing or invalid date arg: $key');
    // Accept yyyy-MM-dd or full ISO. Normalize to a start-of-day ISO string.
    final s = v.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return '${s}T00:00:00.000';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s)) return s;
    throw _ToolError('Bad date format for $key: $v (use yyyy-MM-dd).');
  }

  String? _kind(Map<String, Object?> args) {
    final v = args['kind'];
    if (v == null) return 'expense';
    if (v is! String) throw _ToolError('Bad kind: $v.');
    if (const {'expense', 'income', 'all'}.contains(v)) {
      return v == 'all' ? null : v;
    }
    throw _ToolError('Bad kind: $v (use expense, income, or all).');
  }

  double? _numOpt(Map<String, Object?> args, String key) {
    final v = args[key];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    throw _ToolError('Bad number for $key: $v.');
  }

  /// Round to one decimal place — bit-for-bit identical to
  /// `AiPayloadBuilder._round1` so executor `pct` matches the builder's `pct`.
  static double _round1(double v) => (v * 10).round() / 10;

  // ── Tools ─────────────────────────────────────────────────────────────────

  AiToolResult _listEntities(Map<String, Object?> args) {
    final kind = args['kind'];
    if (kind is! String) {
      return const AiToolResult(
          body: {'error': 'list_entities requires arg "kind".'}, isError: true);
    }
    final out = <Map<String, Object?>>[];
    switch (kind) {
      case 'category':
        for (final c in directory.categories) {
          out.add({'id': _labelOf(c.id, 'category'), if (shareNames) 'name': c.name});
        }
        break;
      case 'account':
        for (final a in directory.accounts) {
          out.add({'id': _labelOf(a.id, 'account'), if (shareNames) 'name': a.name});
        }
        break;
      case 'mode':
        for (final m in directory.modes) {
          out.add({'id': _labelOf(m.id, 'mode'), if (shareNames) 'name': m.name});
        }
        break;
      case 'tag':
        for (final t in directory.tags) {
          out.add({'id': _labelOf(t.id, 'tag'), if (shareNames) 'name': t.name});
        }
        break;
      case 'goal':
        for (final g in goals) {
          out.add({'id': _labelOf(g.id, 'goal'), if (shareNames) 'name': g.name});
        }
        break;
      case 'bill':
        for (final b in bills) {
          out.add({'id': _labelOf(b.id, 'bill'), if (shareNames) 'name': b.name});
        }
        break;
      default:
        return AiToolResult(body: {'error': 'Unknown entity kind: $kind'}, isError: true);
    }
    if (shareNames) {
      for (final e in out) {
        final n = e['name'];
        if (n is String) _emitName(n);
      }
    }
    return AiToolResult(
        body: {'kind': kind, 'count': out.length, 'entities': out}, names: _names);
  }

  Future<AiToolResult> _breakdown(Map<String, Object?> args) async {
    final groupBy = args['group_by'];
    if (groupBy is! String) {
      return const AiToolResult(
          body: {'error': 'breakdown requires arg "group_by".'}, isError: true);
    }
    final range = _dateRange(args);
    final kind = _kind(args);
    List<Map<String, Object?>> rows;
    double totalForPct = 0;
    switch (groupBy) {
      case 'category':
        final data = await reports.categoryBreakdown(from: range.from, to: range.to, kind: kind);
        rows = data.map((c) {
          final amt = c.total;
          _emit(amt);
          if (shareNames) _emitName(c.name);
          return {
            'id': _labelOf(c.categoryId, 'category'),
            if (shareNames) 'name': c.name,
            'amount': amt,
          };
        }).toList();
        totalForPct = data.fold<double>(0, (s, c) => s + c.total);
        break;
      case 'mode':
        final data = await reports.modeBreakdown(from: range.from, to: range.to, kind: kind);
        rows = data.map((m) {
          final amt = m.total;
          _emit(amt);
          if (shareNames) _emitName(m.name);
          return {
            'id': _labelOf(m.modeId, 'mode'),
            if (shareNames) 'name': m.name,
            'amount': amt,
          };
        }).toList();
        totalForPct = data.fold<double>(0, (s, m) => s + m.total);
        break;
      case 'tag':
        // tagBreakdown is expense-only in the repo; ignore kind for tags.
        final data = await reports.tagBreakdown(from: range.from, to: range.to);
        rows = data.map((t) {
          final amt = t.total;
          _emit(amt);
          if (shareNames) _emitName(t.name);
          return {
            'id': _labelOf(t.tagId, 'tag'),
            if (shareNames) 'name': t.name,
            'amount': amt,
          };
        }).toList();
        totalForPct = data.fold<double>(0, (s, t) => s + t.total);
        break;
      case 'account':
        // No per-range account breakdown in the repo → reuse filteredTotals'
        // by_account with no filters, kind only.
        final f = await reports.filteredTotals(from: range.from, to: range.to, kind: kind);
        rows = f.byAccount.map((a) {
          _emit(a.amount);
          if (shareNames) _emitName(a.name);
          return {
            'id': _labelOf(a.id, 'account'),
            if (shareNames) 'name': a.name,
            'amount': a.amount,
            'count': a.count,
          };
        }).toList();
        totalForPct = f.total;
        break;
      default:
        return AiToolResult(body: {'error': 'Unknown group_by: $groupBy'}, isError: true);
    }
    final capped = <Map<String, Object?>>[...rows.take(_maxRows)];
    if (rows.length > _maxRows) {
      final otherAmt = rows.skip(_maxRows).fold<double>(0, (s, r) => s + (r['amount'] as double));
      _emit(otherAmt);
      capped.add({'id': 'other', 'amount': otherAmt});
    }
    final withPct = capped.map((r) {
      final amt = r['amount'] as double;
      return {
        ...r,
        'pct': totalForPct > 0 ? _round1(amt / totalForPct * 100) : 0.0,
      };
    }).toList();
    return AiToolResult(
        body: {'group_by': groupBy, 'rows': withPct}, amounts: _amounts, names: _names);
  }

  Future<AiToolResult> _monthlyTotals(Map<String, Object?> args) async {
    final range = _dateRange(args);
    final data = await reports.monthlyTotalsInRange(from: range.from, to: range.to);
    final months = data.take(_maxMonths).map((m) {
      _emit(m.income);
      _emit(m.expense);
      _emit(m.net);
      return {
        'month': '${m.year}-${m.month.toString().padLeft(2, '0')}',
        'income': m.income,
        'expense': m.expense,
        'net': m.net,
      };
    }).toList();
    return AiToolResult(body: {'months': months}, amounts: _amounts);
  }

  Future<AiToolResult> _filteredTotals(Map<String, Object?> args) async {
    final range = _dateRange(args);
    final kind = _kind(args);
    String? catId, accId, modeId, tagId;
    if (args['category'] is String) catId = _resolveLabel(args['category'] as String, 'category');
    if (args['account'] is String) accId = _resolveLabel(args['account'] as String, 'account');
    if (args['mode'] is String) modeId = _resolveLabel(args['mode'] as String, 'mode');
    if (args['tag'] is String) tagId = _resolveLabel(args['tag'] as String, 'tag');
    final amountMin = _numOpt(args, 'amount_min');
    final amountMax = _numOpt(args, 'amount_max');

    final r = await reports.filteredTotals(
      from: range.from, to: range.to, kind: kind,
      accountId: accId, categoryId: catId, modeId: modeId, tagId: tagId,
      amountMin: amountMin, amountMax: amountMax,
    );
    _emit(r.total);

    List<Map<String, Object?>> cap(
        List<({String id, String name, double amount, int count})> src, String kindName) {
      final mapped = src.map((e) {
        _emit(e.amount);
        if (shareNames) _emitName(e.name);
        return {
          'id': _labelOf(e.id, kindName),
          if (shareNames) 'name': e.name,
          'amount': e.amount,
          'count': e.count,
        };
      }).toList();
      final capped = <Map<String, Object?>>[...mapped.take(_maxGroup)];
      if (mapped.length > _maxGroup) {
        final otherAmt = mapped.skip(_maxGroup).fold<double>(0, (s, m) => s + (m['amount'] as double));
        _emit(otherAmt);
        final otherCnt = src.skip(_maxGroup).fold<int>(0, (s, m) => s + m.count);
        capped.add({'id': 'other', 'amount': otherAmt, 'count': otherCnt});
      }
      return capped;
    }

    return AiToolResult(
      body: {
        'count': r.count,
        'total': r.total,
        'by_category': cap(r.byCategory, 'category'),
        'by_mode': cap(r.byMode, 'mode'),
        'by_account': cap(r.byAccount, 'account'),
        'by_tag': cap(r.byTag, 'tag'),
      },
      amounts: _amounts,
      names: _names,
    );
  }

  Future<AiToolResult> _budgetStatus(Map<String, Object?> args) async {
    DateTime monthDate;
    final m = args['month'];
    if (m is String && RegExp(r'^\d{4}-\d{2}$').hasMatch(m)) {
      final parts = m.split('-');
      monthDate = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    } else {
      final now = DateTime.now();
      monthDate = DateTime(now.year, now.month);
    }
    final list = await budgets.progressForMonth(monthDate);
    final rows = list.map((b) {
      _emit(b.spent);
      _emit(b.effectiveAmount);
      if (shareNames) _emitName(b.categoryName);
      final overBy = b.isOver ? b.spent - b.effectiveAmount : null;
      if (overBy != null) _emit(overBy);
      return {
        'id': _labelOf(b.budget.categoryId, 'category'),
        if (shareNames) 'name': b.categoryName,
        'spent': b.spent,
        'effective': b.effectiveAmount,
        'over': b.isOver,
        if (overBy != null) 'over_by': overBy,
      };
    }).toList();
    return AiToolResult(
      body: {
        'month': '${monthDate.year}-${monthDate.month.toString().padLeft(2, '0')}',
        'budgets': rows,
      },
      amounts: _amounts,
      names: _names,
    );
  }

  AiToolResult _goalsOverview() {
    final rows = goals.map((g) {
      _emit(g.target);
      _emit(g.saved);
      if (g.monthlyCommitment != null) _emit(g.monthlyCommitment!);
      final label = _labelOf(g.id, 'goal');
      if (shareNames) _emitName(g.name);
      return {
        'id': label,
        'target': g.target,
        'saved': g.saved,
        'pct': g.target > 0 ? _round1(g.saved / g.target * 100) : 0.0,
        if (g.monthsLeft != null) 'months_left': g.monthsLeft,
        if (g.monthlyCommitment != null) 'monthly_commitment': g.monthlyCommitment,
      };
    }).toList();
    return AiToolResult(body: {'goals': rows}, amounts: _amounts, names: _names);
  }

  AiToolResult _billsOverview() {
    final rows = bills.map((b) {
      _emit(b.amount);
      final label = _labelOf(b.id, 'bill');
      if (shareNames) _emitName(b.name);
      return {
        'id': label,
        'amount': b.amount,
        'cadence': b.cadence,
        if (b.nextDueInDays != null) 'next_due_in_days': b.nextDueInDays,
        'source': b.source,
      };
    }).toList();
    return AiToolResult(body: {'bills': rows}, amounts: _amounts, names: _names);
  }
}

class _ToolError implements Exception {
  const _ToolError(this.message);
  final String message;
}