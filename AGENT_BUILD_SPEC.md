# Family Expense Tracker — Project Diagnosis & Agent Build Specification

> **Document Type:** System Diagnosis, Architecture Roadmap & Automated Agent Build Directive  
> **Date:** September 10, 2026  
> **Target Audience:** Autonomous Coding Agent & Developer  
> **Primary Use Case:** Personal & Family Expense Tracking on Mobile Devices  

---

## 1. Executive Summary & Current State Audit (100% Code-Verified)

A complete audit of the repository (`c:\Users\rohan\OneDrive\Desktop\projects\Expense-Tracker`) reveals several critical discrepancies and missing foundations:

### 1.1 Storage Disconnect (`app.py` vs `database.py`)
- **The Issue:** `database.py` defines an SQLite database (`expenses.db`), but `app.py` **completely ignores SQLite**. Instead, `app.py` lines 310–373 load and save raw text to `expenses.txt` using strings formatted as `Category-Amount`.
- **Current Data:** `expenses.db` exists but has **0 rows**. `expenses.txt` has only 1 row (`Game-1200`).
- **Consequence:** Data is fragile, prone to race conditions if accessed from mobile, and lacks relational structure.

### 1.2 Incomplete Transaction Schema
- **No Dates or Timestamps:** Neither the DB nor the text file records transaction dates. The user cannot see daily spending, monthly comparisons, or trends.
- **No Family Attribution:** There is no field to attribute who made the purchase (Self, Spouse, Parents, Kids).
- **No Notes or Payment Modes:** No notes (e.g., "Monthly veggies at D-Mart") or payment types (UPI, Cash, Card).
- **Amount Data Type:** `amount` is stored as an integer (`INTEGER` in SQLite, `int(amount)` in python). Decimal amounts (e.g., ₹45.50) crash the app or get truncated.

### 1.3 Code Duplication & Bugs in `database.py`
- In `database.py`, `delete_expense(id)` is implemented **twice consecutively** (lines 37–48 and lines 49–63).

### 1.4 Mobile Usability Roadblocks
- In `app.py`, edits and deletions require manually typing a zero-based list row index (`edit_index`, `delete_index`). On a mobile phone screen, this is error-prone and unintuitive.
- The 2-column desktop layout (`st.columns(2)`) cramps input fields on smartphone viewports.

### 1.5 Repository Hygiene
- The ignore file is incorrectly named `.git.ignore` instead of `.gitignore`.
- Line 1 contains an erroneous CLI string: `git status# Python`.

---

## 2. Realistic Heights It Can Reach (Simple, Practical, Family-First)

To keep the application light, maintainable, and free of over-engineered SaaS bloat, here is the feature blueprint:

1. **Family Member Attribution:** Instant tagging per transaction (`Self`, `Spouse`, `Dad`, `Mom`, `Kids`).
2. **Date & Calendar Support:** Auto-defaults to current date, with an easy calendar picker for past/backlogged receipts.
3. **Payment Mode Tagging:** UPI (Google Pay, PhonePe, Paytm), Cash, Credit/Debit Card, Net Banking.
4. **1-Tap Quick Categories:** Preset essentials:
   - 🛒 Groceries & Household
   - 🍔 Food & Dining
   - 💡 Bills & Utilities
   - 🚗 Transport & Fuel
   - 💊 Health & Medical
   - 🛍️ Shopping
   - 🎬 Entertainment & Leisure
   - 📦 Other
5. **Mobile-First Touch UI:** Large tap targets, clean single-column cards, interactive selectboxes for editing/deleting (no typing numeric indices).
6. **Monthly Budget Tracking & Visual Progress:** Set a family monthly budget limit (e.g., ₹50,000) with a dynamic progress bar (Green → Amber → Red).
7. **Monthly Filtering & Breakdown:** View spending for "Current Month", "Last Month", or "All Time", with spending distribution by category and family member.
8. **1-Click Backup & Restore:** Zero data loss guarantee via instant CSV / SQLite download button and file uploader.

---

## 3. How It Runs on Your Phone

Choose one of the following 3 tested deployment paths:

