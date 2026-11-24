# 📊 Smart Ledger & Daily Finance App

[![Download APK](https://img.shields.io/badge/Download-Release%20APK%20(v1.0.0)-FF5C38?style=for-the-badge&logo=android)](https://github.com/oprasannakumar/daily_finance_app/releases/download/v1.0.0/SmartLedger-v1.0.0.apk)
[![Release](https://img.shields.io/github/v/release/oprasannakumar/daily_finance_app?style=for-the-badge&color=00D2B4)](https://github.com/oprasannakumar/daily_finance_app/releases/latest)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)

An intelligent, privacy-first personal finance tracking and debt management app built with Flutter and integrated with Google Sheets, Gemini AI Vision OCR, and Android Home Screen Widgets.

---

### 📥 Direct Download
Download the pre-compiled, ready-to-install Android APK:
👉 **[Download SmartLedger-v1.0.0.apk](https://github.com/oprasannakumar/daily_finance_app/releases/download/v1.0.0/SmartLedger-v1.0.0.apk)** (or visit [Releases](https://github.com/oprasannakumar/daily_finance_app/releases)).

---

### ✨ Key Features

1. **🧾 AI Receipt & Bill OCR Scanner (Camera-to-Invoice)**
   - Snap a physical supermarket receipt with your camera or select an invoice photo from gallery.
   - Multimodal Gemini AI OCR automatically extracts store name, bill number, bill date, line items, quantities, and unit prices into editable form tables.

2. **⚡ Dynamic App Shortcuts & Home Screen Widget**
   - **App Shortcuts**: Long-press app icon to access `➕ Quick Add`, `📷 Scan Receipt (AI)`, and `👥 Borrowers Ledger`.
   - **Android Widget**: Native resizable home screen launcher widget for 1-tap entry.

3. **🤝 Borrowers Ledger & Automatic Loan Splits**
   - Track shared purchases and loans (e.g. Personal Share vs Grand Father, Mother, Friends).
   - Selecting an invoice with borrowers automatically switches the purpose to `Loan Given` and pre-fills exact split shares.
   - Filter, audit, and export customized PDF loan statements with 1 tap.

4. **☁️ Direct Google Sheets Synchronization**
   - Multi-sheet ledger synchronization (`Transactions`, `Account Balances`, `Invoice`, `Dealer_Prices`).
   - Local-first architecture with instant offline writes and background sync.

5. **💳 Multi-Account & Payment Breakdown**
   - Split single transactions across Cash, Bank, Credit Cards, Wallets, and Rewards.
   - Real-time balance auditing and auto-deductions.

---

### 🛠️ Building From Source

```bash
# Clone the repository
git clone https://github.com/oprasannakumar/daily_finance_app.git
cd daily_finance_app

# Install dependencies
flutter pub get

# Run test suite
flutter test

# Build Release APK
flutter build apk --release --target-platform android-arm64
```
Output APK location: `build/app/outputs/flutter-apk/app-release.apk`
