import '../../../data/models/budget_progress.dart';
import '../../../data/models/report_models.dart';
import 'ai_config.dart';
import 'ai_context.dart';
import 'ai_mention_resolver.dart';

/// An account + its current balance, supplied to [AiPayloadBuilder] for the
/// `account_balances` field. `name` is used ONLY to build the on-device legend
/// via [_Labeler] — it never appears in the outbound JSON (only `acc_N` does).
typedef AccountBalance = ({String id, String name, double balance});

/// A savings-goal summary supplied for the `goals` field. `name` is used only
/// for the on-device legend; the outbound JSON emits `goal_N` + figures only
/// (no name, no icon, no note).
typedef GoalSummary = ({
  String id,
  String name,
  double target,
  double saved,
  int? monthsLeft,
  double? monthlyCommitment,
});

/// A recurring-bill summary supplied for the `recurring_bills` field. `name`
/// is used only for the on-device legend; the outbound JSON emits `bill_N` +
/// amount/cadence/next-due/source only (no name, no note).
typedef BillSummary = ({
  String id,
  String name,
  double amount,
  String cadence,
  int? nextDueInDays,
  String source,
});

/// The privacy boundary for the AI feature.
///
/// This is the **only** code that constructs what leaves the device. It reads
/// pre-computed aggregations ([MonthlySummary], [BudgetProgress], [MonthTotal],
/// …) — never raw transaction rows, never `DuesRepository`, never any `note`,
/// contact name, phone, or photo path.
///
/// It applies [AiConfig.shareNames]: when false (the default) it replaces
/// category/account/mode/tag/goal/bill *names* with opaque rank keys
/// (`cat_0`, `acc_1`, `goal_N`, `bill_N`) and embeds no `legend` in the
/// outbound JSON — the LLM sees only numbers and anonymous labels. When true
/// it attaches a `legend` mapping each rank key to its real name so advice can
/// be specific. Notes and contact data are stripped in *both* modes.
///
/// In **both** modes the full label→name legend is returned to the caller (in
/// the [AiContext] record) so [AiGatekeeper] can restore real names in the LLM's
/// reply on-device — the legend itself never leaves the device when
/// `shareNames` is false.
///
/// `MonthlySummary.biggestSpendNote` is a transaction note baked into an
/// aggregation result — it is explicitly dropped here (along with the single-
/// transaction `biggestSpendTitle`/`biggestSpendAmount`, which are too granular
/// to aggregate and would leak a category-by-name reference). Goal and bill
/// names are labelized but their `note`/`icon` are never sent.
class AiPayloadBuilder {
  AiPayloadBuilder({this.shareNames = false});
  final bool shareNames;

