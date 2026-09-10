# =============================================================================
# FAMILY EXPENSE TRACKER — Mobile-First Dashboard
# =============================================================================
# Run with:
#   streamlit run app.py
# For access from a phone on the same Wi-Fi (see .streamlit/config.toml):
#   http://<your-pc-ip>:8501
# =============================================================================

from datetime import date, timedelta

import pandas as pd
import streamlit as st

import database as db

# =============================================================================
# PAGE CONFIGURATION
# =============================================================================
# "centered" keeps a single, comfortably narrow column — the right shape for
# a phone screen instead of a wide desktop dashboard.
st.set_page_config(
    page_title="Family Expense Tracker",
    page_icon="💳",
    layout="centered",
)

# =============================================================================
# STARTUP: DB INIT + ONE-TIME LEGACY MIGRATION
# =============================================================================
db.init_db()
_migrated = db.migrate_from_txt("expenses.txt")
if _migrated:
    st.session_state.setdefault("_migration_notice", _migrated)

CATEGORY_EMOJI = {
    "Groceries & Household": "🛒",
    "Food & Dining": "🍔",
    "Bills & Utilities": "💡",
    "Transport & Fuel": "🚗",
    "Health & Medical": "💊",
    "Shopping": "🛍️",
    "Entertainment & Leisure": "🎬",
    "Other": "📦",
}
CATEGORY_LABELS = [f"{CATEGORY_EMOJI[c]} {c}" for c in db.VALID_CATEGORIES]
LABEL_TO_CATEGORY = dict(zip(CATEGORY_LABELS, db.VALID_CATEGORIES))

MEMBER_EMOJI = {"Self": "🙋", "Spouse": "💑", "Dad": "👨", "Mom": "👩", "Kids": "🧒"}
PAYMENT_EMOJI = {"UPI": "📱", "Cash": "💵", "Card": "💳"}
SOURCE_EMOJI = {
    "Salary": "💼", "Business": "🏢", "Freelance": "💻",
    "Interest": "🏦", "Gift": "🎁", "Other": "💰",
}

DEFAULT_BUDGET = 50000

