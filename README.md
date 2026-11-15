# Multi-Branch Cooperative Bank Management System

DBIS Lab (CS257) project. A relational database system for a multi-branch cooperative bank, covering customer and account management, branch and employee management, atomic and concurrency-safe transaction processing, a loan lifecycle with guarantors and EMI schedules, and reporting.

Problem statement: https://drive.google.com/file/d/1O-rlJTe_RvUfFdJQnFa5k7VxSm0PuZpK/view?usp=drive_link

## Requirements

MySQL 8.0.16 or later (CHECK constraints are enforced from this version).

## Building the database

From the repository root:

    ./scripts/reset_db.sh      # drops and recreates the CooperativeBank database
    ./scripts/run_all.sh       # runs database/01 to 07 in numeric order

Set MYSQL_USER, MYSQL_PASSWORD (optional) and MYSQL_HOST (optional) in the environment, or edit the variables at the top of each script.

## Repository layout

    docs/                    Proposal, problem statement, ER diagram, UML, normalization, report
    database/                Numbered SQL files, executed in order
      01_schema.sql            Tables and base constraints
      02_account_opening.sql   Atomic account-opening procedures
      02_constraints_triggers.sql   Additional constraints and triggers
      02_loan_dates.sql        Loan event chronology checks and triggers
      03_seed_data.sql         Demonstration dataset
      04_transactions.sql      Deposit, withdrawal, transfer procedures
      05_loans.sql             Loan application, approval, disbursal, EMI, repayment
      06_views.sql             Reporting views
      07_indexes.sql           Indexes (kept separate for before/after comparison)
    experiments/             Self-contained experiments, not part of the core build
      concurrency/             Lost-update anomaly and its resolution
      indexing/                Bulk data generator and timing comparison
      query_optimization/      Slow queries, rewrites and EXPLAIN output
    scripts/                 Helper scripts to reset and build the database
    tests/                   Smoke tests (balance reconciliation, constraint checks)

## Demonstration data

`database/03_seed_data.sql` populates all 21 tables with fictional data as of
2026-11-15. Load it once after the schema and constraints/triggers on empty tables:

    mysql --login-path=local --execute="source database/03_seed_data.sql"

The data includes three branches, joint accounts, nominees, every account type,
active/frozen/closed accounts, intra-/inter-branch transfers, and approved,
rejected, and pending applications. Loans demonstrate active, closed, sanctioned,
and defaulted states, with EMI schedules and partial/multi-installment repayments.
Balances reconcile with successful transaction history; pending and failed
attempts do not affect balances. The file uses plain INSERT statements in dependency
order. If an insert fails, earlier successful inserts remain in the database.
Do not rerun it to add more data: its fixed demonstration IDs are intentionally unique.

Validate the data in a disposable database with the same test environment settings
described below:

    python -m unittest discover -s tests -p test_seed_data.py -v

## Loan event dates

Load 02_loan_dates.sql after the schema and other constraints (run_all.sh includes
it automatically). Decisions cannot precede applications, sanctions cannot precede
approval, and disbursements cannot precede sanction. Installment due dates must be
after the disbursement day, or after sanction for a schedule prepared before funding.
Repayment PaidAt and its financial transaction date cannot precede funding (or
sanction when undisbursed). Eligibility of undisbursed loans for repayment remains
a separate workflow rule.

DATE fields are compared by calendar day; repayment timestamps use the exact
funding time. Linked disbursement/repayment transaction timestamps become immutable.
Changing a sanction, decision, funding reference, installment, or repayment is also
checked against existing dependent events using locking reads. Deadlocks can require
retrying a complete transaction. Monthly schedule generation is separate from these
date checks; the in-progress 05_loans.sql has not been changed.

## Loan approval guarantors

