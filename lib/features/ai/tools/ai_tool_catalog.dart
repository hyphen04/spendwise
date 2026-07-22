/// The fixed set of on-device tools the AI may call. Safety comes from this set
/// being closed and named — the LLM never authors SQL. Each tool returns
/// aggregates only (no rows, no notes, no contact data); entity references in
/// args use opaque labels (`cat_3`) the executor resolves to real ids on-device.
class AiToolDef {
  const AiToolDef({required this.name, required this.description, required this.args});
  final String name;
  final String description;
  /// `argName → "type: description"`. Required args are described as such.
  final Map<String, String> args;
}

const Map<String, AiToolDef> aiToolCatalog = {
  'list_entities': AiToolDef(
    name: 'list_entities',
    description:
        'List all active entities of a kind with their labels (+ real names if '
        'the legend is shared) and the total count. Use this to answer "how '
        'many X do I have" and to discover what exists.',
    args: {'kind': 'String (required): one of category, account, mode, goal, bill'},
  ),
  'breakdown': AiToolDef(
    name: 'breakdown',
    description:
        'Spend broken down by a dimension over a date range. Returns '
        '[{id, amount, count, pct}] sorted desc, capped top-20 + an "other" '
        'rollup. Handles "per-category spend in October", "UPI spend last week".',
    args: {
      'group_by': 'String (required): category | account | mode',
      'from': 'String (required): ISO date yyyy-MM-dd, inclusive',
      'to': 'String (required): ISO date yyyy-MM-dd, exclusive',
      'kind': 'String (optional): expense | income | all (default expense)',
    },
  ),
  'monthly_totals': AiToolDef(
    name: 'monthly_totals',
    description:
        'Per-month income/expense/net over a date range (capped 24 months). '
        'Handles "how much did I spend last March", year-over-year.',
    args: {
      'from': 'String (required): ISO date yyyy-MM-dd, inclusive',
      'to': 'String (required): ISO date yyyy-MM-dd, exclusive',
    },
  ),
  'filtered_totals': AiToolDef(
    name: 'filtered_totals',
    description:
        'Count + total + per-dimension breakdowns for transactions matching '
        'filters. Returns {count, total, by_category, by_mode, by_account} '
        '(each capped top-10 + other). NO rows, NO notes, NO merchants. '
        'Handles "how many transactions over 5000 in April", "total UPI spend '
        'last week". Entity filters use opaque labels (cat_3).',
    args: {
      'from': 'String (required): ISO date yyyy-MM-dd, inclusive',
      'to': 'String (required): ISO date yyyy-MM-dd, exclusive',
      'amount_min': 'Number (optional): minimum transaction amount',
      'amount_max': 'Number (optional): maximum transaction amount',
      'category': 'String (optional): opaque label cat_N',
      'account': 'String (optional): opaque label acc_N',
      'mode': 'String (optional): opaque label mode_N',
      'kind': 'String (optional): expense | income | all (default expense)',
    },
  ),
  'budget_status': AiToolDef(
    name: 'budget_status',
    description:
        'Per-budget status for a month (default current): {id, spent, '
        'effective, over, over_by}.',
    args: {'month': 'String (optional): yyyy-MM (default current month)'},
  ),
  'goals_overview': AiToolDef(
    name: 'goals_overview',
    description:
        'Your savings goals as anonymized aggregates: {id, target, saved, pct, '
        'months_left?, monthly_commitment?}. No names unless the legend is shared.',
    args: {},
  ),
  'bills_overview': AiToolDef(
    name: 'bills_overview',
    description:
        'Your recurring bills as anonymized aggregates: {id, amount, cadence, '
        'next_due_in_days?, source}. No names unless the legend is shared.',
    args: {},
  ),
};

/// The catalog as it appears in the system prompt.
String get kAiToolCatalogText {
  final buf = StringBuffer('You may call these on-device tools to look up the '
      'user\'s data. To call one, reply with ONLY a JSON object: '
      '{"tool": "<name>", "args": {…}}. Results come back as anonymized JSON; '
      'use them to answer. Tools return aggregates only — never rows, notes, '
      'or contact details. Entity references in args use the opaque labels from '
      'the summary (cat_N, acc_N, mode_N, goal_N, bill_N).\n');
  for (final def in aiToolCatalog.values) {
    buf.writeln('\n- ${def.name}: ${def.description}');
    if (def.args.isNotEmpty) {
      for (final e in def.args.entries) {
        buf.writeln('    - ${e.key}: ${e.value}');
      }
    }
  }
  return buf.toString();
}