# =============================================================================
# CUSTOM CSS — mobile-first, large tap targets, dark theme
# =============================================================================
st.markdown(
    """
<style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');

    * { font-family: 'Inter', sans-serif; }

    .stApp { background-color: #0e1117; }

    .block-container {
        padding-top: 1.5rem;
        padding-bottom: 3rem;
        max-width: 560px;
    }

    .dashboard-header { text-align: center; padding: 0.5rem 0 1rem 0; }
    .dashboard-header h1 { color: #ffffff; font-size: 1.9rem; font-weight: 700; margin-bottom: 0.2rem; }
    .dashboard-header p { color: #8b949e; font-size: 0.95rem; font-weight: 300; }
    .header-accent {
        height: 3px;
        background: linear-gradient(90deg, #7c3aed, #3b82f6, #06b6d4);
        border-radius: 2px;
        margin: 0.6rem auto;
        width: 50%;
    }

    .metric-card {
        background: #161b22;
        border-radius: 16px;
        padding: 1.1rem;
        text-align: center;
        border: 1px solid #21262d;
        box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
        position: relative;
        overflow: hidden;
        margin-bottom: 0.8rem;
    }
    .metric-card::before {
        content: '';
        position: absolute; top: 0; left: 0; right: 0; height: 4px;
        background: linear-gradient(90deg, #7c3aed, #3b82f6);
    }
    .metric-value { font-size: 1.5rem; font-weight: 700; color: #ffffff; margin: 0.3rem 0; word-break: break-word; }
    .metric-label {
        font-size: 0.78rem; color: #8b949e; font-weight: 500;
        text-transform: uppercase; letter-spacing: 0.5px;
    }

    .section-title {
        color: #ffffff; font-size: 1.1rem; font-weight: 600;
        margin: 1.2rem 0 0.7rem 0; display: flex; align-items: center; gap: 0.5rem;
    }

    .budget-card {
        background: #161b22; border-radius: 16px; padding: 1.2rem;
        border: 1px solid #21262d; margin-bottom: 0.5rem;
    }
    .budget-row { display: flex; justify-content: space-between; font-size: 0.85rem; color: #8b949e; margin-bottom: 0.5rem; }
    .budget-bar-bg { background: #0d1117; border-radius: 8px; height: 14px; overflow: hidden; border: 1px solid #21262d; }
    .budget-bar-fill { height: 100%; border-radius: 8px; transition: width 0.4s ease; }

    .category-badge {
        display: inline-block; background: linear-gradient(135deg, #7c3aed22, #3b82f622);
        color: #c9d1d9; padding: 0.45rem 0.9rem; border-radius: 10px; margin: 0.25rem;
        font-size: 0.85rem; border: 1px solid #30363d;
    }
    .category-amount { font-weight: 700; color: #7c3aed; }

    input[type="text"], input[type="number"], textarea {
        background-color: #0d1117 !important; color: #c9d1d9 !important;
        border: 1px solid #30363d !important; border-radius: 10px !important;
        padding: 0.7rem 1rem !important; font-size: 1rem !important;
    }
    input:focus, textarea:focus {
        border-color: #7c3aed !important; box-shadow: 0 0 0 2px rgba(124, 58, 237, 0.2) !important;
    }
    label { color: #8b949e !important; font-weight: 500 !important; }

    .stButton > button {
        background: linear-gradient(135deg, #7c3aed, #3b82f6) !important;
        color: white !important; border: none !important; border-radius: 10px !important;
        padding: 0.75rem 1rem !important; font-weight: 600 !important;
        font-size: 1rem !important; min-height: 3rem !important;
    }
    .stButton > button:hover { box-shadow: 0 6px 20px rgba(124, 58, 237, 0.4) !important; }
    .stDownloadButton > button {
        background: #161b22 !important; color: #c9d1d9 !important;
        border: 1px solid #30363d !important; border-radius: 10px !important; min-height: 3rem !important;
    }

    hr { border-color: #21262d !important; margin: 1.2rem 0 !important; }
    .stAlert { border-radius: 10px !important; }
    #MainMenu {visibility: hidden;}
    footer {visibility: hidden;}

    .expense-card {
        background: #161b22; border-radius: 14px; padding: 0.9rem 1.1rem;
        margin-bottom: 0.6rem; border: 1px solid #21262d;
    }
    .expense-card-top { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.4rem; }
    .expense-date { color: #8b949e; font-size: 0.78rem; font-weight: 500; }
    .expense-amount { color: #ffffff; font-weight: 700; font-size: 1.15rem; }
    .expense-tags { display: flex; gap: 0.4rem; flex-wrap: wrap; margin-bottom: 0.3rem; }
    .tag { font-size: 0.75rem; padding: 0.2rem 0.6rem; border-radius: 8px; border: 1px solid #30363d; color: #c9d1d9; }
    .tag-category { background: #7c3aed22; }
    .tag-member { background: #3b82f622; }
    .tag-payment { background: #06b6d422; }
    .expense-note { color: #8b949e; font-size: 0.85rem; font-style: italic; }

    [data-testid="stExpander"] {
        background: #161b22; border-radius: 14px; border: 1px solid #21262d;
    }
</style>
""",
    unsafe_allow_html=True,
)

if st.session_state.get("_migration_notice"):
    st.success(
        f"✅ Migrated {st.session_state['_migration_notice']} legacy expense(s) from "
        f"expenses.txt into the database. The original file was archived as expenses.txt.bak."
    )
    del st.session_state["_migration_notice"]

# =============================================================================
# HEADER
# =============================================================================
st.markdown(
    """
<div class="dashboard-header">
    <h1>💳 Family Expense Tracker</h1>
    <p>Track, manage, and analyze family spending</p>
    <div class="header-accent"></div>
</div>
""",
    unsafe_allow_html=True,
)

# =============================================================================
# MONTH SELECTOR
# =============================================================================
today = date.today()
current_month_start = today.replace(day=1)
if current_month_start.month == 1:
    last_month_start = current_month_start.replace(year=current_month_start.year - 1, month=12)
else:
    last_month_start = current_month_start.replace(month=current_month_start.month - 1)