Create an application as PENDING, insert its ApplicationGuarantor links, then
update Status to APPROVED together with ReviewedBy and DecisionDate. The approval
trigger chooses ApprovalGuarantorID automatically. Its composite foreign key
requires that designated guarantor to remain linked to the same application.
Direct APPROVED inserts are rejected because the application must exist before
guarantor links can be created. The seed script follows this order using plain SQL.

Deleting or moving a designated link automatically selects another linked guarantor;
removing the last link is rejected. To replace a sole guarantor, insert the new link
first, then remove the old one. Locks and the designation FK protect concurrent
approval, deletion, and reassignment. Deadlocks or stale-snapshot FK failures may
require retrying the complete transaction; they cannot leave an approved application
without a guarantor. Administrative seed-validation tests exclude the independent,
in-progress demonstration code in 05_loans.sql.

## Loan transaction references

Loan sanctions cannot exceed the application's RequestedAmount. Triggers in
02_constraints_triggers.sql validate inserts, amount changes, and application
reassignment; application updates cannot lower the request below an existing
sanction. Equality is allowed. Locking reads protect simultaneous changes;
deadlocks may require retrying a complete transaction.

`Loan.ApplicationStatus` defaults to APPROVED and is fixed by a CHECK. A composite
foreign key requires its application to actually be approved, and prevents changing
the application to PENDING or REJECTED while a loan references it. Existing loan
inserts can omit the defaulted ApplicationStatus field.

A disbursed Loan references a successful LOAN_DISBURSEMENT transaction with the
same payout account and sanction amount. Set DisbursementTransactionID,
DisbursementTransactionType='LOAN_DISBURSEMENT', and
DisbursementTransactionStatus='SUCCESS' together when moving beyond SANCTIONED.
All three fields must be NULL while the loan remains SANCTIONED. Composite foreign
keys block later changes to the referenced transaction's account, amount, type, or status.

Repayment.TransactionType and TransactionStatus default to LOAN_REPAYMENT and
SUCCESS and are fixed by checks. Its composite foreign key also requires the
repayment amount to match the transaction amount. Existing repayment inserts can
omit the two defaulted fields. These constraints validate transaction links; loan
disbursal and repayment workflows will be implemented in 05_loans.sql.

`PaymentAllocation.LoanID` is required and must match both its repayment's loan
and its installment's loan. Composite foreign keys protect these relationships
on inserts and updates, including moves of the referenced repayment or installment.
This rule validates loan membership; allocation totals are a separate constraint.

## Employee roles

`Employee.EmployeeRole` is MANAGER, CLERK, or NULL for an employee with neither
specialization. Set the parent role before inserting into Manager or Clerk; their
role columns default to the corresponding fixed value. Composite foreign keys
and checks prevent mismatched roles on inserts and updates, including concurrent
writes. A referenced employee's role cannot change until its existing subtype row
is removed (and removing that row may be blocked by existing loan-review references).
Employees are not required to have a subtype row: this specialization remains partial.

## Account opening

`02_account_opening.sql` creates each account together with its matching subtype
and first holder in one transaction. A positive opening amount also creates a
successful deposit record. Zero opening amounts are allowed for Savings/Current
accounts with a zero minimum balance. Fixed deposits require positive principal.

```sql
CALL OpenSavingsAccount(5001, 1, 1, '2026-11-15', 4.00, 1000.00, 5000.00, 'open-5001');
CALL OpenCurrentAccount(5002, 1, 1, '2026-11-15', 5000.00, 10000.00, 'open-5002');
CALL OpenFixedDeposit(5003, 1, 1, '2026-11-15', '2027-11-15', 25000.00, 6.50, 'open-5003');
```

Arguments start with account number, branch ID, and customer ID. Savings then takes
opening date, annual interest rate, minimum balance, opening amount, and RequestID.
Current omits the interest rate. Fixed Deposit takes start date, maturity date,
principal, annual interest rate, and RequestID. Use existing branches/customers and
new account numbers. Call outside an existing transaction. Accounts are retained
when closed: subtype deletion and reassignment are blocked by triggers in script 02.