  /// Build the compact context used by the Ask chat (~400–700 tokens).
  ///
  /// Inputs are the current-month [summary], the month's [budgets], and the
  /// rolling 6-month [cashflow]. The optional aggregates (modes, account
  /// balances, tags, category trend, tx frequency, day distribution, goals,
  /// recurring bills) are anonymized and omitted when empty. Returns the JSON
  /// payload plus the on-device legend (see [AiContext]).
  AiContext buildAskContext({
    required MonthlySummary summary,
    required List<BudgetProgress> budgets,
    required List<MonthTotal> cashflow,
    required String period,
    List<ModeTotal> modeBreakdown = const [],
    List<AccountBalance> accountBalances = const [],
    List<TagTotal> tagBreakdown = const [],
    List<List<CategoryTotal>> categoryBreakdown3mo = const [],
    int? expenseCount,
    int? daysInPeriod,
    Map<String, double> dailyExpenseByDay = const {},
    List<GoalSummary> goals = const [],
    List<BillSummary> recurringBills = const [],
    List<AiEntityName> allCategories = const [],
    List<AiEntityName> allModes = const [],
    List<AiEntityName> allTags = const [],
  }) {
    final labeler = _Labeler();
    final expense = summary.expense;

    final allCats = _buildAllCategories(
        allCategories, categoryBreakdown3mo, labeler, expense);
    final modes = _buildAllModes(allModes, modeBreakdown, labeler, expense);
    final accBalances = _buildAccountBalances(accountBalances, labeler);
    final tags = _buildAllTags(allTags, tagBreakdown, labeler, expense);
    final txFrequency = _buildTxFrequency(expenseCount, daysInPeriod);
    final dayDist = _buildDayDistribution(dailyExpenseByDay);
    final goalsList = _buildGoals(goals, labeler);
    final billsList = _buildBills(recurringBills, labeler);

    final budgetList = <Map<String, Object?>>[];
    for (final b in budgets) {
      final key = labeler.category(b.budget.categoryId, b.categoryName);
      final effective = b.effectiveAmount;
      budgetList.add({
        'id': key,
        'spent': _round(b.spent),
        'effective': _round(effective),
        'over': b.isOver,
        if (b.isOver) 'over_by': _round(b.spent - effective),
      });
    }

    final cashflowList = <Map<String, Object?>>[];
    for (final m in cashflow) {
      cashflowList.add({
        'month': '${m.year}-${m.month.toString().padLeft(2, '0')}',
        'income': _round(m.income),
        'expense': _round(m.expense),
        'net': _round(m.net),
      });
    }

    return (
      json: {
        'currency_note':
            'All amounts in the user\'s currency, summed across accounts with no '
            'FX conversion. Treat the unit as one currency.',
        'period': period,
        'summary': {
          'income': _round(summary.income),
          'expense': _round(expense),
          'net': _round(summary.net),
        },
        'categories': allCats,
        if (allModes.isNotEmpty) 'payment_modes': modes,
        if (accountBalances.isNotEmpty) 'account_balances': accBalances,
        if (budgetList.isNotEmpty) 'budgets': budgetList,
        if (allTags.isNotEmpty) 'tag_breakdown': tags,
        if (txFrequency != null) 'tx_frequency': txFrequency,
        if (dayDist.isNotEmpty) 'day_distribution': dayDist,
        if (goalsList.isNotEmpty) 'goals': goalsList,
        if (billsList.isNotEmpty) 'recurring_bills': billsList,
        'cashflow_12mo': cashflowList,
        'savings_rate_trend': savingsRateTrend(cashflow),
        'category_count': allCategories.length,
        'account_count': accountBalances.length,
        'mode_count': allModes.length,
        'tag_count': allTags.length,
        'goal_count': goals.length,
        'bill_count': recurringBills.length,
        // biggestSpendNote / biggestSpendTitle / biggestSpendAmount are
        // deliberately NOT included — they are single-transaction details.
        if (shareNames && labeler.legend.isNotEmpty) 'legend': labeler.legend,
      },
      legend: labeler.legend,
    );
  }

  /// Build the richer context used by the on-demand narrative report.
  ///
  /// Same privacy rules as [buildAskContext]: only pre-computed aggregations,
  /// never raw rows / notes / contacts. Adds payment-mode breakdown and more
  /// top expense categories so the narrative report can reason about *how* the
  /// user pays and a broader spending mix. Same opaque-key + optional legend
  /// scheme via [_Labeler]. Returns the JSON payload plus the on-device legend
  /// (see [AiContext]).
  AiContext buildReportContext({
    required MonthlySummary summary,
    required List<BudgetProgress> budgets,
    required List<MonthTotal> cashflow,
    required List<CategoryTotal> topExpenseCategories,
    required List<ModeTotal> modeBreakdown,
    required String period,
    List<AccountBalance> accountBalances = const [],
    List<TagTotal> tagBreakdown = const [],
    List<List<CategoryTotal>> categoryBreakdown3mo = const [],
    int? expenseCount,
    int? daysInPeriod,
    Map<String, double> dailyExpenseByDay = const {},
    List<GoalSummary> goals = const [],
    List<BillSummary> recurringBills = const [],
  }) {
    final labeler = _Labeler();
    final expense = summary.expense;

    final topCats = <Map<String, Object?>>[];
    for (final c in topExpenseCategories) {
      final key = labeler.category(c.categoryId, c.name);
      topCats.add({
        'id': key,
        'amount': _round(c.total),
        'pct_of_expense': expense > 0 ? _round1(c.total / expense * 100) : 0.0,
      });
    }

    final modes = _buildModes(modeBreakdown, labeler, expense);

    final budgetList = <Map<String, Object?>>[];
    for (final b in budgets) {
      final key = labeler.category(b.budget.categoryId, b.categoryName);
      final effective = b.effectiveAmount;
      budgetList.add({
        'id': key,
        'spent': _round(b.spent),
        'effective': _round(effective),
        'over': b.isOver,
        if (b.isOver) 'over_by': _round(b.spent - effective),
      });
    }

    final cashflowList = <Map<String, Object?>>[];
    for (final m in cashflow) {
      cashflowList.add({
        'month': '${m.year}-${m.month.toString().padLeft(2, '0')}',
        'income': _round(m.income),
        'expense': _round(m.expense),
        'net': _round(m.net),
      });
    }

    final accBalances = _buildAccountBalances(accountBalances, labeler);
    final tags = _buildTags(tagBreakdown, labeler);
    final trendCats =
        _buildCategoryTrend(categoryBreakdown3mo, topExpenseCategories, labeler);
    final txFrequency = _buildTxFrequency(expenseCount, daysInPeriod);
    final dayDist = _buildDayDistribution(dailyExpenseByDay);
    final goalsList = _buildGoals(goals, labeler);
    final billsList = _buildBills(recurringBills, labeler);

    return (
      json: {
        'currency_note':
            'All amounts in the user\'s currency, summed across accounts with no '
            'FX conversion. Treat the unit as one currency.',
        'period': period,
        'summary': {
          'income': _round(summary.income),
          'expense': _round(expense),
          'net': _round(summary.net),
          'opening_balance': _round(summary.openingBalance),
          'closing_balance': _round(summary.closingBalance),
        },
        'top_expense_categories': topCats,
        'payment_modes': modes,
        if (accBalances.isNotEmpty) 'account_balances': accBalances,
        if (budgetList.isNotEmpty) 'budgets': budgetList,
        if (tags.isNotEmpty) 'tag_breakdown': tags,
        if (trendCats.isNotEmpty) 'category_trend_3mo': trendCats,
        if (txFrequency != null) 'tx_frequency': txFrequency,
        if (dayDist.isNotEmpty) 'day_distribution': dayDist,
        if (goalsList.isNotEmpty) 'goals': goalsList,
        if (billsList.isNotEmpty) 'recurring_bills': billsList,
        'cashflow_6mo': cashflowList,
        'savings_rate_trend': savingsRateTrend(cashflow),
        // biggestSpendNote / biggestSpendTitle / biggestSpendAmount are
        // deliberately NOT included — they are single-transaction details.
        if (shareNames && labeler.legend.isNotEmpty) 'legend': labeler.legend,
      },
      legend: labeler.legend,
    );
  }

