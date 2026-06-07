# Changelog

All notable changes to SpendWise are listed here.
Format: `## vX.X.X — YYYY-MM-DD` with Added / Changed / Fixed sections.

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