last_month_end = current_month_start - timedelta(days=1)

period = st.selectbox(
    "Period",
    ["Current Month", "Last Month", "All Time"],
    index=0,
    key="period_select",
)

if period == "Current Month":
    range_start, range_end = current_month_start.isoformat(), today.isoformat()
elif period == "Last Month":
    range_start, range_end = last_month_start.isoformat(), last_month_end.isoformat()
else:
    range_start, range_end = None, None

stats = db.get_summary_stats(start_date=range_start, end_date=range_end)
period_income = db.get_income_total(range_start, range_end)
period_net = period_income - stats["total"]

# =============================================================================
# METRIC CARDS
# =============================================================================
m1, m2 = st.columns(2)
with m1:
    st.markdown(
        f"""<div class="metric-card">
            <div class="metric-label">Total Spent</div>
            <div class="metric-value">₹{stats['total']:,.2f}</div>
        </div>""",
        unsafe_allow_html=True,
    )
with m2:
    st.markdown(
        f"""<div class="metric-card">
            <div class="metric-label">Daily Average</div>
            <div class="metric-value">₹{stats['daily_average']:,.2f}</div>
        </div>""",
        unsafe_allow_html=True,
    )

m3, m4 = st.columns(2)
with m3:
    top_cat_display = stats["top_category"] or "—"
    st.markdown(
        f"""<div class="metric-card">
            <div class="metric-label">Top Category</div>
            <div class="metric-value" style="font-size:1.05rem;">{top_cat_display}</div>
        </div>""",
        unsafe_allow_html=True,
    )
with m4:
    top_member_display = stats["top_member"] or "—"
    st.markdown(
        f"""<div class="metric-card">
            <div class="metric-label">Top Spender</div>
            <div class="metric-value" style="font-size:1.05rem;">{top_member_display}</div>
        </div>""",
        unsafe_allow_html=True,
    )

m5, m6 = st.columns(2)
with m5:
    st.markdown(
        f"""<div class="metric-card">
            <div class="metric-label">Income</div>
            <div class="metric-value" style="color:#22c55e;">₹{period_income:,.2f}</div>
        </div>""",
        unsafe_allow_html=True,
    )
with m6:
    net_color = "#22c55e" if period_net >= 0 else "#ef4444"
    net_sign = "+" if period_net >= 0 else "−"
    st.markdown(
        f"""<div class="metric-card">
            <div class="metric-label">Net (Income − Spent)</div>
            <div class="metric-value" style="color:{net_color};">{net_sign} ₹{abs(period_net):,.2f}</div>
        </div>""",
        unsafe_allow_html=True,
    )

# =============================================================================
# MONTHLY BUDGET
# =============================================================================
st.markdown('<div class="section-title">🎯 Monthly Budget</div>', unsafe_allow_html=True)

saved_budget = float(db.get_setting("monthly_budget", DEFAULT_BUDGET))
budget = st.number_input(
    "Family monthly budget (₹)",
    min_value=0.0,
    value=saved_budget,
    step=500.0,
    key="budget_input",
)
if budget != saved_budget:
    db.set_setting("monthly_budget", budget)

month_stats = db.get_summary_stats(start_date=current_month_start.isoformat(), end_date=today.isoformat())
spent_this_month = month_stats["total"]
pct = (spent_this_month / budget * 100) if budget > 0 else 0
pct_display = min(pct, 100)

if pct >= 100:
    bar_color = "#ef4444"
elif pct >= 80:
    bar_color = "#f59e0b"
else:
    bar_color = "#22c55e"

st.markdown(
    f"""<div class="budget-card">
        <div class="budget-row">
            <span>₹{spent_this_month:,.2f} spent this month</span>
            <span>{pct:,.0f}% of ₹{budget:,.0f}</span>
        </div>
        <div class="budget-bar-bg">
            <div class="budget-bar-fill" style="width:{pct_display}%; background:{bar_color};"></div>
        </div>
    </div>""",
    unsafe_allow_html=True,
)
if pct >= 100:
    st.error("⚠️ Family budget exceeded for this month.")
elif pct >= 80:
    st.warning("⚠️ Over 80% of this month's budget used.")

