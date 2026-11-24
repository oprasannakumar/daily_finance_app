# 🧾 Smart Ledger & Daily Finance App

[![Download APK](https://img.shields.io/badge/Download-Release%20APK%20(v1.0.0)-FF5C38?style=for-the-badge&logo=android)](https://github.com/oprasannakumar/daily_finance_app/releases/download/v1.0.0/SmartLedger-v1.0.0.apk)
[![Latest Release](https://img.shields.io/github/v/release/oprasannakumar/daily_finance_app?style=for-the-badge&color=00D2B4)](https://github.com/oprasannakumar/daily_finance_app/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.29.0-02569B?style=for-the-badge&logo=flutter)](https://flutter.dev)
[![Google Sheets API](https://img.shields.io/badge/Google%20Sheets-API%20v4-34A853?style=for-the-badge&logo=googlesheets)](https://developers.google.com/sheets/api)
[![Gemini Vision AI](https://img.shields.io/badge/Gemini%20AI-Vision%20OCR-4285F4?style=for-the-badge&logo=google)](https://ai.google.dev/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)

An intelligent, privacy-first personal finance tracking, debt ledger, grocery price intelligence, and invoice management mobile application built with Flutter. Deeply integrated with **Google Sheets** (dual-spreadsheet synchronization), **AI Voice & Narration Parsing** (Gemini & Groq), and **Android App Shortcuts**.

---

## 📥 Direct Download & Installation

You can download and install the pre-compiled Android release APK directly without cloning the code:

👉 **[Download SmartLedger-v1.0.0.apk](https://github.com/oprasannakumar/daily_finance_app/releases/download/v1.0.0/SmartLedger-v1.0.0.apk)**

*(You can also find all versions under the [GitHub Releases](https://github.com/oprasannakumar/daily_finance_app/releases) tab).*

---

## 🌟 Comprehensive Feature Set

### 1. ⚡ Smart Entry Form
- **Natural Language Voice Input**: Tap the microphone button to dictate expenses (e.g., *"Paid 450 rupees for dinner from HDFC credit card"*).
- **Dual AI Narration Parsing**: Backed by **Gemini (gemini-3.6-flash)** and **Groq (qwen/qwen3.8-27b)** API engines with a zero-latency local fallback rule engine to instantly auto-fill Amount, Purpose, Spent For, and Account.
- **Smart Clipboard Auto-Fill**: Automatically parses banking SMS, Google Pay, PhonePe, and Paytm transaction notifications copied to clipboard.
- **Dual-Flow Accounting**: Toggle between **Withdraw** (Expense) and **Deposit** (Income) flows.
- **Self Transfer Mode**: Dedicated account-to-account transfer system (e.g. ATM cash withdrawal, moving funds from Bank to Wallet) formatted cleanly as balanced double-entry rows.
- **Multi-Account Split Payments**: Pay a single bill using multiple sources (e.g., ₹500 Cash + ₹478 HDFC UPI).
- **Fast Date Navigation**: Swipeable horizontal date picker with calendar picker dialog.

### 2. 🧾 Invoice Manager, Price Trends & Re-order Tracker
- **Itemized Invoice Creator**: Add and manage invoices with store/dealer name, bill number, bill date, line items, quantities, and prices.
- **Multi-Recipient Bill Splitting**: Assign individual items on a grocery bill to different people (e.g. `Self`, `Grand Father`, `Mother`).
- **Dealer Price Catalog Sync**: Tracks historical prices by dealer in the `"Dealer_Prices"` sheet of `"Grocery_DB"`; automatically updates unit prices if they change.
- **📈 Grocery Price History & Intelligence**: Real-time cross-store price comparison across all historical purchases and dealer catalog.
  - Automatically identifies **Price Hikes** (🔺) and **Price Drops** (🔻) compared to prior purchases.
  - Highlights the **Best Historical Deal** and which merchant or store offered it.
  - Calculates total quantity purchased and total expenditure per grocery item.
- **🛒 Smart Re-order Tracker & Auto-Checklist**:
  - Automatically learns your household purchase frequency and predicts when items are **DUE** for replenishment based on historical purchase rhythm (e.g. every 7, 14, or 30 days).
  - Interactive Smart Checklist: dynamically select items, adjust quantities with `+` / `-` buttons, and view estimated budget totals in real time.
  - **1-Tap Share**: Format and copy shopping lists to clipboard and share via WhatsApp or SMS.
  - **Draft Invoice Conversion**: Turn any replenishment list into a structured draft invoice with one tap.
- **Swipe-to-Delete**: Clean swipe gestures with confirmation to remove individual line items or entire borrower groups.
- **Interactive Search & Date-Filtered Picker**: Main form features a date-matched dropdown modal with live search to attach any invoice directly to a transaction.
- **Automated "Loan Given" Switch**: When an invoice with borrower splits is selected in the main form, the Purpose is automatically switched to **`Loan Given`**, and exact shares are populated in split mode.

### 3. 🤝 Borrowers Ledger & Debt Statement Generator
- **Detailed Loan Tracking**: Separate tracking for loans given and repayments received by borrower.
- **Faceted Multi-Filter Sheet**: Filter by date range, individual borrower, transaction type, or reference ID.
- **Borrower PDF Export**: Generate dedicated PDF statements for individual borrowers showing their net outstanding balance, itemized breakdown, and date-wise ledger.
- **Share & Print**: Native Android sharing sheet and PDF printing.

### 4. 💳 Multi-Account Balances & Asset Management
- **Complete Asset Coverage**: Tracks **Cash**, **Bank Accounts**, **Credit Cards**, **Wallets**, and **Rewards**.
- **View / Edit Mode**: Toggle edit mode to add new accounts, remove duplicate accounts/cards, or manually adjust baseline balances.
- **Real-Time Auditing**: Automatically deducts expenses and credits deposits across active balances.

### 5. ☁️ Google Sheets Dual-Database Sync
- **Primary Finance Spreadsheet**: Syncs main transaction logs, loan splits, account balances, and recurring templates.
- **`Grocery_DB` Spreadsheet**: Syncs `"Invoice"` records (itemized lines) and `"Dealer_Prices"` catalog.
- **Offline-First Resilience**: Local-first caching via `SharedPreferences`; background sync with pending delete queue ensures zero data loss offline.

---

## 📖 How to Use the Application

### Walkthrough 1: Logging a Quick Expense
1. Open the app — the **Smart Entry** form loads with today's date pre-selected.
2. In the **Narration** box, type or tap the **✨ Auto-Fill** button.
   - *Example*: `"Grocery 978 Babu oil mill HDFC"`
3. The app auto-populates **Flow** (`Withdraw`), **Purpose** (`Grocery`), **Spent For** (`Self`), and the **Payment Breakdown** (`HDFC: ₹978`).
4. Tap **Save** — the transaction is recorded locally and synced to Google Sheets.

---

### Walkthrough 2: Creating an Invoice & Managing Grocery Bills
1. Tap **🧾 INVOICE (OPT)** on the main form, then tap **Invoice Manager** at the bottom.
2. In the **Create Invoice** tab, enter the Dealer/Shop Name (e.g. `Babu oil mill`), Date, and items with quantities and unit prices.
3. To assign specific items to family members or friends (e.g. `Grand Father`), tap **+ Add Recipient Group (Borrower)** and add items under their section.
4. Tap **Save Invoice** — items are appended to `"Invoice"` in `"Grocery_DB"`, and new item prices are cataloged in `"Dealer_Prices"`.

---

### Walkthrough 3: Linking an Invoice with Borrower Splits in the Main Form
1. On the main form, tap **🧾 INVOICE (OPT)**.
2. The picker displays invoices matching the selected form date (e.g. `24-Nov-2026: Babu oil mill - ₹978.00 | Grand Father: ₹895.50`).
3. Tap the invoice:
   - **Narration** updates to `Babu oil mill`.
   - **Total Amount** updates to `₹978.00`.
   - **Purpose** automatically changes to **`Loan Given`**.
   - **Spent For** automatically changes to **`Split`**.
   - **Split Breakdown** automatically allocates `My Share (Self): ₹82.50` and `Grand Father: ₹895.50`.
4. Select your payment account (e.g. `HDFC New`) and tap **Save**.
5. The transaction is logged in the main statement and Grand Father's loan ledger is updated!

---

### Walkthrough 4: Exporting a PDF Report for a Borrower
1. Tap the ledger icon in the header or use the **Borrowers Ledger** shortcut.
2. Tap on any borrower (e.g., `Grand Father`).
3. View their total loan balance, itemized grocery items, and payment dates.
4. Tap **📄 Export PDF Statement**.
5. Select the date range and tap **Generate PDF** — preview, print, or share via WhatsApp!

---

### Walkthrough 5: Tracking Price Trends & Smart Re-orders
1. Open the **Invoice Manager** from the main form or drawer.
2. Tap the **Price & Re-order** tab (third tab alongside Invoices and Catalog).
3. The dashboard displays:
   - **Due Re-orders**: Items whose typical purchase frequency interval has elapsed.
   - **Price Hikes & Drops**: Quick badges showing which grocery items have inflated or gotten cheaper.
   - **Best Deals**: Historical best rates across different stores and markets.
4. Check the items you need to restock, adjust desired quantities using `+` and `-`.
5. Tap **Share List** to copy a formatted grocery list to your clipboard and open WhatsApp, or tap **Create Draft Invoice** to generate an active invoice ready for checkout!

---

### Walkthrough 6: Using Android App Shortcuts
- Touch and hold the **Daily Finance** app icon on your phone's home screen.
- A menu pops up with: `➕ Quick Add`, `📷 Scan Receipt (AI)`, and `👥 Borrowers Ledger`.
- Drag any shortcut onto your home screen to create a dedicated 1-tap launcher icon.

---

## 🗄️ Google Sheets Architecture

### 1. Primary Finance Spreadsheet
| Sheet Name | Columns / Headers | Purpose |
| :--- | :--- | :--- |
| **`Transactions`** | `Date` \| `Narration` \| `Invoice No.` \| `Purpose` \| `Spent for/Earned by` \| `Transaction Type` \| `From/ To` \| `Withdrawn Amount` \| `Deposit Amount` \| `Balance` \| `Reference` | Main statement and master journal |
| **`Account Balances`** | `Category` \| `Account Name` \| `Current Balance` \| `Updated Date` | Real-time balance of Cash, Banks, Cards, Wallets, Rewards |
| **`Borrowers` / Loans** | `Date` \| `Borrower` \| `Narration` \| `Invoice No.` \| `Transaction Type` \| `Account` \| `Given Amount` \| `Received Amount` \| `Reference` | Itemized debt ledger per person |

### 2. `Grocery_DB` Spreadsheet
| Sheet Name | Columns / Headers | Purpose |
| :--- | :--- | :--- |
| **`Invoice`** | `Bill Date` \| `Shop Name` \| `Bill No` \| `Item Name` \| `Quantity` \| `Price` \| `Total` \| `Recipient` | Itemized invoice lines with borrower attribution |
| **`Dealer_Prices`** | `Item` \| `Dealer` \| `Price` \| `LastUpdated` | Historical pricing catalog per store/dealer |

---

## 🏗️ Technical Architecture & Stack

- **Framework**: [Flutter 3.29.0](https://flutter.dev) / [Dart 3.7.0](https://dart.dev)
- **UI Design System**: Illustrative Warm Playful Theme (`#FF7A5C` Coral, `#4ECDC4` Mint Teal, `#FFD93D` Gold, `#A78BFA` Lavender) with full Dark Mode support.
- **State Management & Caching**: Local-first architecture with `SharedPreferences`, `ValueNotifier` reactives, and zero-latency UI updates.
- **AI & Cloud Services**:
  - **Gemini API**: `gemini-2.5-flash` for multimodal receipt OCR and text parsing.
  - **Google Sheets API v4**: REST client using OAuth2 Bearer tokens from `google_sign_in`.
- **Hardware Integrations**:
  - `image_picker`: Camera & gallery capture.
  - `speech_to_text`: Real-time voice dictation.
  - `quick_actions`: Android App Shortcuts (Quick Add, Scan Receipt, Borrowers Ledger).
  - `share_plus`: Native shopping list and report sharing sheet.
  - `pdf` & `printing`: Vector-based PDF generation and printing.

---

## 💻 Building from Source

### Prerequisites
- Flutter SDK `^3.29.0`
- Android SDK with API Level 34+
- Java JDK 17

### Steps
```bash
# 1. Clone the repository
git clone https://github.com/oprasannakumar/daily_finance_app.git
cd daily_finance_app

# 2. Install dependencies
flutter pub get

# 3. Run unit tests
flutter test

# 4. Run static analysis
flutter analyze

# 5. Build Release APK (ARM64)
flutter build apk --release --target-platform android-arm64
```
The output APK will be generated at:
`build/app/outputs/flutter-apk/app-release.apk`

---

## 📄 License
This project is open source under the [MIT License](LICENSE).