For application access, an administrator can run `scripts/account_access.sql`
after the full build. It creates `cooperative_account_operator`, granting read access
to account records and execution of the opening/transaction procedures, without
direct INSERT, UPDATE, DELETE, or TRUNCATE privileges on the account tables.
Assign it to a dedicated existing application user:

```sql
GRANT 'cooperative_account_operator' TO 'bank_app'@'localhost';
SET DEFAULT ROLE 'cooperative_account_operator' TO 'bank_app'@'localhost';
```

Replace the user/host with your actual dedicated account. It must have no broader
table/global write grants or other roles granting them. This setup does not create
or change a real application user automatically. Root retains administrative access
and can still insert incomplete accounts directly; use it for the plain seed import
and validate the resulting data. Total specialization is guaranteed through the
restricted account-opening interface, rather than by unrestricted table inserts.

Account-opening tests also create/drop a random test user and role, requiring those
administrative permissions as well as disposable-database access:

    python -m unittest discover -s tests -p test_account_opening.py -v

## Transaction procedures

`database/04_transactions.sql` creates `Deposit`, `Withdraw`, and `Transfer`.
For an existing database with the schema and triggers loaded, install this file once:

    mysql --login-path=local --execute="source database/04_transactions.sql"

Run these examples in MySQL, replacing account numbers with existing accounts:

```sql
USE CooperativeBank;
CALL Deposit(1001, 500.00, 'BRANCH', 'deposit-001', @TransactionID);
SELECT @TransactionID;
CALL Withdraw(1001, 100.00, 'ATM', 'withdrawal-001', @TransactionID);
SELECT @TransactionID;
CALL Transfer(1001, 2001, 250.00, 'ONLINE', 'transfer-001', @TransactionID);
SELECT @TransactionID;
```

Each call commits its own transaction and must run outside an existing transaction.
Use a new RequestID for each operation. Reusing a RequestID raises a duplicate-key
error without moving funds again. Failed calls roll back balance changes and log
rows together; successful calls return their TransactionID through the OUT parameter.
Deadlocks and lock timeouts also roll back the call and can be retried by the caller.

Amounts must be positive, fit DECIMAL(15,2), and contain whole cents. Both transfer
accounts must be active and belong to the same bank; transfers can cross branches.
Withdrawals and transfers preserve the source account's minimum balance. These
ordinary operations support Savings and Current accounts; FD funding, maturity,
and closure require a separate workflow. Concurrent calls use row locks, with
transfer accounts locked in ascending account-number order.

`TransferDetails.TransactionType` defaults to TRANSFER and is fixed by a CHECK.
Its composite foreign key to BankTransaction prevents links to other transaction
types, including later changes to either side. Existing inserts can omit this column.
Deletion or reassignment of transfer details (transaction, source, or destination)
is blocked. Application transfers must use the Transfer procedure and the restricted
role; administrators importing records directly should check:

```sql
SELECT * FROM v_transfer_integrity_violations;
```

This view from 06_views.sql must return no rows after import. It covers transfers
in every status. The view detects omissions; it does not reject incomplete direct
administrative inserts. Root retains administrative privileges, including TRUNCATE.

Integration tests create and remove a uniquely named disposable database, load
the real schema/triggers/procedures, and exercise rollback and concurrent sessions:

    python -m unittest discover -s tests -p test_transactions.py -v

Tests require Python 3.9+ and the MySQL CLI on PATH (or `MYSQL_TEST_CLIENT` set to
its executable path). Set `MYSQL_TEST_HOST`, `MYSQL_TEST_PORT`, and `MYSQL_TEST_USER`
if different from 127.0.0.1, 3306, and root. Supply credentials through the client's
existing login configuration or `MYSQL_PWD`. The test user needs permission to
create and drop the disposable database. Tests do not alter CooperativeBank.

## Team

Eklavya (250001028), Tanush Bansal (250001071), Chetan Yogbharti (250001023), Parth Kalia (250001054)
