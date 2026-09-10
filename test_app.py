"""Runnable self-check for the money paths. No framework: `python test_app.py`."""

import io
import os
import tempfile

import database as db


def main():
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    os.remove(path)
    db.DB_PATH = path
    db.init_db()

    # --- expenses core ---------------------------------------------------
    db.add_expense("2026-09-01", "Food & Dining", 45.50, "Self", "UPI", "lunch")
    db.add_expense("2026-09-02", "Groceries & Household", 1200, "Mom", "Cash", "")
    s = db.get_summary_stats("2026-09-01", "2026-09-30")
    assert abs(s["total"] - 1245.50) < 1e-6, s["total"]
    assert s["top_member"] == "Mom", s["top_member"]

    # --- income CRUD ---------------------------------------------------
    db.add_income("2026-09-05", 60000, "Self", "Salary", "sept pay")
    db.add_income("2026-09-20", 5000.50, "Spouse", "Freelance", "")
    assert abs(db.get_income_total("2026-09-01", "2026-09-30") - 65000.50) < 1e-6
    assert db.get_income_total("2026-08-01", "2026-08-31") == 0

    inc = db.get_income()
    assert len(inc) == 2 and inc[0]["date"] == "2026-09-20", "income not newest-first"

    iid = inc[0]["id"]
    db.update_income(iid, "2026-09-20", 7000, "Spouse", "Business", "edited")
    assert db.get_income_row(iid)["source"] == "Business"
    db.delete_income(iid)
    assert db.get_income_row(iid) is None
    assert abs(db.get_income_total() - 60000) < 1e-6

    # --- net (income - spent) ----------------------------------------
    net = db.get_income_total("2026-09-01", "2026-09-30") - db.get_summary_stats(
        "2026-09-01", "2026-09-30"
    )["total"]
    assert abs(net - (60000 - 1245.50)) < 1e-6, net

    # --- per-category budgets --------------------------------------
    assert db.get_category_budgets() == {}
    db.set_category_budgets({"Food & Dining": 3000, "Shopping": 0, "Transport & Fuel": 2000.0})
    cb = db.get_category_budgets()
    assert cb == {"Food & Dining": 3000.0, "Transport & Fuel": 2000.0}, cb  # 0 dropped

    # --- income CSV round trip ------------------------------------
    csv_text = db.export_income_to_csv()
    assert "Salary" in csv_text
    n = db.import_income_from_csv(io.BytesIO(csv_text.encode("utf-8")))
    assert n == 1, n
    assert abs(db.get_income_total() - 120000) < 1e-6

    os.remove(path)
    print("ALL CHECKS PASSED")


if __name__ == "__main__":
    main()
