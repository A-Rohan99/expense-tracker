"""
Database layer for the Family Expense Tracker.

Schema (rich, family-aware):
    id            INTEGER PRIMARY KEY AUTOINCREMENT
    date          TEXT NOT NULL   -- ISO format YYYY-MM-DD
    category      TEXT NOT NULL
    amount        REAL NOT NULL   -- supports decimals (e.g. 45.50)
    member        TEXT NOT NULL   -- Self, Spouse, Dad, Mom, Kids
    payment_mode  TEXT NOT NULL   -- UPI, Cash, Card
    note          TEXT DEFAULT ''

Also maintains a small `settings` key/value table used to persist things
like the monthly family budget across sessions.
"""

import csv
import io
import json
import os
import sqlite3
from datetime import date

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "expenses.db")

VALID_MEMBERS = ["Self", "Spouse", "Dad", "Mom", "Kids"]
VALID_PAYMENT_MODES = ["UPI", "Cash", "Card"]
VALID_INCOME_SOURCES = ["Salary", "Business", "Freelance", "Interest", "Gift", "Other"]

# Preset categories (emoji labels are attached in app.py for display; these
# are the canonical values stored in the database).
VALID_CATEGORIES = [
    "Groceries & Household",
    "Food & Dining",
    "Bills & Utilities",
    "Transport & Fuel",
    "Health & Medical",
    "Shopping",
    "Entertainment & Leisure",
    "Other",
]


def get_connection():
    return sqlite3.connect(DB_PATH)


def _table_exists(cursor, table_name):
    cursor.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        (table_name,),
    )
    return cursor.fetchone() is not None


def _table_columns(cursor, table_name):
    cursor.execute(f"PRAGMA table_info({table_name})")
    return [row[1] for row in cursor.fetchall()]


def init_db():
    """Create the expenses/settings tables if missing, and migrate an
    existing legacy `expenses` table (old schema: id, category, amount)
    into the new rich schema in place, preserving every row."""
    connection = get_connection()
    cursor = connection.cursor()

    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT
        )
        """
    )

    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS income (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            amount REAL NOT NULL,
            member TEXT NOT NULL,
            source TEXT NOT NULL,
            note TEXT DEFAULT ''
        )
        """
    )
    connection.commit()

    if not _table_exists(cursor, "expenses"):
        cursor.execute(
            """
            CREATE TABLE expenses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL,
                category TEXT NOT NULL,
                amount REAL NOT NULL,
                member TEXT NOT NULL,
                payment_mode TEXT NOT NULL,
                note TEXT DEFAULT ''
            )
            """
        )
        connection.commit()
        connection.close()
        return

    columns = _table_columns(cursor, "expenses")
    is_legacy_schema = "date" not in columns

    if is_legacy_schema:
        # Preserve legacy rows (id, category, amount) by moving them into
        # the new schema with sensible defaults, rather than dropping data.
        cursor.execute("ALTER TABLE expenses RENAME TO expenses_legacy")
        cursor.execute(
            """
            CREATE TABLE expenses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL,
                category TEXT NOT NULL,
                amount REAL NOT NULL,
                member TEXT NOT NULL,
                payment_mode TEXT NOT NULL,
                note TEXT DEFAULT ''
            )
            """
        )
        today = date.today().isoformat()
        cursor.execute("SELECT category, amount FROM expenses_legacy")
        for category, amount in cursor.fetchall():
            cursor.execute(
                """
                INSERT INTO expenses (date, category, amount, member, payment_mode, note)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (today, category, amount, "Self", "UPI", "Migrated from legacy schema"),
            )
        cursor.execute("DROP TABLE expenses_legacy")
        connection.commit()

    connection.close()


def migrate_from_txt(txt_path="expenses.txt"):
    """One-time migration of legacy `Category-Amount` lines from
    expenses.txt into the database (date=today, member='Self',
    payment_mode='UPI'). Archives the source file as expenses.txt.bak
    afterwards so this never runs twice on the same data.

    Returns the number of rows migrated.
    """
    if not os.path.isabs(txt_path):
        txt_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), txt_path)

    if not os.path.exists(txt_path):
        return 0

    with open(txt_path, "r") as file:
        lines = file.readlines()

    today = date.today().isoformat()
    migrated = 0

    connection = get_connection()
    cursor = connection.cursor()

    for line in lines:
        line = line.strip()
        if not line or "-" not in line:
            continue

        category, amount = line.rsplit("-", 1)
        category = category.strip().title()
        amount = amount.strip()

        try:
            amount = float(amount)
        except ValueError:
            continue

        cursor.execute(
            """
            INSERT INTO expenses (date, category, amount, member, payment_mode, note)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (today, category, amount, "Self", "UPI", "Migrated from expenses.txt"),
        )
        migrated += 1

    connection.commit()
    connection.close()

    # Archive the source file so this migration is a one-time event, even
    # if no rows matched the expected format.
    os.replace(txt_path, txt_path + ".bak")

    return migrated