### Path A: Streamlit Community Cloud (Recommended for Family Access)
- **How:** Push this repo to a private GitHub repository. Connect the repo on [share.streamlit.io](https://share.streamlit.io).
- **Mobile Access:** Open the generated URL on your phone's browser (Safari or Chrome), tap **"Add to Home Screen"**. It installs as an app icon with native full-screen feel.
- **Benefits:** Works anywhere on mobile data without needing your PC turned on.

### Path B: Local Network Server (100% Private, At Home)
- **How:** Run Streamlit with `--server.address 0.0.0.0 --server.port 8501`.
- **Mobile Access:** Open `http://<your-pc-ip>:8501` on your phone browser connected to the same Wi-Fi.
- **Benefits:** Completely private, zero cloud dependency.

### Path C: Standalone Mobile Web App (Zero Server)
- If you prefer zero Python runtime on a server or PC, the exact same UI and SQLite/IndexedDB storage can be bundled as an offline Progressive Web App (PWA).

---

## 4. Disaster Recovery & Backup Plan (Zero Hallucination)

1. **Auto-Migration of Legacy Data:**
   - On initial launch, the system checks for `expenses.txt`. If found, it parses `Category-Amount`, inserts it into `expenses.db` with date=today, member='Self', payment_mode='UPI', and archives `expenses.txt` as `expenses.txt.bak`.
2. **Database Integrity & Backups:**
   - Single-click **"Export Backup (CSV)"** directly downloads all records with timestamps to phone storage.
   - Single-click **"Restore from CSV"** allows re-uploading all records in case of phone replacement or database reset.
   - SQLite file can be downloaded directly from the UI.

---

## 5. Direct Instructions for the Agent (Autonomous Build)

> **Instructions for the Agent:**  
> Read the specifications below and implement them directly. Do not ask for user confirmation. Follow the file modifications and verification steps.

### Step 1: Repository Hygiene
- Rename `.git.ignore` to `.gitignore`.
- Update `.gitignore` to:
  ```gitignore
  # Python
  __pycache__/
  *.py[cod]
  *$py.class

  # Virtual Environments
  .venv/
  venv/
  env/

  # Databases & Backups
  expenses.db
  expenses.txt.bak
  *.csv

  # Environment & IDE
  .env
  .vscode/
  .DS_Store
  Thumbs.db
  ```

### Step 2: Refactor `database.py`
1. Remove duplicate `delete_expense` implementation.
2. Update SQLite schema to support rich family tracking:
   ```sql
   CREATE TABLE IF NOT EXISTS expenses (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       date TEXT NOT NULL,
       category TEXT NOT NULL,
       amount REAL NOT NULL,
       member TEXT NOT NULL,
       payment_mode TEXT NOT NULL,
       note TEXT DEFAULT ''
   );
   ```
3. Add helper functions:
   - `init_db()`: Creates the table if not exists, runs schema migrations for existing legacy tables.
   - `migrate_from_txt(txt_path="expenses.txt")`: Safely migrates existing text file data.
   - `add_expense(date, category, amount, member, payment_mode, note)`
   - `get_expenses(start_date=None, end_date=None, member=None, category=None)`
   - `update_expense(id, date, category, amount, member, payment_mode, note)`
   - `delete_expense(id)`
   - `get_summary_stats(start_date=None, end_date=None)`
   - `export_to_csv()` and `import_from_csv(file_stream)`

### Step 3: Streamlit Mobile Configuration (`.streamlit/config.toml`)
Create `.streamlit/config.toml` with:
```toml
[server]
headless = true
address = "0.0.0.0"
port = 8501
enableCORS = false
enableXsrfProtection = false

[theme]
base = "dark"
primaryColor = "#7c3aed"
backgroundColor = "#0e1117"
secondaryBackgroundColor = "#161b22"
textColor = "#ffffff"
```

### Step 4: Redesign `app.py` for Mobile
1. Use `layout="centered"` in `st.set_page_config(page_title="Family Expense Tracker", page_icon="💳", layout="centered")`.
2. Connect exclusively to `database.py` (retire file-based read/write in `app.py`).
3. Add a clean, mobile-optimized top bar:
   - Month Selector (defaults to current month).
   - Metric cards: Total Spent, Daily Average, Top Category, Top Spender.
   - Monthly budget progress bar with warning indicators if spending > 80% or > 100%.
4. "Quick Add Expense" Section:
   - Date picker (defaults to today).
   - Amount input (supports decimals, big tap target).
   - Category selector (Pills / Radio / Selectbox with emojis).
   - Member dropdown (`Self`, `Spouse`, `Dad`, `Mom`, `Kids`).
   - Payment Mode selector (`UPI`, `Cash`, `Card`).
   - Optional note input.
   - Full-width tap button: `➕ Add Expense`.
5. "Recent Transactions" Section:
   - Filter by search keyword, category, or member.
   - Clean card-style display: Date, Category badge, Note, Member badge, Amount in bold.
   - Action controls: Edit or Delete selected transaction via a dropdown selector (no typing raw row index numbers).
6. "Analytics & Charts" Section:
   - Donut or bar chart for Category distribution.
   - Member-wise expenditure breakdown.
7. "Backup & Restore" Section (in an expander):
   - `st.download_button` to download all data as CSV.
   - `st.file_uploader` to restore from CSV.

### Step 5: Verification
1. Run `python -c "import database; database.init_db()"` and verify clean table initialization.
2. Run automated test inserting test rows with dates and members, fetching summaries, and verifying calculations.
3. Test CSV export and re-import.
4. Verify `streamlit run app.py` starts without errors.
