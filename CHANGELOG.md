# Changelog

All notable changes to SpendWise are listed here.
Format: `## vX.X.X — YYYY-MM-DD` with Added / Changed / Fixed sections.

## v2.15.0 — 2026-07-10

### Added
- **Device-contacts enrichment for Dues & Tabs**: When adding or editing a Dues contact, an "Import from phone" button opens the native contact picker and fills in the person/vendor's real name, phone number(s), and photo (with your consent). The contact detail screen now shows the photo avatar and **Call + WhatsApp action buttons** (Call dials via the system dialer; WhatsApp opens the chat with that number directly via the `whatsapp://` scheme, falling back to `wa.me`); list rows show the photo thumbnail. A phone-based dedup guard prompts you to open an existing contact instead of creating a duplicate. Contacts are read **on-device only and never uploaded** (the app has no server).
- **Multiple numbers per contact**: importing a device contact now keeps *all* its numbers (mobile / home / work), each with its label, instead of forcing a choice at import time. When you tap **Call** or **WhatsApp** and the contact has more than one number, a chooser sheet lets you pick which to use; with a single number it acts directly. The detail card shows the primary number with a `+N` badge when there are more. Dedup matches any of a contact's numbers, not just the primary.
- **Settings → Contact Access toggle** with a privacy subtitle stating contacts are read on-device and never uploaded. The OS contacts permission is requested when you turn it on or when you first import.
- **Phone normalization, dedup & a `ContactPhone` model** (`lib/app/utils/phone_utils.dart`): numbers are normalized to a last-10-digit key so `+91…`, `091…`, and bare 10-digit forms match; the multi-number list is stored as JSON in `due_contacts.phones`.
- **Shared `ContactAvatar` widget** for the photo-vs-emoji fallback, reused by the detail screen, list rows, and the import preview.
- **Delete contact** from the contact detail screen's app bar (beside Edit), with the same confirm-dialog + "settle or delete entries first" guard as the list swipe-delete.
- **Settlement date in the Settle sheet**: you can now pick the date a settlement was posted (defaults to today; back-dateable to 2000). That date is used for both the settlement's record *and* the linked transaction's posting date, so Reports count the settlement transaction on the settlement date — not necessarily today.
- **Edit settlement date**: on the settlement detail sheet, an edit-calendar action (and the tappable date) lets you re-date an existing settlement. It updates the settlement record and its linked transaction together, so an old settlement logged on the wrong day can be moved into the right report month without deleting and re-settling. No migration — existing settlements keep their original date and stay valid.

### Changed
- **Redesigned contact detail screen**: the hero is now a single flat contact card (avatar, name, tappable phone, person/vendor tag, balance with ↑/↓ direction, and Call + WhatsApp actions) matching the app's surface + thin-outline card language; tighter spacing throughout. Section headers use the lowercase label + count style from the home screen.
- **DB schema v9 → v10 → v11**: v10 added nullable `phone`, `photo_path`, and `device_contact_id` columns to `due_contacts`; v11 added a nullable `phones` JSON column holding the full number list. Additive migrations; no data loss, no `DEFAULT` required.
- **Referential-integrity guards on delete** — deleting a record that other rows still reference now blocks with a clear "N records bound to it" message instead of failing silently or with a raw error:
  - **Transaction linked to a Dues settlement**: cannot be deleted directly — undo or delete the settlement first (from the contact's Settlement history), which removes the linked transaction with it. (Previously a "Delete Tx Only" option orphaned the settlement.)
  - **Settled due entry**: cannot be deleted while part of a settlement — undo the settlement first. (Previously deleted silently and desynced the settlement's entry count.)
  - **Contact with entries/settlements**: the block now states the exact counts ("1 entry and 2 settlements bound to it") instead of a generic message.
  - Account / Category / Mode deletes already blocked on linked transactions and forced reassignment — unchanged.

### Fixed
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
