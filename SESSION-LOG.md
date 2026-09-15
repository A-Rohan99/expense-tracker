# Session Log

## Date: 2026-09-11
### Agent: Antigravity (Gemini 3.8 Flash)

### Task
Implement the CRED-aesthetic Dashboard UI in Flutter using Riverpod to fetch and compute real-time financial data from the FastAPI backend.

### What was done
1. **Financial Models** (`frontend/lib/models/`):
   - Created [Account](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/models/account.dart) model for liquid asset tracking (Bank, Cash, Wallets).
   - Created [CreditCard](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/models/credit_card.dart) and [CreditCardSummary](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/models/credit_card.dart) models mirroring backend dynamic billing computations (billed, unbilled, available limit, due dates).
   - Created [Loan](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/models/loan.dart) model for principal, interest rate, tenure, and outstanding liabilities.
   - Created [TransactionModel](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/models/transaction.dart) representing unified ledger transactions.
   - Created [DashboardSummary](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/models/dashboard_summary.dart) composite state model.

2. **State Management & Data Providers** (`frontend/lib/providers/`):
   - Created [dashboard_providers.dart](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/providers/dashboard_providers.dart):
     - `HouseholdModeNotifier` (Riverpod 3.x `Notifier<bool>`) controlling Private vs Household filtering.
     - `accountsProvider`, `creditCardsProvider`, `creditCardSummariesProvider`, `loansProvider`.
     - `monthlyTransactionsProvider` filtering by current month and household flag.
     - `dashboardSummaryProvider` combining all endpoints to compute Total Liquid Balance, Net Cashflow, Total Debt, and breakdowns.

3. **UI Components & Widgets** (`frontend/lib/widgets/` & `frontend/lib/screens/`):
   - Created [CurrencyFormatter](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/utils/currency_formatter.dart) supporting Indian numbering format (Lakhs/Crores) and compact formats.
   - Created [AnimatedAmountCounter](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/widgets/animated_counter.dart) with fluid count-up animation on load.
   - Created [HouseholdToggle](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/widgets/household_toggle.dart) with pill-switch aesthetics and neon highlight.
   - Created [HeroBalanceSection](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/widgets/hero_balance_section.dart) showcasing Total Liquid Balance and positive/negative colored Net Cashflow indicator.
   - Created [DebtCard](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/widgets/debt_card.dart) elevated `#1E1E1E` card with neon glow, liability ratio bar, and credit card/loan breakdown.
   - Created [AccountsListCard](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/widgets/accounts_list_card.dart), [CreditCardsListCard](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/widgets/credit_cards_list_card.dart), [LoansListCard](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/widgets/loans_list_card.dart), and [RecentActivityCard](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/widgets/recent_activity_card.dart).
   - Created [DashboardScreen](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/screens/dashboard_screen.dart) featuring CRED single-column layout, pull-to-refresh, loading shimmers, error recovery, and staggered entrance animations via `flutter_animate`.
   - Connected `/home` route in [main.dart](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/lib/main.dart).

4. **Testing & Verification**:
   - Added unit tests in [frontend/test/dashboard_test.dart](file:///c:/Users/yashm/OneDrive/Personel%20Projects/expense_tracker/frontend/test/dashboard_test.dart).
   - Ran `flutter analyze --no-pub` — 0 errors, 0 warnings.
   - Ran `flutter test` — all 11 tests passed.

## Feature Additions: Credit Line Alarms & Active Loan Tracker

### What was done
1. **Credit Card Alarms UI** (`frontend/lib/widgets/credit_card_alarms_list.dart`):
   - Created horizontally scrollable list of Credit Card widgets displaying dynamic statement cycle and due dates.
   - Dynamic 3-tier Alarm styling based on calculated `daysUntilDue`:
     - `daysUntilDue > 7`: Subtle Obsidian styling with cyan accents.
     - `daysUntilDue <= 7`: Glowing **Neon Amber** (`#FFB300`) border, amber ambient glow shadow, and countdown badge.
     - `daysUntilDue < 0` (Overdue): Pulsating **Neon Red** (`#FF2A2A`) accent, red status badge, and continuous pulsing animation via `flutter_animate`.
   - Tactile **"PAY BILL"** button on each card triggering `PayBillBottomSheet`.

2. **Tactile Pay Bill Bottom Sheet** (`frontend/lib/widgets/pay_bill_bottom_sheet.dart`):
   - Bottom sheet allowing the user to select the amount (Billed Amount, Total Due, Minimum Due).
   - Bank Account selector showing live available balances and preventing payments when balance is insufficient.
   - Triggers `POST /transactions/` as a `transfer` transaction.
   - Success tick animation and automatic reactive refresh of all dashboard providers.

3. **Pending EMIs Tick-to-Pay UI** (`frontend/lib/widgets/pending_emis_section.dart` & `frontend/lib/utils/loan_calculator.dart`):
   - Created `LoanCalculator.calculateMonthlyEmi` implementing the standard reducing-balance EMI formula matching the FastAPI backend.
   - Displays loan name, monthly calculated EMI amount in bold CRED typography, interest rate, and outstanding balance.
   - Prominent, tactile **"MARK AS PAID"** tickbox button.
   - Confirmation/Account selection bottom sheet to choose payment source.
   - Executes `POST /loans/{loan_id}/pay-emi` to atomically deduct bank funds and reduce loan principal.
   - Smooth success animation with elastic checkmark, principal/interest component breakdown badge, and haptic feedback.

4. **Riverpod Payment Controller** (`frontend/lib/providers/payment_providers.dart`):
   - Created `PaymentController` (Riverpod `Notifier<PaymentState>`) managing `payCreditCardBill` and `payLoanEmi`.
   - Invalidates all asset, liability, transaction, and dashboard providers upon payment.

5. **Integrated in DashboardScreen** (`frontend/lib/screens/dashboard_screen.dart`):
   - Embedded horizontally scrollable `CreditCardAlarmsList` and `PendingEmisSection` with fluid staggered animations.

### Rejected Alternatives
- **Rejected client-side state mutation for debt reduction**: Payment triggers the actual FastAPI backend endpoints (`/transactions/` transfer and `/loans/{id}/pay-emi`) to ensure the double-entry ledger remains mathematically balanced and server-authoritative.
- **Rejected hardcoded EMI amounts**: Dynamically calculated monthly EMIs using the amortization formula $E = P \cdot r \cdot \frac{(1+r)^n}{(1+r)^n - 1}$.
- **Rejected `StateProvider`**: In Riverpod 3.x, `StateProvider` is deprecated in favor of `NotifierProvider` / `Notifier<bool>`.
- **Rejected static billing balance in cards**: Preserved the double-entry architecture where credit card billing and liabilities are computed on the fly through `/credit-cards/{id}/summary`.
- **Rejected hardcoded currency symbol / comma splits**: Built custom `CurrencyFormatter` with Indian numbering system (Lakhs and Crores).