  // ── Aggregate builders (shared by Ask + Report) ──────────────────────────

  /// Every active category (incl 0-spend), labeled, with current-month amount,
  /// pct of total expense, and a uniform 3-month trend (zeros when no 3-mo data
  /// was supplied). Sorted by current-month amount desc. Used by [buildAskContext]
  /// so the AI sees the full category directory, not just top spenders.
  List<Map<String, Object?>> _buildAllCategories(
      List<AiEntityName> all,
      List<List<CategoryTotal>> breakdown3mo,
      _Labeler labeler,
      double expense) {
    final has3 = breakdown3mo.length == 3;
    final currentMap = has3
        ? {for (final c in breakdown3mo[2]) c.categoryId: c.total}
        : const <String, double>{};
    final out = <Map<String, Object?>>[];
    for (final c in all) {
      final key = labeler.category(c.id, c.name);
      final amt = currentMap[c.id] ?? 0.0;
      final trend = has3
          ? breakdown3mo
              .map((m) => _round(
                  m.where((x) => x.categoryId == c.id).fold(0.0, (s, x) => s + x.total)))
              .toList()
          : [0.0, 0.0, 0.0];
      out.add({
        'id': key,
        'amount': _round(amt),
        'pct_of_expense': expense > 0 ? _round1(amt / expense * 100) : 0.0,
        'trend_3mo': trend,
      });
    }
    out.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
    return out;
  }

  /// Every active payment mode (incl 0-spend), labeled, sorted by amount desc.
  /// Used by [buildAskContext].
  List<Map<String, Object?>> _buildAllModes(
      List<AiEntityName> all,
      List<ModeTotal> modeBreakdown,
      _Labeler labeler,
      double expense) {
    final amtMap = {for (final m in modeBreakdown) m.modeId: m.total};
    final out = <Map<String, Object?>>[];
    for (final m in all) {
      final key = labeler.mode(m.id, m.name);
      final amt = amtMap[m.id] ?? 0.0;
      out.add({
        'id': key,
        'amount': _round(amt),
        'pct_of_expense': expense > 0 ? _round1(amt / expense * 100) : 0.0,
      });
    }
    out.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
    return out;
  }