def add_expense(date_str, category, amount, member, payment_mode, note=""):
    connection = get_connection()
    cursor = connection.cursor()
    cursor.execute(
        """
        INSERT INTO expenses (date, category, amount, member, payment_mode, note)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (date_str, category, float(amount), member, payment_mode, note),
    )
    connection.commit()
    connection.close()


def _row_to_dict(row):
    return {
        "id": row[0],
        "date": row[1],
        "category": row[2],
        "amount": row[3],
        "member": row[4],
        "payment_mode": row[5],
        "note": row[6],
    }


def get_expenses(start_date=None, end_date=None, member=None, category=None):
    """Return expenses (newest first) optionally filtered by an inclusive
    date range, family member, and/or category."""
    connection = get_connection()
    cursor = connection.cursor()

    query = (
        "SELECT id, date, category, amount, member, payment_mode, note "
        "FROM expenses WHERE 1=1"
    )
    params = []

    if start_date:
        query += " AND date >= ?"
        params.append(start_date)
    if end_date:
        query += " AND date <= ?"
        params.append(end_date)
    if member:
        query += " AND member = ?"
        params.append(member)
    if category:
        query += " AND category = ?"
        params.append(category)

    query += " ORDER BY date DESC, id DESC"

    cursor.execute(query, params)
    rows = cursor.fetchall()
    connection.close()

    return [_row_to_dict(row) for row in rows]


def get_expense(id):
    connection = get_connection()
    cursor = connection.cursor()
    cursor.execute(
        "SELECT id, date, category, amount, member, payment_mode, note "
        "FROM expenses WHERE id = ?",
        (id,),
    )
    row = cursor.fetchone()
    connection.close()
    return _row_to_dict(row) if row else None


def update_expense(id, date_str, category, amount, member, payment_mode, note=""):
    connection = get_connection()
    cursor = connection.cursor()
    cursor.execute(
        """
        UPDATE expenses
        SET date = ?, category = ?, amount = ?, member = ?, payment_mode = ?, note = ?
        WHERE id = ?
        """,
        (date_str, category, float(amount), member, payment_mode, note, id),
    )
    connection.commit()
    connection.close()


def delete_expense(id):
    connection = get_connection()
    cursor = connection.cursor()
    cursor.execute("DELETE FROM expenses WHERE id = ?", (id,))
    connection.commit()
    connection.close()


def get_summary_stats(start_date=None, end_date=None):
    """Aggregate stats for the given (optional) date range: total spent,
    number of transactions, daily average (total / distinct days with any
    spending), per-category totals, per-member totals, and the top
    category/member by spend."""
    expenses = get_expenses(start_date=start_date, end_date=end_date)

    total = sum(e["amount"] for e in expenses)
    count = len(expenses)

    category_totals = {}
    member_totals = {}
    days_with_spend = set()

    for e in expenses:
        category_totals[e["category"]] = category_totals.get(e["category"], 0) + e["amount"]
        member_totals[e["member"]] = member_totals.get(e["member"], 0) + e["amount"]
        days_with_spend.add(e["date"])

    daily_average = total / len(days_with_spend) if days_with_spend else 0
    top_category = max(category_totals, key=category_totals.get) if category_totals else None
    top_member = max(member_totals, key=member_totals.get) if member_totals else None

    return {
        "total": total,
        "count": count,
        "daily_average": daily_average,
        "category_totals": category_totals,
        "member_totals": member_totals,
        "top_category": top_category,
        "top_member": top_member,
    }


def export_to_csv():
    """Return a CSV string of every expense (all-time, newest first)."""
    expenses = get_expenses()
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["id", "date", "category", "amount", "member", "payment_mode", "note"])
    for e in expenses:
        writer.writerow(
            [e["id"], e["date"], e["category"], e["amount"], e["member"], e["payment_mode"], e["note"]]
        )
    return output.getvalue()


def import_from_csv(file_stream):
    """Import rows from a CSV file-like object (as given by
    st.file_uploader). Expects columns: date, category, amount, member,
    payment_mode, note (id is ignored and regenerated). Malformed rows are
    skipped. Returns the number of rows imported."""
    content = file_stream.read()
    if isinstance(content, bytes):
        content = content.decode("utf-8")

    reader = csv.DictReader(io.StringIO(content))
    imported = 0

    connection = get_connection()
    cursor = connection.cursor()

    for row in reader:
        try:
            row_date = (row.get("date") or "").strip() or date.today().isoformat()
            category = (row.get("category") or "Other").strip() or "Other"
            amount = float(row.get("amount") or 0)
            member = (row.get("member") or "Self").strip() or "Self"
            payment_mode = (row.get("payment_mode") or "Cash").strip() or "Cash"
            note = row.get("note") or ""
        except (ValueError, AttributeError):
            continue

        cursor.execute(
            """
            INSERT INTO expenses (date, category, amount, member, payment_mode, note)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (row_date, category, amount, member, payment_mode, note),
        )
        imported += 1

    connection.commit()
    connection.close()

    return imported