income_this_month = db.get_income_total(current_month_start.isoformat(), today.isoformat())
left_this_month = income_this_month - spent_this_month
left_color = "#22c55e" if left_this_month >= 0 else "#ef4444"
st.markdown(
    f"""<div class="budget-card">
        <div class="budget-row">
            <span>Money left this month</span>
            <span style="color:{left_color}; font-weight:700;">₹{left_this_month:,.2f}</span>
        </div>
        <div class="budget-row" style="font-size:0.78rem;">
            <span>income ₹{income_this_month:,.0f}</span>
            <span>− spent ₹{spent_this_month:,.0f}</span>
        </div>
    </div>""",
    unsafe_allow_html=True,
)

with st.expander("📂 Per-category budgets (this month)"):
    saved_cat_budgets = db.get_category_budgets()
    new_cat_budgets = {}
    for c in db.VALID_CATEGORIES:
        new_cat_budgets[c] = st.number_input(
            f"{CATEGORY_EMOJI[c]} {c}",
            min_value=0.0,
            step=500.0,
            value=float(saved_cat_budgets.get(c, 0.0)),
            key=f"catbud_{c}",
        )
    if {k: v for k, v in new_cat_budgets.items() if v > 0} != saved_cat_budgets:
        db.set_category_budgets(new_cat_budgets)
        saved_cat_budgets = db.get_category_budgets()

    active_cat_budgets = {c: b for c, b in saved_cat_budgets.items() if b > 0}
    if active_cat_budgets:
        st.markdown("<br>", unsafe_allow_html=True)
        for c, b in active_cat_budgets.items():
            spent_c = month_stats["category_totals"].get(c, 0.0)
            p_c = (spent_c / b * 100) if b > 0 else 0
            col_c = "#ef4444" if p_c >= 100 else "#f59e0b" if p_c >= 80 else "#22c55e"
            st.markdown(
                f"""<div class="budget-row"><span>{CATEGORY_EMOJI[c]} {c}</span>
                    <span>₹{spent_c:,.0f} / ₹{b:,.0f}</span></div>
                <div class="budget-bar-bg"><div class="budget-bar-fill"
                    style="width:{min(p_c, 100)}%; background:{col_c};"></div></div>
                <div style="height:0.7rem;"></div>""",
                unsafe_allow_html=True,
            )

st.divider()

# =============================================================================
# QUICK ADD EXPENSE
# =============================================================================
st.markdown('<div class="section-title">➕ Quick Add Expense</div>', unsafe_allow_html=True)

with st.form("add_expense_form", clear_on_submit=True):
    add_date = st.date_input("Date", value=today, max_value=today, key="add_date")
    add_amount = st.number_input("Amount (₹)", min_value=0.0, step=1.0, format="%.2f", key="add_amount")
    add_category_label = st.selectbox("Category", CATEGORY_LABELS, key="add_category")
    add_member = st.selectbox(
        "Family member",
        db.VALID_MEMBERS,
        format_func=lambda m: f"{MEMBER_EMOJI.get(m, '')} {m}",
        key="add_member",
    )
    add_payment = st.selectbox(
        "Payment mode",
        db.VALID_PAYMENT_MODES,
        format_func=lambda p: f"{PAYMENT_EMOJI.get(p, '')} {p}",
        key="add_payment",
    )
    add_note = st.text_input("Note (optional)", placeholder="e.g., Monthly veggies at D-Mart", key="add_note")

    submitted = st.form_submit_button("➕  Add Expense", use_container_width=True)
    if submitted:
        if add_amount <= 0:
            st.error("⚠️ Amount must be greater than 0")
        else:
            db.add_expense(
                add_date.isoformat(),
                LABEL_TO_CATEGORY[add_category_label],
                add_amount,
                add_member,
                add_payment,
                add_note.strip(),
            )
            st.success("✅ Expense added!")
            st.rerun()

st.divider()

# =============================================================================
# RECENT TRANSACTIONS
# =============================================================================
st.markdown('<div class="section-title">📋 Recent Transactions</div>', unsafe_allow_html=True)

f1, f2 = st.columns(2)
with f1:
    filter_category_label = st.selectbox("Filter by category", ["All"] + CATEGORY_LABELS, key="filter_category")