  /// Every active tag (incl 0-spend), labeled, sorted by amount desc. Used by
  /// [buildAskContext].
  List<Map<String, Object?>> _buildAllTags(
      List<AiEntityName> all,
      List<TagTotal> tagBreakdown,
      _Labeler labeler,
      double expense) {
    final amtMap = {for (final t in tagBreakdown) t.tagId: t.total};
    final out = <Map<String, Object?>>[];
    for (final t in all) {
      final key = labeler.tag(t.id, t.name);
      final amt = amtMap[t.id] ?? 0.0;
      out.add({
        'id': key,
        'amount': _round(amt),
        'pct_of_expense': expense > 0 ? _round1(amt / expense * 100) : 0.0,
      });
    }
    out.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
    return out;
  }

  List<Map<String, Object?>> _buildModes(
      List<ModeTotal> modeBreakdown, _Labeler labeler, double expense) {
    final modes = <Map<String, Object?>>[];
    for (final m in modeBreakdown) {
      final key = labeler.mode(m.modeId, m.name);
      modes.add({
        'id': key,
        'amount': _round(m.total),
        'pct_of_expense': expense > 0 ? _round1(m.total / expense * 100) : 0.0,
      });
    }
    return modes;
  }

  List<Map<String, Object?>> _buildAccountBalances(
      List<AccountBalance> accountBalances, _Labeler labeler) {
    final out = <Map<String, Object?>>[];
    for (final a in accountBalances) {
      final key = labeler.account(a.id, a.name);
      out.add({'id': key, 'balance': _round(a.balance)});
    }
    return out;
  }

  List<Map<String, Object?>> _buildTags(
      List<TagTotal> tagBreakdown, _Labeler labeler) {
    final out = <Map<String, Object?>>[];
    for (final t in tagBreakdown) {
      final key = labeler.tag(t.tagId, t.name);
      out.add({'id': key, 'amount': _round(t.total)});
    }
    return out;
  }

  /// Per-category spend over the last 3 months for the top categories. Only
  /// emitted when exactly 3 monthly breakdowns are supplied (oldest→newest);
  /// otherwise omitted (the field is optional).
  List<Map<String, Object?>> _buildCategoryTrend(
      List<List<CategoryTotal>> breakdown3mo,
      List<CategoryTotal> topCats,
      _Labeler labeler) {
    if (breakdown3mo.length != 3) return const [];
    final out = <Map<String, Object?>>[];
    for (final c in topCats.take(5)) {
      final key = labeler.category(c.categoryId, c.name);
      final months = breakdown3mo.map((month) {
        final found = month.where((m) => m.categoryId == c.categoryId);
        return _round(found.isEmpty ? 0.0 : found.first.total);
      }).toList();
      out.add({'id': key, 'months': months});
    }
    return out;
  }

  Map<String, Object?>? _buildTxFrequency(int? expenseCount, int? daysInPeriod) {
    if (expenseCount == null || daysInPeriod == null || daysInPeriod <= 0) {
      return null;
    }
    return {
      'expense_count': expenseCount,
      'per_day_avg': _round1(expenseCount / daysInPeriod),
    };
  }

  /// Spend bucketed by day-of-month thirds (1-10, 11-20, 21-31), enabling
  /// salary-cycle crunch reasoning. Only emitted when daily data is supplied.
  List<Map<String, Object?>> _buildDayDistribution(Map<String, double> daily) {
    if (daily.isEmpty) return const [];
    final buckets = <String, double>{
      '1-10': 0.0,
      '11-20': 0.0,
      '21-31': 0.0,
    };
    daily.forEach((date, amount) {
      final day = int.tryParse(date.split('-').last) ?? 0;
      if (day >= 1 && day <= 10) {
        buckets['1-10'] = buckets['1-10']! + amount;
      } else if (day <= 20) {
        buckets['11-20'] = buckets['11-20']! + amount;
      } else if (day >= 21) {
        buckets['21-31'] = buckets['21-31']! + amount;
      }
    });
    return [
      {'bucket': '1-10', 'amount': _round(buckets['1-10']!)},
      {'bucket': '11-20', 'amount': _round(buckets['11-20']!)},
      {'bucket': '21-31', 'amount': _round(buckets['21-31']!)},
    ];
  }

  /// Goals as anonymized aggregates only — `goal_N` + figures. No name, icon,
  /// or note ever leaves the device.
  List<Map<String, Object?>> _buildGoals(
      List<GoalSummary> goals, _Labeler labeler) {
    final out = <Map<String, Object?>>[];
    for (final g in goals) {
      final key = labeler.goal(g.id, g.name);
      final pct = g.target > 0 ? _round1(g.saved / g.target * 100) : 0.0;
      out.add({
        'id': key,
        'target': _round(g.target),
        'saved': _round(g.saved),
        'pct': pct,
        if (g.monthsLeft != null) 'months_left': g.monthsLeft,
        if (g.monthlyCommitment != null)
          'monthly_commitment': _round(g.monthlyCommitment!),
      });
    }
    return out;
  }