def get_setting(key, default=None):
    connection = get_connection()
    cursor = connection.cursor()
    cursor.execute("SELECT value FROM settings WHERE key = ?", (key,))
    row = cursor.fetchone()
    connection.close()
    return row[0] if row else default


def set_setting(key, value):
    connection = get_connection()
    cursor = connection.cursor()
    cursor.execute(
        "INSERT INTO settings (key, value) VALUES (?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        (key, str(value)),
    )
    connection.commit()
    connection.close()


# =============================================================================
# PER-CATEGORY BUDGETS  (stored as one JSON blob in `settings`)
# =============================================================================
def get_category_budgets():
    """Return {category: amount} for categories with a budget set (> 0)."""
    try:
        data = json.loads(get_setting("category_budgets", "{}"))
        return {k: float(v) for k, v in data.items() if float(v) > 0}
    except (ValueError, TypeError, AttributeError):
        return {}


def set_category_budgets(mapping):
    """Persist per-category budgets; entries <= 0 are dropped."""
    clean = {k: float(v) for k, v in mapping.items() if float(v) > 0}
    set_setting("category_budgets", json.dumps(clean))


# =============================================================================
# INCOME  (separate table; keeps every expense query untouched)
# =============================================================================
def _income_row_to_dict(row):
    return {
        "id": row[0],
        "date": row[1],
        "amount": row[2],
        "member": row[3],
        "source": row[4],
        "note": row[5],
    }


def add_income(date_str, amount, member, source, note=""):
    connection = get_connection()
    cursor = connection.cursor()
    cursor.execute(
        "INSERT INTO income (date, amount, member, source, note) VALUES (?, ?, ?, ?, ?)",
        (date_str, float(amount), member, source, note),
    )
    connection.commit()
    connection.close()


def get_income(start_date=None, end_date=None, member=None):
    """Income rows (newest first), optionally filtered by inclusive date
    range and/or family member."""
    connection = get_connection()
    cursor = connection.cursor()

    query = "SELECT id, date, amount, member, source, note FROM income WHERE 1=1"
    params = []
    if start_date:
        query += " AND date >= ?"
        params.append(start_date)
    if end_date:
        query += " AND date <= ?"
        params.append(end_date)
    if member:
        query += " AND member = ?"
        params.append(member)
    query += " ORDER BY date DESC, id DESC"

    cursor.execute(query, params)
    rows = cursor.fetchall()
    connection.close()
    return [_income_row_to_dict(r) for r in rows]


def get_income_row(id):
    connection = get_connection()
    cursor = connection.cursor()
    cursor.execute(
        "SELECT id, date, amount, member, source, note FROM income WHERE id = ?", (id,)
    )
    row = cursor.fetchone()
    connection.close()
    return _income_row_to_dict(row) if row else None


def update_income(id, date_str, amount, member, source, note=""):
    connection = get_connection()
    cursor = connection.cursor()
    cursor.execute(
        "UPDATE income SET date = ?, amount = ?, member = ?, source = ?, note = ? WHERE id = ?",
        (date_str, float(amount), member, source, note, id),
    )
    connection.commit()
    connection.close()


def delete_income(id):
    connection = get_connection()
    cursor = connection.cursor()
    cursor.execute("DELETE FROM income WHERE id = ?", (id,))
    connection.commit()
    connection.close()


def get_income_total(start_date=None, end_date=None):
    return sum(r["amount"] for r in get_income(start_date=start_date, end_date=end_date))


def export_income_to_csv():
    rows = get_income()
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["id", "date", "amount", "member", "source", "note"])
    for r in rows:
        writer.writerow([r["id"], r["date"], r["amount"], r["member"], r["source"], r["note"]])
    return output.getvalue()


def import_income_from_csv(file_stream):
    """Import income rows from a CSV file-like object. Expects columns:
    date, amount, member, source, note (id is ignored). Malformed rows are
    skipped. Returns the number of rows imported."""
    content = file_stream.read()
    if isinstance(content, bytes):
        content = content.decode("utf-8")

    reader = csv.DictReader(io.StringIO(content))
    imported = 0

    connection = get_connection()
    cursor = connection.cursor()

    for row in reader:
        try:
            row_date = (row.get("date") or "").strip() or date.today().isoformat()
            amount = float(row.get("amount") or 0)
            member = (row.get("member") or "Self").strip() or "Self"
            source = (row.get("source") or "Other").strip() or "Other"
            note = row.get("note") or ""
        except (ValueError, AttributeError):
            continue
        if amount <= 0:
            continue
        cursor.execute(
            "INSERT INTO income (date, amount, member, source, note) VALUES (?, ?, ?, ?, ?)",
            (row_date, amount, member, source, note),
        )
        imported += 1

    connection.commit()
    connection.close()
    return imported