with f2:
    filter_member = st.selectbox("Filter by member", ["All"] + db.VALID_MEMBERS, key="filter_member")

search_term = st.text_input("Search notes/category", placeholder="Search…", key="search_term")

filter_category = LABEL_TO_CATEGORY.get(filter_category_label) if filter_category_label != "All" else None
filter_member_value = filter_member if filter_member != "All" else None

visible_expenses = db.get_expenses(
    start_date=range_start, end_date=range_end, member=filter_member_value, category=filter_category
)

if search_term.strip():
    term = search_term.strip().lower()
    visible_expenses = [
        e for e in visible_expenses
        if term in e["note"].lower() or term in e["category"].lower()
    ]

if not visible_expenses:
    st.info("No expenses match this view yet. Add one above 👆")
else:
    for e in visible_expenses:
        emoji = CATEGORY_EMOJI.get(e["category"], "📦")
        note_html = f'<div class="expense-note">📝 {e["note"]}</div>' if e["note"] else ""
        st.markdown(
            f"""<div class="expense-card">
                <div class="expense-card-top">
                    <span class="expense-date">{e['date']}</span>
                    <span class="expense-amount">₹{e['amount']:,.2f}</span>
                </div>
                <div class="expense-tags">
                    <span class="tag tag-category">{emoji} {e['category']}</span>
                    <span class="tag tag-member">{MEMBER_EMOJI.get(e['member'], '')} {e['member']}</span>
                    <span class="tag tag-payment">{PAYMENT_EMOJI.get(e['payment_mode'], '')} {e['payment_mode']}</span>
                </div>
                {note_html}
            </div>""",
            unsafe_allow_html=True,
        )

st.divider()

# =============================================================================
# EDIT / DELETE (via selector — no raw index typing)
# =============================================================================
st.markdown('<div class="section-title">⚙️ Edit or Delete a Transaction</div>', unsafe_allow_html=True)

all_expenses = db.get_expenses()
if not all_expenses:
    st.info("No transactions yet to edit or delete.")
else:
    options = {
        f"{e['date']} · {CATEGORY_EMOJI.get(e['category'], '📦')} {e['category']} · ₹{e['amount']:,.2f} · {e['member']}": e["id"]
        for e in all_expenses
    }
    selected_label = st.selectbox("Select a transaction", list(options.keys()), key="manage_select")
    selected_id = options[selected_label]
    selected = db.get_expense(selected_id)

    with st.form("edit_expense_form"):
        edit_date = st.date_input("Date", value=date.fromisoformat(selected["date"]), max_value=today, key="edit_date")
        edit_amount = st.number_input(
            "Amount (₹)", min_value=0.0, step=1.0, format="%.2f", value=float(selected["amount"]), key="edit_amount"
        )
        current_cat_label = f"{CATEGORY_EMOJI.get(selected['category'], '📦')} {selected['category']}"
        cat_index = CATEGORY_LABELS.index(current_cat_label) if current_cat_label in CATEGORY_LABELS else 0
        edit_category_label = st.selectbox("Category", CATEGORY_LABELS, index=cat_index, key="edit_category")
        edit_member = st.selectbox(
            "Family member",
            db.VALID_MEMBERS,
            index=db.VALID_MEMBERS.index(selected["member"]) if selected["member"] in db.VALID_MEMBERS else 0,
            format_func=lambda m: f"{MEMBER_EMOJI.get(m, '')} {m}",
            key="edit_member",
        )
        edit_payment = st.selectbox(
            "Payment mode",
            db.VALID_PAYMENT_MODES,
            index=db.VALID_PAYMENT_MODES.index(selected["payment_mode"]) if selected["payment_mode"] in db.VALID_PAYMENT_MODES else 0,
            format_func=lambda p: f"{PAYMENT_EMOJI.get(p, '')} {p}",
            key="edit_payment",
        )
        edit_note = st.text_input("Note (optional)", value=selected["note"], key="edit_note")

        ec1, ec2 = st.columns(2)
        with ec1:
            save_clicked = st.form_submit_button("✏️  Save Changes", use_container_width=True)
        with ec2:
            delete_clicked = st.form_submit_button("🗑️  Delete", use_container_width=True)

        if save_clicked:
            if edit_amount <= 0:
                st.error("⚠️ Amount must be greater than 0")
            else:
                db.update_expense(
                    selected_id,
                    edit_date.isoformat(),
                    LABEL_TO_CATEGORY[edit_category_label],
                    edit_amount,
                    edit_member,
                    edit_payment,
                    edit_note.strip(),
                )
                st.success("✅ Expense updated!")
                st.rerun()

        if delete_clicked:
            db.delete_expense(selected_id)
            st.success("✅ Expense deleted!")
            st.rerun()