  /// Recurring bills as anonymized aggregates only — `bill_N` + amount/cadence/
  /// next-due/source. No name or note ever leaves the device.
  List<Map<String, Object?>> _buildBills(
      List<BillSummary> bills, _Labeler labeler) {
    final out = <Map<String, Object?>>[];
    for (final b in bills) {
      final key = labeler.bill(b.id, b.name);
      out.add({
        'id': key,
        'amount': _round(b.amount),
        'cadence': b.cadence,
        if (b.nextDueInDays != null) 'next_due_in_days': b.nextDueInDays,
        'source': b.source,
      });
    }
    return out;
  }

  /// Compute a coarse savings-rate trend label from the cashflow series.
  /// Shared by the payload and (loosely) mirrors the local insight engine.
  static String savingsRateTrend(List<MonthTotal> cashflow) {
    if (cashflow.length < 2) return 'unknown';
    double rate(MonthTotal m) => m.income > 0 ? m.net / m.income : 0.0;
    final rates = cashflow.map(rate).toList();
    final n = rates.length.toDouble();
    final xs = List.generate(rates.length, (i) => i.toDouble());
    final meanX = xs.reduce((a, b) => a + b) / n;
    final meanY = rates.reduce((a, b) => a + b) / n;
    var num = 0.0, den = 0.0;
    for (int i = 0; i < rates.length; i++) {
      num += (xs[i] - meanX) * (rates[i] - meanY);
      den += (xs[i] - meanX) * (xs[i] - meanX);
    }
    final slope = den == 0 ? 0.0 : num / den;
    if (slope > 0.02) return 'rising';
    if (slope < -0.02) return 'falling';
    return 'flat';
  }

  static double _round(double v) => (v * 100).round() / 100;
  static double _round1(double v) => (v * 10).round() / 10;

  /// Recursively collect every numeric value in a built payload JSON, so the
  /// caller can pass them to [AiGatekeeper] as `sentAmounts` for the numeric-
  /// correspondence check. The figures are already rounded by the builder, so
  /// they match what the LLM saw to within the gatekeeper's ~2% tolerance.
  static Set<double> collectAmounts(Map<String, Object?> json) {
    final amounts = <double>{};
    void walk(Object? v) {
      if (v is num) {
        amounts.add(v.toDouble());
      } else if (v is Map) {
        for (final e in v.values) {
          walk(e);
        }
      } else if (v is List) {
        for (final e in v) {
          walk(e);
        }
      }
    }
    walk(json);
    return amounts;
  }
}

/// Assigns opaque rank keys to entity ids in first-seen order, and always
/// records a `label → real-name` legend. The legend is returned to the caller
/// (via [AiContext]) so [AiGatekeeper] can restore real names on-device; it is
/// embedded in the outbound JSON **only** when `shareNames` is true (gated at
/// the build-method return sites, not here).
class _Labeler {
  _Labeler();
  final legend = <String, String>{};
  final _catKeys = <String, String>{};
  final _accKeys = <String, String>{};
  final _modeKeys = <String, String>{};
  final _tagKeys = <String, String>{};
  final _goalKeys = <String, String>{};
  final _billKeys = <String, String>{};
  int _catN = 0, _accN = 0, _modeN = 0, _tagN = 0, _goalN = 0, _billN = 0;

  String category(String id, String name) =>
      _key(_catKeys, 'cat', _catN, id, name, () => _catN++);
  String account(String id, String name) =>
      _key(_accKeys, 'acc', _accN, id, name, () => _accN++);
  String mode(String id, String name) =>
      _key(_modeKeys, 'mode', _modeN, id, name, () => _modeN++);
  String tag(String id, String name) =>
      _key(_tagKeys, 'tag', _tagN, id, name, () => _tagN++);
  String goal(String id, String name) =>
      _key(_goalKeys, 'goal', _goalN, id, name, () => _goalN++);
  String bill(String id, String name) =>
      _key(_billKeys, 'bill', _billN, id, name, () => _billN++);

  String _key(Map<String, String> map, String prefix, int n, String id,
      String name, void Function() bump) {
    return map.putIfAbsent(id, () {
      final key = '${prefix}_$n';
      // Always record the legend on-device (used by AiGatekeeper.restore).
      legend[key] = name;
      bump();
      return key;
    });
  }
}