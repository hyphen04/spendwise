<div align="center">
  <img src="assets/logo/logo.png" alt="SpendWise Logo" width="120" height="120" style="border-radius: 20px;">
  
  # SpendWise

  **Personal Finance, Simplified & Secured.** <br>
  *Finally, an app that tells you exactly where your money went. You probably won't like the answer — but hey, at least it's offline so no one else can see your shame.*

  [![Flutter Version](https://img.shields.io/badge/Flutter-%3E%3D3.27.0-02569B?logo=flutter)](https://flutter.dev)
  [![Version](https://img.shields.io/badge/Version-2.11.0-brightgreen.svg)]()
  [![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-lightgrey.svg)]()
  [![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
</div>

<br>

SpendWise is a beautifully crafted, privacy-first personal finance tracker. It helps you manage your money, track where every penny goes, organize budgets, and track dues — all completely offline, straight from your device. No cloud syncing, no ads, no trackers, just you and your finances in an elegant Material 3 interface.

---

## ✨ Features

- 📵 **100% Offline & Private:** All data resides securely on your device. We respect your privacy.
- 🌐 **Offline / Online Mode:** A master toggle in Settings lets you run the app fully offline. **Offline** (the default) hides every internet-dependent feature — AI Copilot, update checks, and feedback — from all screens and keeps everything on-device; no online operation runs. **Online** restores the full app with your existing sub-toggles intact (your AI / auto-update choices stay dormant while offline and resume exactly as-is when you switch back). Fonts are bundled locally too, so the app renders identically with no connection.
- 🎨 **Material You Design:** Clean, fluid, and deeply integrated Material 3 UI. Support for Dark Mode, OLED pure black, and dynamic accent colors.
- 🔒 **App Lock Security:** Keep your financial data safe with PIN code protection and Biometric (Face ID / Fingerprint) unlock.
- 📊 **Budgets & Analytics:** Track expenses against custom budgets. Visualize your spending with beautiful, intuitive charts.
- 👥 **Dues & Split Tracking:** Easily track who owes you and who you owe, perfect for keeping track of small personal loans and shared bills.
- 💾 **Robust Backups:** Generate and restore database backups easily. Custom storage quotas and full raw database (ZIP) export.
- 📥 **Import & Export:** Export your financial reports seamlessly into **PDF, CSV, or Excel**, and easily import data from legacy systems.

## 🛠 Tech Stack

Built with modern Flutter architecture to ensure stability, speed, and maintainability:

- **Framework:** [Flutter](https://flutter.dev) (v3.27.0+)
- **State Management:** [Riverpod](https://riverpod.dev/) (with code generation)
- **Local Database:** [Drift (SQLite)](https://drift.simonbinder.eu/) for typesafe and fast offline storage
- **Routing:** [GoRouter](https://pub.dev/packages/go_router)
- **Styling:** Dynamic Color, bundled local fonts (Plus Jakarta Sans + Space Grotesk), Phosphor Icons
- **Security:** Flutter Secure Storage, Local Auth (Biometrics)

## 🚀 Getting Started

### Prerequisites
- Flutter SDK `^3.27.0`
- Dart SDK `>=3.5.0 <4.0.0`
- Android Studio / Xcode (for deployment)

### Installation
1. **Clone the repository**
   ```bash
   git clone https://github.com/hyphen04/spendwise.git
   cd spendwise
   ```

2. **Install Dependencies**
   ```bash
   flutter pub get
   ```

3. **Code Generation** (for Riverpod, Freezed & Drift)
   ```bash
   dart run build_runner build -d
   ```

4. **Run the App**
   ```bash
   flutter run
   ```

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/hyphen04/spendwise/issues). 

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📜 License

Distributed under the MIT License. See `LICENSE` for more information.

---

<div align="center">
  Designed & Developed with ☕ and questionable life choices by <strong>Kunj Patel</strong>. <br>
  <a href="https://kunj.dev">Portfolio</a> • <a href="https://github.com/hyphen04">GitHub</a>
</div>
