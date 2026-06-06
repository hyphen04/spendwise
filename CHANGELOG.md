# Changelog

All notable changes to SpendWise are listed here.
Format: `## vX.X.X — YYYY-MM-DD` with Added / Changed / Fixed sections.

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