st.divider()

# =============================================================================
# INCOME  (Quick Add + records + edit/delete)
# =============================================================================
st.markdown('<div class="section-title">💰 Income</div>', unsafe_allow_html=True)

with st.form("add_income_form", clear_on_submit=True):
    inc_date = st.date_input("Date", value=today, max_value=today, key="inc_date")
    inc_amount = st.number_input("Amount (₹)", min_value=0.0, step=1.0, format="%.2f", key="inc_amount")
    inc_member = st.selectbox(
        "Family member",
        db.VALID_MEMBERS,
        format_func=lambda m: f"{MEMBER_EMOJI.get(m, '')} {m}",
        key="inc_member",
    )
    inc_source = st.selectbox(
        "Source",
        db.VALID_INCOME_SOURCES,
        format_func=lambda s: f"{SOURCE_EMOJI.get(s, '')} {s}",
        key="inc_source",
    )
    inc_note = st.text_input("Note (optional)", placeholder="e.g., September salary", key="inc_note")

    inc_submitted = st.form_submit_button("➕  Add Income", use_container_width=True)
    if inc_submitted:
        if inc_amount <= 0:
            st.error("⚠️ Amount must be greater than 0")
        else:
            db.add_income(inc_date.isoformat(), inc_amount, inc_member, inc_source, inc_note.strip())
            st.success("✅ Income added!")
            st.rerun()

income_rows = db.get_income(start_date=range_start, end_date=range_end)
if not income_rows:
    st.info("No income recorded for this period.")
else:
    for r in income_rows:
        note_html = f'<div class="expense-note">📝 {r["note"]}</div>' if r["note"] else ""
        st.markdown(
            f"""<div class="expense-card">
                <div class="expense-card-top">
                    <span class="expense-date">{r['date']}</span>
                    <span class="expense-amount" style="color:#22c55e;">+ ₹{r['amount']:,.2f}</span>
                </div>
                <div class="expense-tags">
                    <span class="tag tag-payment">{SOURCE_EMOJI.get(r['source'], '💰')} {r['source']}</span>
                    <span class="tag tag-member">{MEMBER_EMOJI.get(r['member'], '')} {r['member']}</span>
                </div>
                {note_html}
            </div>""",
            unsafe_allow_html=True,
        )

