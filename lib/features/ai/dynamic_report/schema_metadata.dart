/// Frozen, PII-stripped schema metadata sent to the LLM so it can author chart
/// specs (Phase 2). This is **hand-authored and deliberately frozen** — it is
/// NOT generated from the live Drift schema, so a future PII column can never
/// accidentally leak into the prompt.
///
/// Privacy contract: this blob contains only table/column *names* and *kinds*
/// for the safe aggregate tables. It NEVER includes:
/// - PII columns (`note`, `receipt_path`, `phone`, `photo_path`,
///   `device_contact_id`, `phones`),
/// - the `due_contacts` / `due_entries` / `due_settlements` tables (contacts +
///   lend/borrow PII),
/// - the `ai_threads` / `ai_messages` tables (chat content),
/// - any row data, real amounts, account balances, or names.
///
/// The LLM uses this only to pick a [DataProvider] + params + write titles/
/// captions using opaque labels. It never authors SQL against these tables
/// directly unless `customSql` is enabled (and then [SqlGuard] re-validates
/// against the same allow-list, defense in depth).
library;

/// The schema blob, ready to embed in `kReportSpecSystemPrompt`.
const String kSchemaMetadata = r'''
# SpendWise on-device schema (safe subset)

You propose charts by emitting a JSON spec — you do NOT run SQL unless the user
has enabled custom SQL. Pick a `provider` from the menu below and set its params.
Titles/captions use the opaque labels provided in the user context (e.g. cat_0,
mode_1); they are restored to real names on-device. Never invent names or
numbers.

## Tables you may reason about (aggregate / safe)
- transactions: id, amount (REAL), transaction_date (ISO text), kind (TEXT enum),
  account_id, category_id, mode_id, created_at.  (note / receipt_path are
  private — not shown to you.)
- accounts: id, name, opening_balance (REAL), kind (TEXT enum).
- categories: id, name, icon, color (#RRGGBB), kind (TEXT enum: income|expense).
- modes: id, name, icon, kind (TEXT enum: income|expense).
- budgets: id, category_id, amount (REAL), period (TEXT: weekly|monthly|yearly).

## transaction.kind enum
- income, expense, transfer_in, transfer_out
  (transfers move money between accounts — they are NOT income/expense; treat
  transfer_in/transfer_out as pairs that net to zero for spending analysis.)

## DataProvider menu (pick one `provider` per chart)
- topCategories   params: {limit:int}        → top expense categories (month)
- cashflow6mo     params: {count:int}       → rolling income/expense by month
- budgets         params: {}                → budget progress (month)
- modes           params: {kind:string}     → payment-mode breakdown (month)
- monthlySummary  params: {}                → month income/expense/net/opening/closing
- customSql       params: {sql:string}      → ONLY if user enabled custom SQL;
                                              a single read-only SELECT. Blocked:
                                              due_*, ai_*, note, receipt_path,
                                              phone, photo_path, device_contact_id,
                                              phones; no DROP/INSERT/UPDATE/etc.;
                                              LIMIT auto-applied.

## ChartType: pie | bar | line | progress | list | stat

## Output JSON shape (respond with ONLY this object, no prose, no markdown)
{
  "charts": [
    {"type":"pie","title":"Where it went","provider":"topCategories",
     "params":{"limit":8}},
    {"type":"bar","title":"Cashflow (6 months)","provider":"cashflow6mo",
     "params":{"count":6}},
    {"type":"progress","title":"Budgets","provider":"budgets","params":{}}
  ],
  "narrativeSeed":"One or two sentences seeding the narrative, using opaque labels."
}

## Shot examples
- Top 3 expense categories: {"type":"pie","title":"Where it went",
  "provider":"topCategories","params":{"limit":3}}
- Net cashflow trend: {"type":"line","title":"Net cashflow trend",
  "provider":"cashflow6mo","params":{"count":6},
  "series":[{"field":"net","name":"Net"}]}
- This month at a glance: {"type":"stat","title":"Net this month",
  "provider":"monthlySummary","params":{},"series":[{"field":"net"}],
  "caption":"Income minus expense for the month."}
- Budget status: {"type":"progress","title":"Budgets",
  "provider":"budgets","params":{}}

## Tone
Write for an Indian personal-finance user: plain INR, observation not alarm, no
shame about overspending. Prefer useful comparisons (vs last month, run-rate vs
typical). Keep narrativeSeed to 1–2 sentences, no tables, no fenced code.
''';