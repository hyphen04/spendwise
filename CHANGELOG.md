# Changelog

All notable changes to SpendWise are listed here.
Format: `## vX.X.X — YYYY-MM-DD` with Added / Changed / Fixed sections.

## Unreleased

### Added
- **Richer AI Copilot chat snapshot**: the Ask SpendWise chat now sees **all** your categories, payment modes, and tags — including ones with no spend this month (not just the top-5 spend categories) — plus `category_count` / `mode_count` / `tag_count` scalars and a **12-month cashflow** series. The AI can now answer "how many categories do I have?" and questions about any category by name, instead of claiming a category "doesn't exist." Privacy is unchanged: only anonymized aggregates and opaque labels leave the device; real names still require the opt-in "Share names" toggle (the name↔label legend still never leaves without it).
- **Rich AI chat rendering**: AI replies (chat, narrative report, and the Smart Insights viewer) now render with `flutter_markdown` via a new styled `AiMarkdown` widget — tables, fenced code blocks (with a Copy button), nested lists, bold/strike/inline-code, and tappable links — instead of the limited changelog parser. The system prompts now allow tables and code blocks. The changelog/What's New UI still uses the lightweight `ChangelogMarkdown` parser (unchanged).
- **Smarter, more helpful AI**: the AI now sees a richer anonymized picture of your finances — account balances, payment-mode breakdown, top tags, a 3-month per-category trend, transaction frequency, and a day-of-month spend distribution — plus your **savings goals** and **recurring bills** as opaque aggregates (`goal_N` / `bill_N` with target/saved/progress and amount/cadence/next-due — **no names, no notes**). Coaching can now reason about budget-vs-goals and upcoming bills. The name↔label legend never leaves the device (sent only with the opt-in "Share names" toggle).
- **Advanced on-device gatekeeper**: every AI text surface — chat, report, insight polish, and weekly-digest polish — now runs through the gatekeeper, which in addition to restoring labels and scrubbing PII performs **numeric-correspondence** checks (flags figures that match nothing sent and exceed the data range — catches hallucinated numbers) and, when "Share names" is on, **hallucinated-name** detection (flags category/account/mode/tag names the AI invents). Polish and digest no longer bypass the gatekeeper.
- **Smart Insights, fullscreen**: Smart Insights are now a WhatsApp-status-style fullscreen viewer — swipe or tap the left/right edges to move between cards, a progress bar paces each, and the full coaching text is shown (no more "…" truncation). Open it from the compact "Smart Insights" row on the Reports hub.
- **Custom Reports (builder)**: you can now build your own report on-device — pick a group-by dimension (category / account / mode / tag / day / month), a metric (sum / count / avg), a kind and date range, optional filters, and a chart type (bar / pie / line / list / stat), with a live preview. Save it and reopen it from the Reports hub's "Your Reports" section. Swipe to edit or delete. The spec is **never sent to the AI**; the executor only reads the safe table subset (transactions + accounts/categories/modes/tags), never notes, receipt paths, or the on-device-only `due_*`/`ai_*`/`goals`/`recurring_items` tables.
- **DB schema v14 → v15**: new `custom_reports` table (id, name, specJson, createdAt, updatedAt) for user-authored on-device reports. Created with `createTable` on upgrade — additive, no data loss, no PII, never sent to the AI.
- **Project tooling in `.claude/`**: two new skills (`spendwise-ai-payload-extension`, `spendwise-custom-report`) encode the safe AI-payload-extension and custom-report workflows; a new `@spendwise-supervisor` agent orchestrates multi-track implementation in worktrees with per-track review + privacy-audit gating. New hooks remind you to run the privacy audit when AI-boundary/PII-table files are edited, and run `flutter analyze` before a commit.
- **Unified bottom sheet**: a single reusable `showSpendWiseSheet` component now backs every bottom sheet in the app, with a consistent drag handle and correct safe-area handling — sheets no longer hand-roll their own handles or sit behind the iPhone notch / Dynamic Island / Android punch-hole on any device. Each sheet owns its close affordance in its title row (well below the status bar, never behind it), and tall sheets are capped to the vertical safe area so their top edge stops at the status-bar boundary.
- **On-demand numpad for quick entry**: the Add Due Entry sheet now opens short — contact, direction, date, note, a tappable amount, and Save. Tap the amount to expand a focused numpad; confirm (✓) to save, or hide-keypad to collapse back. The amount sits centered with backspace + hide-keypad on the right, is grouped Indian-style (e.g. `1,00,00,000`), and shrinks to fit instead of cutting off large figures with "…".
- **Month / 6-Month Forecast (run-rate projection)**: the Forecast report (Reports → Forecast) and a compact "at a glance" card on Home now show a run-rate projection with a **Monthly / 6 Months pill**. **Monthly** shows a **progress ring** that fills as the month goes, with your projected month-end balance in the centre — a single month's ~30 days don't fill a square grid nicely, so a ring reads cleaner than a calendar. **6 Months** is a compact GitHub-style spending heatmap of the rolling 6 calendar months (small squares shaded by each day's spend — darker = more, today ringed, future days as outlined placeholders so the whole period is countable; month labels on top). The hero number is your **projected balance** — "what you'd have left", not earnings — with a no-shame outlook pill (warm amber, never red). Monthly projects to month-end from your spend pace (income taken as-is, so a mid-month salary isn't doubled); 6-month projects where you'd be in 6 months from your average monthly net over the last 6 completed months. Stat tiles show how the number is built, and (monthly) a per-category run-rate section compares this month to your usual pace. Labels spell out the assumptions in plain words. All on-device; no AI, no network.
- **Weekly Digest**: a new screen (Settings → Weekly Digest) shows your week at a glance — spent this week vs last week (with a no-shame ▲/▼ delta), your top category, short observational bullets, and one friendly tip. It's computed **entirely on-device** (no network for the core). Tap **Share as text** to send the summary anywhere via the system share sheet — the summary is yours to keep; nothing is uploaded. When AI is on with a key set, an optional **AI summary** card rewrites the digest as a 2-sentence friendly note (category/mode names are anonymized to opaque labels before leaving the device and restored after — the legend never leaves; falls back to the deterministic text otherwise).
- **Savings Goals**: a new screen (Settings → Savings Goals) for *savings* targets — distinct from spend-cap budgets. Create a goal (name, icon, color, target amount, optional deadline, optional "Save More Tomorrow" monthly commitment, optional linked account), then add contributions anytime and watch the progress ring fill. The screen shows no-shame status copy ("Just started" / "Building up" / "Almost there" / "Goal reached") and, when there's a deadline, how many months are left. Swipe to edit or delete (shared confirm dialog), tap to edit, snackbar after every change. Goals live on this device only — the `goals` table has no PII and is never part of the AI schema metadata, so it never leaves the device.
- **Bills & Subscriptions**: a new screen (Settings → Bills & Subscriptions) tracks your recurring bills and subscriptions — both ones you add manually and ones SpendWise **detects from your transaction history** (≥3 near-equal charges at a consistent cadence). Each bill shows a **no-shame "due in Nd / overdue by Nd" badge** so you know what's coming without alarm. Swipe a row to edit or delete (with the shared confirm dialog), tap to edit. A "Re-detect" action re-scans the last 12 months and seeds anything new, idempotently. Detection runs **entirely on-device** — the `recurring_items` table holds only your own bill names/amounts (no phone/photo) and is never part of the AI schema metadata, so it never leaves the device. The bill `note` field is also on-device only.
- **AI Report is now visual**: the AI Report screen always shows accurate on-device charts — a **category donut**, a **6-month income-vs-expense cashflow bar chart**, and **budget progress bars** — built from your real aggregations. The charts render even with AI off (no key needed), so the report is useful and visual out of the box. When AI is on, the streamed narrative appears below the charts as coaching. The LLM never draws the charts; they come straight from your own data, so they're always correct.
- **Dynamic charts (experimental)**: turn on "Dynamic charts" in AI settings and the AI picks *which* charts to show for your month — it emits a declarative chart spec (type + named on-device data provider + title), the app executes it locally with `fl_chart` and renders real data. The LLM sees only **schema metadata + opaque labels** (no raw rows, no real amounts, no notes/names); titles/labels are restored on-device by the gatekeeper. An opt-in **"Allow AI to query my data (custom SQL)"** sub-toggle lets the AI propose read-only SQL, run through a safety pipeline (SELECT-only, allow-listed tables, PII columns and `due_*`/`ai_*` tables hard-blocked, single-statement, LIMIT + timeout). Off by default; falls back to the default 3-chart spec on any error.
- **On-device AI gatekeeper (warden)**: every AI reply — in the Ask chat and the report — now passes through an on-device gatekeeper before it reaches you. It **restores opaque labels to real names locally** (`cat_0` → "Food & Dining"), so even with "Share names" off you see real category/mode names in answers and the report — the name↔label legend never leaves your device. It also **validates** the reply: empty/garbage is blocked with an error + Retry; leftover/invented labels, leaked-PII-looking tokens, or numbers wildly outside your data are flagged with a small **"Checked on-device"** note while the text is still shown. Notes, contact names/phones/photos, and receipt paths never enter this path.
- **On-demand AI Report with PDF export**: Reports → "AI Report" opens a dedicated screen where you pick a month and generate a streaming, narrative financial report (Overview / Spending / Budgets / Cashflow / Takeaways) rendered with the app's markdown viewer. **Export to PDF** shares a clean, readable PDF (headings, bullets, bold) via the system share sheet. The report context is built by `AiPayloadBuilder` — only anonymized aggregations (opaque category ids like `cat_0`, totals, trends) leave the device; notes, contact names/phones/photos, and receipt paths are never included. Works only with AI enabled + an API key set.
- **AI-polished insights (on-demand)**: In Reports → Smart Insights, a "Get AI coaching on these" button asks the LLM to rewrite the locally-computed insights as clearer, actionable coaching nudges. Real category and payment-mode names are **replaced with opaque labels (`cat_0`, `mode_1`) before they leave the device** and restored on-device afterward — the name↔label legend never leaves your phone. A "✨ AI-polished" badge + "View raw / View polished" toggle lets you compare; any failure falls back to the local insights. On-demand (not automatic) to keep token usage conservative.
- **AI Copilot chat history**: Ask-SpendWise conversations are now saved on this device and listed on a new **Chats** screen (tap the history icon in the chat app bar, or open a chat from Reports → "Ask SpendWise AI"). Reopen any chat to continue it; swipe a row to **rename** or **delete** (with the shared confirm dialog). Long-press any message to **edit & resend** (regenerates from that point), **copy**, **delete a single message**, or **regenerate** the last reply. Empty chats you back out of are pruned automatically. Chats are stored on-device only — never uploaded.
- **DB schema v11 → v12**: two new tables, `ai_threads` (id, title, preview, createdAt, updatedAt) and `ai_messages` (id, threadId, role, content, isError, createdAt). Brand-new tables created with `createTable` on upgrade — additive, no data loss. Stored messages are local user content; the hidden, anonymized context preamble is rebuilt in memory per session and is never persisted.
- **DB schema v12 → v13**: new `recurring_items` table (id, name, amount, categoryId, accountId?, modeId?, cadence, nextDueDate, lastSeenDate?, source, isActive, note, createdAt, updatedAt) for Bills & Subscriptions. Created with `createTable` on upgrade — additive, no data loss, no NOT NULL columns without a default. Detected recurring items are seeded idempotently on first open of the Bills screen (and via "Re-detect") from existing expense history; nothing is deleted. The table contains no PII and is excluded from the AI schema metadata.
- **DB schema v13 → v14**: new `goals` table (id, name, icon, color, targetAmount, savedAmount, targetDate?, linkedAccountId?, monthlyCommitment?, isActive, createdAt, updatedAt) for Savings Goals. Created with `createTable` on upgrade — additive, no data loss, no NOT NULL columns without a default. No PII; excluded from the AI schema metadata.
- **Project tooling in `.claude/`**: four reusable skills (`spendwise-release`, `spendwise-db-schema-change`, `spendwise-privacy-audit`, `spendwise-dynamic-report-add-provider`) encode the release, DB-schema, privacy-audit, and report-extension workflows so they run the same way every time. Three project agents (`@spendwise-explorer` for scoped codebase questions, `@spendwise-privacy-auditor` to adversarially audit AI/report changes, `@spendwise-reviewer` to review a diff against the project rules) assist with the recurring review tasks. `CLAUDE.md` now points to them and documents the AI privacy invariant + dynamic-report rules.
- **Device-contacts enrichment for Dues & Tabs**: When adding or editing a Dues contact, an "Import from phone" button opens the native contact picker and fills in the person/vendor's real name, phone number(s), and photo (with your consent). The contact detail screen now shows the photo avatar and **Call + WhatsApp action buttons** (Call dials via the system dialer; WhatsApp opens the chat with that number directly via the `whatsapp://` scheme, falling back to `wa.me`); list rows show the photo thumbnail. A phone-based dedup guard prompts you to open an existing contact instead of creating a duplicate. Contacts are read **on-device only and never uploaded** (the app has no server).
- **Multiple numbers per contact**: importing a device contact now keeps *all* its numbers (mobile / home / work), each with its label, instead of forcing a choice at import time. When you tap **Call** or **WhatsApp** and the contact has more than one number, a chooser sheet lets you pick which to use; with a single number it acts directly. The detail card shows the primary number with a `+N` badge when there are more. Dedup matches any of a contact's numbers, not just the primary.
- **Settings → Contact Access toggle** with a privacy subtitle stating contacts are read on-device and never uploaded. The OS contacts permission is requested when you turn it on or when you first import.
- **Phone normalization, dedup & a `ContactPhone` model** (`lib/app/utils/phone_utils.dart`): numbers are normalized to a last-10-digit key so `+91…`, `091…`, and bare 10-digit forms match; the multi-number list is stored as JSON in `due_contacts.phones`.
- **Shared `ContactAvatar` widget** for the photo-vs-emoji fallback, reused by the detail screen, list rows, and the import preview.
- **Delete contact** from the contact detail screen's app bar (beside Edit), with the same confirm-dialog + "settle or delete entries first" guard as the list swipe-delete.
- **Settlement date in the Settle sheet**: you can now pick the date a settlement was posted (defaults to today; back-dateable to 2000). That date is used for both the settlement's record *and* the linked transaction's posting date, so Reports count the settlement transaction on the settlement date — not necessarily today.
- **Edit settlement date**: on the settlement detail sheet, an edit-calendar action (and the tappable date) lets you re-date an existing settlement. It updates the settlement record and its linked transaction together, so an old settlement logged on the wrong day can be moved into the right report month without deleting and re-settling. No migration — existing settlements keep their original date and stay valid.

### Changed
- **Reports hub redesigned**: the flat wall of 10 report cards is now grouped into clear sections — Overview, Spending, Accounts & Planning, Dues (on-device only), AI Copilot, and Your Reports — with a hero "New custom report" card. All 10 built-in reports are retained; the hierarchy makes the screen scannable instead of overwhelming.
- **`sql_guard` now also blocks `goals` and `recurring_items`** in the opt-in custom-SQL path, matching their exclusion from the AI schema metadata (bills and goals stay on-device only).
- **“Top Spends” report is now labeled honestly as “Top Categories”.** The report (`topSpends`) always ranked your spending by *category*, not individual transactions — the old “largest individual transactions” description was wrong. The card and report title now say “Top Categories” / “Where you spent the most this month”.
- **Reports hub now uses a single shared `ReportCard` widget.** A polished local `_ReportCard` duplicate lived in `reports_screen.dart` while a divergent `widgets/report_card.dart` went unused; the shared widget now carries the polished design and the local duplicate is gone — no visual change, one source of truth.
- **Real names now appear in AI answers even when "Share names" is off.** The gatekeeper restores labels on-device, so the default (anonymize-by-default) gives you readable answers without any names leaving the device. The "Share category & account names" setting now means: *send* the names to the LLM during generation (for more specific advice) vs. keep them on-device and restore after. Default remains off.
- **AI navigation is now a strict 2-screen stack**: opening or starting a chat **replaces** the current AI screen instead of pushing a new one, so the back history is always just *chat ↔ chats list* (no infinite openings, and back from the list returns to where you came from). Transitions between AI screens are now a smooth 260 ms slide + fade.
- **Chats list no longer flickers**: threads with zero messages are filtered out of the list query, so an empty "new chat" row no longer flashes before being pruned.
- **What's New & update sheets no longer carry duplicate close buttons** — each sheet has a single close affordance in its title row (seated below the status bar), and the What's New sheet leaves a comfortable gap below the notch / punch-hole so it doesn't crowd the top of the screen.
- **Redesigned contact detail screen**: the hero is now a single flat contact card (avatar, name, tappable phone, person/vendor tag, balance with ↑/↓ direction, and Call + WhatsApp actions) matching the app's surface + thin-outline card language; tighter spacing throughout. Section headers use the lowercase label + count style from the home screen.
- **DB schema v9 → v10 → v11**: v10 added nullable `phone`, `photo_path`, and `device_contact_id` columns to `due_contacts`; v11 added a nullable `phones` JSON column holding the full number list. Additive migrations; no data loss, no `DEFAULT` required.
- **Referential-integrity guards on delete** — deleting a record that other rows still reference now blocks with a clear "N records bound to it" message instead of failing silently or with a raw error:
  - **Transaction linked to a Dues settlement**: cannot be deleted directly — undo or delete the settlement first (from the contact's Settlement history), which removes the linked transaction with it. (Previously a "Delete Tx Only" option orphaned the settlement.)
  - **Settled due entry**: cannot be deleted while part of a settlement — undo the settlement first. (Previously deleted silently and desynced the settlement's entry count.)
  - **Contact with entries/settlements**: the block now states the exact counts ("1 entry and 2 settlements bound to it") instead of a generic message.
  - Account / Category / Mode deletes already blocked on linked transactions and forced reassignment — unchanged.

### Fixed
- **AI no longer says "no category named fuel" when you ask about a real category.** Because the app is anonymize-by-default, the AI saw only opaque labels (`cat_0`…`cat_4`, the top-5 spend categories this month) and no name↔label map, so it couldn't connect the word you typed ("fuel") to any label — and a category with no spend this month wasn't in its data at all. The chat now resolves the category/account/mode/tag names **you type in your own question** on-device and adds a silent `[Context note]` (only in what's sent to the AI — never persisted, never shown to you) tying that name to its label and current-month amount. The AI can now answer specifically about the category you named. The on-device legend for categories you **didn't** mention still never leaves the device; only names you typed yourself are reused. (Backstops: the system prompt now tells the AI never to claim a category "doesn't exist" — only that there's no activity this month — and to offer the top-spending breakdown instead.)
- **"Share category & account names" toggle now takes effect immediately.** Previously flipping the toggle persisted but didn't change what the AI actually received until you restarted the app (or changed provider/model), because the resolved AI config was cached and never recomputed when the toggle flipped. The config now watches the toggle and the setting invalidates it on change, so the next chat/report generation uses the new value right away.
- **AI Report header month was invisible.** The month label in the report's app bar clipped to nothing inside the narrow title slot (three action buttons left no room). It now scales down to fit (matching the other report screens), so "September 2026" is always visible.
- **Category delete no longer crashes when the category is used by a budget**: a category referenced by one or more budgets now blocks with "used by N budget(s). Delete or change those budgets first" instead of surfacing a raw database `RESTRICT` exception. The destructive accent now uses the app's real red (`AppColors.expense`) in this dialog too.

> **Backup caveat**: The database backup ZIP includes `expenses.db` (so the `phone` / `device_contact_id` / `photo_path` / `phones` columns are backed up and restored) but not the `contact_photos/` files in the app documents directory. After a restore, imported contacts keep their name and all numbers, but the photo falls back to the emoji avatar (no crash). A future release may bundle the photo files into the backup.

## v2.14.0 — 2026-07-09

### Added
- **What's New viewer**: Settings → "What's New" opens a sheet showing the changelog for the currently installed version. The notes are bundled as an offline asset (`CHANGELOG.md`), so it works without a network on both Android and iOS — letting users revisit what changed after updating.
- **Rendered changelog in the update sheet**: When an update is available, release notes now appear as formatted Markdown (headings, nested/numbered lists, bold, inline code, tappable links) in a roomier bottom sheet, instead of raw Markdown text in a dialog.
- **Lightweight changelog Markdown parser**: A small dependency-free parser (`lib/app/widgets/changelog_markdown.dart`) renders the "what's new" content — headings, bullets, numbered lists, blockquotes, horizontal rules, and inline `**bold**` / `~~strike~~` / `` `code` `` / `[links](url)`.

### Changed
- **Smaller release APK**: Release builds now target arm64 and split per-ABI, reducing the download from ~70 MB to ~25 MB.
- Removed unused platform folders (macOS, Linux, Windows, Web) and dependencies (`phosphor_flutter`, `showcaseview`, `xml`, `printing`) to slim the app and repository.

## v2.13.0 — 2026-07-09

### Added
- **Swipe-to-Reveal Row Actions**: Every entity list (transactions, accounts, categories, modes, budgets, contacts, due entries) now supports swipe-to-reveal Edit / Duplicate / Delete actions via `flutter_slidable`, with secondary actions (archive, set/clear default) kept in the trailing menu.
- **Tap = Edit**: A plain tap on any row now opens the entity's edit form prefilled — the read-only transaction detail sheet has been removed.
- **Transaction Duplicate**: Swipe a transaction to duplicate it (copies amount, date, account, category, mode, note, and tags; transfers are duplicated as a linked pair).
- **Always Confirm Before Delete**: Every delete now routes through a shared confirmation dialog (`showConfirmDeleteDialog`), including the previously instant, no-prompt due-entry delete.
- **Always Show Feedback**: A snackbar now appears after every edit and every delete (`showFeedbackSnackBar` — "X updated" / "X deleted" / "X duplicated"); no successful change is silent anymore.
- **Current-Month Recent Activity**: The home "recent activity" feed is now scoped to the current month (newest-first), with infinite scroll and a "View all history →" button that navigates to the transactions screen for older months.
- **Destructive Red Styling**: Delete swipe buttons, confirmation dialogs, and error snackbars now render in the app's destructive red (`AppColors.expense`), since `ColorScheme.error` is repurposed to a monochrome token in this theme.
- **Search Pagination**: Global search now returns the full match set with client-side infinite scroll instead of a hard 25-row cap.

### Changed
- **Top Spends Report**: Now groups expenses by category (ranked category totals with icon/color) instead of listing individual transactions, and renders amounts in the destructive red.
- **Net Worth / Reports**: Archived accounts are now excluded from the base-balance and prior-period net calculations in reports, so archived accounts no longer skew totals.
- **Home Dues Widget**: Balance text now uses explicit green ("they owe you") / red ("you owe them") colors instead of the monochrome `cs.error`, and contact avatar colors use the shared `hexToColor` util.
- **Edit Contact Sheet**: Made compact and safe-area aware so it no longer overlaps the status bar; added a drag handle and themed surface; removed the now-redundant in-sheet Delete button (delete is available via swipe).
- **Transactions Screen**: Now infinite-scrolls and uses the swipe/tap=edit interactions consistent with the rest of the app.
- **App Icons**: Refreshed launcher icons; removed unused web icon assets.
- Replaced deprecated `withOpacity()` calls with `withValues(alpha:)` and removed a few unused imports.

---

## v2.12.0 — 2026-07-07

### Added
- **.env Support**: Added support for `.env` files via `flutter_dotenv` for secure environment variable management.

### Changed
- **Database Backup**: Updated the raw database export to generate a ZIP containing both the main database and the latest replica backup.
- **Auto Update Check**: Improved auto-update check logic to properly compare build numbers when semantic versions match.
- **Transaction Lists**: Filtered out `transfer_in` transactions from the Home and Transactions screens to avoid duplicate entries when logging internal transfers.
- **Backup Quota**: Reduced default backup quota from 20 MB to 10 MB.

---

## v2.11.0 — 2026-07-06

### Changed
- **Typography Upgrade**: Completely overhauled the app's typography to use a "Fintech Premium" font stack (Plus Jakarta Sans, DM Sans, Space Grotesk) for improved readability and a modern aesthetic.
- **Transaction Entry UI**: Replaced the "Swipe to Add/Save" slider in the Add/Edit transaction sheets with a standard, solid button for a simpler and more consistent user experience.

---

## v2.10.0 — 2026-07-06

### Added
- **Account Current Balance Calibration**: Redesigned account creation and editing. You can now simply enter your actual current bank balance, and SpendWise automatically calculates your true starting balance by reverse-engineering your past transactions.

### Changed
- **Transfer Architecture Overhaul**: Rebuilt the underlying financial engine to rigorously track internal transfers (`transfer_in` and `transfer_out`) for flawlessly accurate net worth and statement calculation.
- **Swipe-to-Add Transaction Enhancements**: Polished the "Swipe to Add" sliders to strictly remain disabled until all necessary fields (amount, accounts, category, payment mode) are populated.

---

## v2.9.1 — 2026-07-04

### Added
- **Dues Management Enhancements**: Added the ability to edit unsettled due entries directly from the contact detail screen and the option to delete a contact entirely (provided they have no active entries).

### Changed
- **Swipe-to-Add Interactions**: Replaced standard "Add Transaction" buttons with a sleek "Swipe to Add/Save" component in the transaction sheets to match the settlement sheet design. The swipe action gracefully stays disabled until all required fields are filled out.

---

---

## v2.9.0 — 2026-07-04

### Added
- **Daily Trends Analysis**: The Monthly Summary report now features deep day-by-day analysis, complete with daily income vs expense bar charts and cumulative wealth growth tracking.
- **Smart Insights**: Added intelligent insight cards to all major reports, automatically summarizing peak spending days, top categories, and positive cashflow periods.
- **Contextual Time Selector**: Time navigation (Month/Year selectors) has been moved into the individual reports, giving you precise control exactly where you need it.

### Changed
- **Reports Dashboard Redesign**: The main Reports hub has been transformed from a standard list into a sleek, responsive, and flat-design Bento Grid layout.

---

## v2.8.0 — 2026-07-04

### Added
- **Quick Dues Widget**: A new, modern, minimalist Neo-bank style Quick Dues widget on the Home Screen for fast entry.
- **Dynamic Entry Highlights**: The add entry dialog now dynamically highlights red or green depending on if you are adding a Payable or Receivable.
- **Widget Toggle**: Added a setting to easily toggle the Quick Dues widget on and off from the home screen.
- **Raw Database Import**: Introduced support for importing raw database backups directly.
- **Privacy Mode**: Added a convenient eye-icon toggle next to the Total Net Worth on the home screen to hide/reveal your balance like a bank app. This defaults to hidden for privacy.

### Changed
- Replaced the horizontal segmented control in quick dues with an intuitive side-by-side action button layout.
- Upgraded the "Swipe to Add" experience with contextual dynamic colors.
- Upgraded the Total Net Worth font to a futuristic, geometric style (Orbitron) for a more striking appearance.

---

## v2.7.0 — 2026-07-02

### Added
- **Dues & Tabs Module**: A complete new feature to track IOUs with friends and contacts. Features a dedicated Dues tab with an overview of your net receivables and payables.
- **Settlement Management**: Intelligently settle multiple dues at once with a beautiful "Swipe to Settle" UI.
- **Settlement History**: Full history of past settlements with the ability to safely delete incorrect settlements, cleanly unlinking entries and removing linked transactions.

### Changed
- Refined the Dues and Tabs screens to follow the app's standard layout principles (SliverAppBars, Manrope/Inter typography, and consistent padding).

---

## v2.6.1 — 2026-06-08

### Added
- **Dynamic Brand Coloring**: Choose your own primary brand accent color from the Settings tab! This customized color intelligently tints all active navigation icons, filled buttons, search floating action buttons, and active filter pills.
- **Default Black Theme**: The default primary color out-of-the-box has been shifted to `0xFF0A0A0A` (Monochrome Black) for a stunningly clean and high-contrast minimal aesthetic.

### Changed
- **Report Summary Layout**: We relocated the "Net Gain" pill from the cramped top AppBar into its own beautifully centered, full-width card positioned intuitively right below the Total Income and Total Expense cards.
- **Filter Sheet Readability**: Upgraded the internal selectable filter chips (e.g., Dates, Categories) within the transactions filter sheet to dynamically illuminate with your active brand color rather than just fading to grey.

### Fixed
- Fixed an annoying `RenderFlex` layout overflow constraint on the Yearly Overview title bar that occasionally triggered on narrower displays.

## v2.6.0 — 2026-06-08

### Added
- **AI Dynamic Insights**: All 6 analytical charts on the Reports and Yearly Overview dashboards now feature intelligently generated, multi-sentence insight cards that summarize your positive/negative trends (e.g., peak income, biggest losses, highest expense categories, and overall average savings rates).
- **Current Balance Preview**: When editing an Account's "Opening Balance" from the Manage tab, the app now dynamically previews your actual "Current Balance" directly beneath the text field in real-time.

### Changed
- **Stricter Import Duplicate Detection**: The 5-point composite key for skipping duplicate transactions during CSV/Excel imports has been upgraded to a strict 6-point key. The importer now checks the *exact* Time of day (not just the calendar Date) and the precise Transaction Note, allowing you to seamlessly import multiple identical transactions that occurred at different times on the same day.

### Fixed
- Fixed an overlapping layout glitch on the Yearly Overview charts.
- Fixed a bug where the 6-Month Cash Flow chart was accidentally rendering the same month's x-axis label twice due to floating-point scaling issues.

---

## v2.5.0 — 2026-06-08

### Added
- **Database Backup & Recovery**: The app now takes rolling replicas of your database securely on your device before every launch. 
- You can manage your storage quota (20MB, 50MB, etc.) to ensure backups never bloat your device.
- **Manage Backups**: A new screen in Settings to view, export, and manually restore these backup replicas.
- **Raw Database Export**: You can now download your live `expenses.db` and the most recent backup directly as a `.zip` file from the Settings menu.
- **Emergency Recovery Flow**: A new pre-flight corruption check prevents the app from crashing if the underlying SQLite file is corrupted. Instead, you'll be greeted by an emergency recovery screen where you can instantly restore from your pristine rolling backups.

### Changed
- All Report screens have been visually overhauled to feature a cleaner dual-line header layout (Title + Subtitle) for improved readability.
- "Export Data" functionality has been completely centralized to the Settings page, removing the redundant action buttons from the top of Report screens.

### Fixed
- Completely purged the legacy "title" field from the Transactions database schema and associated SQL queries to resolve crashes when generating certain reports (like Top Spends).
- **XLSX Importer Robustness**: 
  - Added a pre-processing step to sanitize and strip invalid `<numFmt>` elements from Excel files generated by Google Sheets, Apple Numbers, and LibreOffice that would otherwise crash the importer.
  - Improved date/time, formula, and boolean cell extraction.
  - Implemented smarter skipping of template placeholder rows and completely empty rows to prevent ghost data imports.

## v2.4.0 — 2026-06-07

### Added
- New app icon across all Android densities with full adaptive icon support (foreground, background, monochrome layers) and all iOS AppIcon sizes
- Home screen wordmark redesigned: "spend" in regular weight + "wise" in bold primary colour — simple, typographic, and unmistakably the app
- Settings → About section overhauled: app card now shows a version badge, a 2×1 stat grid (Offline · No Ads · Private · On-Device), and a punchy one-liner; developer card gets a cleaner KP avatar, tighter bio, and the same link chips

### Fixed
- Tapping a column chip in the Export sheet crashed with "Cannot change an unmodifiable set" — the default column set was a `const` reference; it is now always copied to a mutable set on config creation
- "Title" column removed from the export column picker and all four exporters (CSV, XLSX, PDF, JSON) — transactions don't have a user-facing title field so this column produced empty or confusing output
- PDF export currency symbol now renders as "Rs" instead of "₹" — the built-in Helvetica font in the pdf package lacks the Unicode rupee glyph, causing it to appear as a box on most devices
- Currency selector removed from the Add/Edit Account form — SpendWise is INR-only for now; the currency column is retained in the database for future multi-currency support
- Account balance subtitle in Manage no longer shows the redundant "· INR" currency code

---

## v2.3.1 — 2026-06-07

### Fixed
- Report cards (e.g. "Biggest Spend") now show the category name when the transaction has no title, and display the note as a subtitle when present — previously only the trophy icon appeared with no text
- Opening balance in accounts now correctly factors into the displayed net balance (`opening balance + income − expense`); account statement report also seeds the running total from opening balance
- All 4 main screens (Home, Transactions, Reports, Settings) now have a consistent fixed header — the header stays pinned while content scrolls

---

## v2.3.0 — 2026-06-07

### Added
- Auto-check for updates on startup: when connected to the internet, SpendWise silently checks GitHub for a new version once every 24 hours and shows a dismissible banner on the home screen if one is found
- "Auto-check for updates" toggle in Settings (enabled by default) to disable the startup check

### Fixed
- Install flow now uses Android's `ACTION_INSTALL_PACKAGE` intent via a native MethodChannel — fixes the issue where tapping Install would close the dialog but the system installer never appeared (affected MIUI, OneUI, ColorOS, and other OEM ROMs)
- Update dialog now shows "Opening installer…" briefly after tapping Install, giving the system installer time to come to the foreground before the dialog closes

---

## v2.2.0 — 2026-06-07

### Changed
- Transactions screen redesigned: consistent "transactions" wordmark header (matching home screen), slim inline income/expense/net stats row, monochrome filter chips, cleaner group date headers
- Pagination added to transactions list — loads 20 items at a time with a "Load N more" button at the bottom
- All 4 main screens (home, transactions, reports, settings) now share a consistent header style: Manrope w800 24pt lowercase title, identical 40×40 action buttons with surfaceContainer background and 12px radius
- Reports and Settings screens converted from Material AppBar to the same custom header used by home and transactions
- Extracted shared `ScreenHeader` and `HeaderIconButton` widgets

### Fixed
- In-app update installer now correctly requests the "Install unknown apps" runtime permission on Android 8+ before launching the system installer — previously the install dialog would close silently without installing
- Settings page header was positioned too high due to `ListView` consuming `MediaQuery.padding.top` for its children; header is now placed outside the scroll view

---

## v2.1.0 — 2026-06-06

### Added
- In-app update checker — Settings → Check for Update fetches latest GitHub release, shows release notes, and downloads + installs the APK with a progress indicator
- Startup cleanup of leftover APK from previous in-app update

### Changed
- Home screen chart now shows separate green (income) and red (expense) lines instead of a single net line
- Transaction tile amounts are now coloured green/red/neutral by kind
- Reports mini chart uses correct green/red colours for income vs. expense lines
- Settings version number is now dynamic (read from app package info)
- Settings subtitle no longer mentions tags

### Removed
- Tags feature removed from all UI surfaces (add/edit sheet, detail sheet, search, manage screen, reports) — data layer kept intact, no migration needed

### Fixed
- Home and Reports charts now refresh immediately after adding, editing, or deleting a transaction (FutureProvider reactivity fix)
- Duplicate "Add Transaction" FAB removed from Transactions screen

---

## v2.0.0 — 2026-06-06

### Added
- Full app rewrite: Drift ORM, Riverpod state management, Material You theming
- Accounts, categories, payment modes management
- Budget tracking with per-category monthly limits
- Reports: monthly summary, yearly overview, category drilldown, mode breakdown, cash flow trend, top spends, account statement, budget performance
- Export to PDF, CSV, and Excel
- Biometric authentication + PIN lock with configurable auto-lock timeout
- In-app update checker via GitHub releases
- Global search across transactions, categories, accounts, and payment modes
- OLED dark mode
- Transfer transactions between accounts