all_income = db.get_income()
if all_income:
    inc_options = {
        f"{r['date']} · {SOURCE_EMOJI.get(r['source'], '💰')} {r['source']} · ₹{r['amount']:,.2f} · {r['member']}": r["id"]
        for r in all_income
    }
    inc_sel_label = st.selectbox("Edit or delete an income entry", list(inc_options.keys()), key="inc_manage_select")
    inc_sel_id = inc_options[inc_sel_label]
    inc_sel = db.get_income_row(inc_sel_id)

    with st.form("edit_income_form"):
        e_inc_date = st.date_input(
            "Date", value=date.fromisoformat(inc_sel["date"]), max_value=today, key="e_inc_date"
        )
        e_inc_amount = st.number_input(
            "Amount (₹)", min_value=0.0, step=1.0, format="%.2f", value=float(inc_sel["amount"]), key="e_inc_amount"
        )
        e_inc_member = st.selectbox(
            "Family member",
            db.VALID_MEMBERS,
            index=db.VALID_MEMBERS.index(inc_sel["member"]) if inc_sel["member"] in db.VALID_MEMBERS else 0,
            format_func=lambda m: f"{MEMBER_EMOJI.get(m, '')} {m}",
            key="e_inc_member",
        )
        e_inc_source = st.selectbox(
            "Source",
            db.VALID_INCOME_SOURCES,
            index=db.VALID_INCOME_SOURCES.index(inc_sel["source"]) if inc_sel["source"] in db.VALID_INCOME_SOURCES else 0,
            format_func=lambda s: f"{SOURCE_EMOJI.get(s, '')} {s}",
            key="e_inc_source",
        )
        e_inc_note = st.text_input("Note (optional)", value=inc_sel["note"], key="e_inc_note")

        ic1, ic2 = st.columns(2)
        with ic1:
            inc_save_clicked = st.form_submit_button("✏️  Save Changes", use_container_width=True)
        with ic2:
            inc_delete_clicked = st.form_submit_button("🗑️  Delete", use_container_width=True)

        if inc_save_clicked:
            if e_inc_amount <= 0:
                st.error("⚠️ Amount must be greater than 0")
            else:
                db.update_income(
                    inc_sel_id,
                    e_inc_date.isoformat(),
                    e_inc_amount,
                    e_inc_member,
                    e_inc_source,
                    e_inc_note.strip(),
                )
                st.success("✅ Income updated!")
                st.rerun()

        if inc_delete_clicked:
            db.delete_income(inc_sel_id)
            st.success("✅ Income deleted!")
            st.rerun()

st.divider()

# =============================================================================
# ANALYTICS & CHARTS
# =============================================================================
st.markdown('<div class="section-title">📊 Analytics</div>', unsafe_allow_html=True)

if stats["category_totals"]:
    st.caption("Spending by category")
    cat_df = pd.DataFrame(
        {"Category": list(stats["category_totals"].keys()), "Amount": list(stats["category_totals"].values())}
    ).set_index("Category")
    st.bar_chart(cat_df, color="#7c3aed")

    st.caption("Spending by family member")
    member_df = pd.DataFrame(
        {"Member": list(stats["member_totals"].keys()), "Amount": list(stats["member_totals"].values())}
    ).set_index("Member")
    st.bar_chart(member_df, color="#3b82f6")
else:
    st.info("Add some expenses to see analytics for this period.")

st.divider()

# =============================================================================
# BACKUP & RESTORE
# =============================================================================
with st.expander("💾 Backup & Restore"):
    csv_data = db.export_to_csv()
    st.download_button(
        "⬇️  Export Backup (CSV)",
        data=csv_data,
        file_name=f"expenses_backup_{today.isoformat()}.csv",
        mime="text/csv",
        use_container_width=True,
    )

    st.markdown("<br>", unsafe_allow_html=True)

    uploaded = st.file_uploader("Restore from CSV", type=["csv"], key="restore_upload")
    if uploaded is not None:
        if st.button("♻️  Import Uploaded CSV", use_container_width=True, key="restore_btn"):
            count = db.import_from_csv(uploaded)
            st.success(f"✅ Imported {count} expense(s) from CSV.")
            st.rerun()

    st.markdown("<hr>", unsafe_allow_html=True)

    st.download_button(
        "⬇️  Export Income (CSV)",
        data=db.export_income_to_csv(),
        file_name=f"income_backup_{today.isoformat()}.csv",
        mime="text/csv",
        use_container_width=True,
        key="inc_export_btn",
    )

    st.markdown("<br>", unsafe_allow_html=True)

    inc_uploaded = st.file_uploader("Restore income from CSV", type=["csv"], key="inc_restore_upload")
    if inc_uploaded is not None:
        if st.button("♻️  Import Income CSV", use_container_width=True, key="inc_restore_btn"):
            inc_count = db.import_income_from_csv(inc_uploaded)
            st.success(f"✅ Imported {inc_count} income record(s) from CSV.")
            st.rerun()

# =============================================================================
# FOOTER
# =============================================================================
st.markdown("<br>", unsafe_allow_html=True)
st.markdown(
    """<div style="text-align: center; color: #484f58; font-size: 0.8rem; padding: 1rem 0;">
        Built with 💜 for the family · Python & Streamlit
    </div>""",
    unsafe_allow_html=True,
)
