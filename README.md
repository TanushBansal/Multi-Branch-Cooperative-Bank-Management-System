# Multi-Branch Cooperative Bank Management System

A **CS257 Database and Information Systems Lab** project built with MySQL. The system
manages customers, accounts, branches, employees, financial transactions, and loans
across multiple banks. A local demo app lets you perform operations and refresh the
database records to inspect the results.

## Team and responsibilities

| Member | Roll number | Work |
| --- | --- | --- |
| **Tanush Bansal** | 250001071 | Transaction processing and the concurrency experiment |
| **Chetan Yogbharti** | 250001023 | Loan lifecycle: application, review, disbursement, installments, and repayment |
| **Eklavya** | 250001028 | Relational schema, constraints, and triggers |
| **Parth Kalia** | 250001054 | Indexing and the demo application |

## What the project supports

- Savings, Current, and Fixed Deposit accounts, including joint holders and nominees.
- Deposits, withdrawals, and transfers within a branch, across branches, and across banks.
- Loan applications, guarantor links, approval/rejection, disbursement, EMI schedules,
  repayment allocation, and loan closure.
- Account/customer statements, branch summaries, transaction history, and loan reports.
- Transaction rollback, row-level locking, and duplicate-request protection for banking operations.

The schema has **21 base tables**. The seed dataset contains **two banks, four branches,
and twelve accounts**. Account `3002` is jointly held by customers `1` and `5`.
Accounts `4001` and `4002` belong to the second bank, Pragati Cooperative Bank.

## Requirements

| Software | Purpose |
| --- | --- |
| MySQL Server 8.0.16+ with InnoDB | Database, constraints, stored procedures, and transactions |
| MySQL command-line tools | `mysql`, `mysql_config_editor`, and SQL script execution |
| Python 3.9+ | Demo server, setup utilities, and automated tests |
| Modern browser | Demo frontend |
| Bash / Git Bash | Optional shell build and reset scripts |

Performance experiments use `EXPLAIN ANALYZE`, which requires MySQL 8.0.18+.
The project has been tested with MySQL 8.0.46. Node.js is optional for JavaScript
syntax checks. The demo uses Python's standard library and plain HTML/CSS/JavaScript;
there is no package installation or frontend build step.

Run all commands below from the **repository root**. Terminal examples use PowerShell
unless marked otherwise. MySQL Server must be running before setup.

## 1. Configure a MySQL connection

Save a local login once, entering your MySQL password when prompted:

```powershell
mysql_config_editor set --login-path=local --host=127.0.0.1 --user=root --password
mysql --login-path=local --execute="SELECT VERSION();"
```

The second command verifies the connection. The Python utilities use this `local`
login path so you do not need to enter the password for every operation.

If MySQL tools are not on PATH, use their full executable paths from the MySQL `bin`
directory. Python utilities also check the standard MySQL Server 8.0 installation
path on Windows. Alternatively, add `--password` to the Python setup/server commands
to enter a password once per process.

## 2. Build and run the presentation demo

### Create the demo database

```powershell
python -B demo-app/setup_demo.py
```

This creates **CooperativeBankDemo**, installs tables, constraints, triggers, account
opening, banking and loan procedures, and indexes, then loads the sample records.
It also installs the guarantor-linking helper used by the frontend. Reports are
computed directly from SQL queries.

Run setup only once for a given database name. It refuses to replace an existing
database. If the demo is already built, start the server directly.

### Start the app

```powershell
python -B demo-app/server.py --database CooperativeBankDemo
```

Open **http://127.0.0.1:8080**. Keep the terminal running and use **Ctrl+C** to stop.
`-B` prevents Python from creating bytecode cache files.

To use a separate, freshly seeded database while keeping an existing demo:

```powershell
python -B demo-app/setup_demo.py --name CooperativeBankMultiBankDemo
python -B demo-app/server.py --database CooperativeBankMultiBankDemo --port 8081
```

Open **http://127.0.0.1:8081** for that instance. Choose the same database name in
both commands. The dataset comes from the current seed file, regardless of the name.

### How the app works

```text
Browser form
    -> Python backend validates the operation and its parameters
    -> MySQL stored procedure performs the operation
    -> Backend returns the result or database error
    -> Refresh reloads the selected table or report
```

**Banking** contains account opening, deposits, withdrawals, and transfers.
**Loans** contains the loan lifecycle operations. The Next button carries returned
application/loan IDs into the following form; you still submit each operation yourself.

The data explorer lists all tables and ten reports. It displays 50 rows per page.
After an operation, press **Refresh** to inspect its effects. New rows and changed
cells are highlighted on previously inspected pages.

For a restricted database user, follow the [demo access instructions](demo-app/README.md#restricted-demo-user).
They grant table reads and procedure execution while preventing direct financial-table writes.
Use `--user bank_demo --password` together when starting with that user.

## 3. Build the main database directly

The numbered SQL files build **CooperativeBank**. Use this path for SQL-only work
and the concurrency experiment. It is separate from the presentation databases above.

For a **fresh build**, open the MySQL client:

```powershell
mysql --login-path=local
```

Then execute:

```sql
SOURCE database/01_schema.sql;
SOURCE database/02_account_opening.sql;
SOURCE database/02_constraints_triggers.sql;
SOURCE database/02_loan_dates.sql;
SOURCE database/03_seed_data.sql;
SOURCE database/04_transactions.sql;
SOURCE database/05_loans.sql;
SOURCE database/06_reports.sql;
SOURCE database/07_indexes.sql;
```

| File | What it does |
| --- | --- |
| `01_schema.sql` | Creates the database, tables, keys, and base checks |
| `02_account_opening.sql` | Creates atomic account-opening procedures |
| `02_constraints_triggers.sql` | Adds cross-table business rules and triggers |
| `02_loan_dates.sql` | Enforces loan-event chronology |
| `03_seed_data.sql` | Inserts the demonstration records in dependency order |
| `04_transactions.sql` | Creates deposit, withdrawal, and transfer procedures |
| `05_loans.sql` | Creates the five loan lifecycle procedures |
| `06_reports.sql` | Runs ten standalone reporting queries |
| `07_indexes.sql` | Adds transaction-date and account/date indexes |

These commands initialize a new database; they are not a migration for an existing
schema. Seed IDs are fixed, so loading the seed again produces duplicate-key errors.
The direct build supports guarantor linkage through `ApplicationGuarantor`; the
Python demo setup additionally installs `LinkLoanGuarantor` for the app's form.

### Optional Bash helpers

```bash
bash scripts/run_all.sh
```

This runs the numbered SQL files in filename order and stops at the first failing
file. It requires Bash and `mysql` on PATH. It uses `MYSQL_HOST` (default `localhost`),
`MYSQL_USER` (default `root`), and optional `MYSQL_PASSWORD`, or the client's default
credentials. It does not explicitly select the named `local` login path used above.

```bash
bash scripts/reset_db.sh
```

**Reset deletes the entire CooperativeBank database and recreates it empty.** Use it
only when you intend to discard that database's records, then run the build again.
It does not reset the separately named demo databases.

### Refresh procedures in an existing database

```powershell
python -B demo-app/install_loans.py --database CooperativeBankDemo
python -B demo-app/setup_demo.py --update --name CooperativeBankDemo
```

The first command updates loan procedures and the guarantor helper. The second
refreshes banking/loan procedures and adds missing matching indexes while retaining
table records. Choose the database you actually use. Neither command migrates table
columns or triggers, nor reloads seed data. Reapply restricted-user grants after
reinstalling procedures, following the demo access instructions.

## Banking transactions

Financial operations use stored procedures in [04_transactions.sql](database/04_transactions.sql).
Each call owns one transaction and must run outside another active transaction.

| Procedure | Action |
| --- | --- |
| `Deposit` | Credits an active Savings/Current account and records the deposit |
| `Withdraw` | Checks funds and minimum balance, then records and debits the withdrawal |
| `Transfer` | Locks both accounts, creates transfer details, and commits the debit/credit together |

Example calls in a seeded database:

```sql
USE CooperativeBank;

CALL Deposit(1001, 500.00, 'BRANCH', 'demo-deposit-001', @TransactionID);
SELECT @TransactionID;

CALL Withdraw(1001, 100.00, 'ATM', 'demo-withdraw-001', @TransactionID);

CALL Transfer(1001, 2001, 250.00, 'ONLINE', 'demo-inter-branch-001', @TransactionID);
CALL Transfer(1001, 4001, 100.00, 'ONLINE', 'demo-inter-bank-001', @TransactionID);
```

Use a new RequestID for each intended operation. Reusing one is rejected without
posting the movement again. Amounts must be positive whole cents within the allowed
range. Ordinary financial operations reject FD accounts and inactive accounts.

The procedures use **READ COMMITTED** and **SELECT ... FOR UPDATE**. A conflicting
operation waits for the account lock, then reads its current balance. Transfers
lock accounts in ascending account-number order to reduce deadlocks. An exception
rolls back the balance changes, transaction entry, and transfer details together.

Inter-bank transfers operate between registered banks inside the same MySQL database.
The transaction report distinguishes `INTRA_BRANCH`, `INTER_BRANCH`, and `INTER_BANK`
and displays both bank names. Account numbers are globally unique across these banks.

## Loan lifecycle

Loan procedures are defined in [05_loans.sql](database/05_loans.sql).

| Stage | Operation | Effect |
| --- | --- | --- |
| Apply | `ApplyLoan` | Creates a PENDING row in `LoanApplication` |
| Link guarantor | `LinkLoanGuarantor` in the demo, or an `ApplicationGuarantor` insert | Associates an existing guarantor with the application |
| Review | `ReviewLoan` | Records approval/rejection, manager, and decision date |
| Disburse | `DisburseLoan` | Creates or funds a Loan and credits its payout account atomically |
| Schedule | `GenerateInstallments` | Creates monthly principal and interest obligations |
| Repay | `RepayLoan` | Debits funds, records repayment, and allocates it to the oldest unpaid installments |
| Close | Performed by repayment | Marks the loan CLOSED when the generated schedule is fully paid |

**Approval alone does not create a Loan row.** It updates `LoanApplication`.
Disbursement requires the payout account, interest rate, and tenure; after that step,
the funded loan appears in `Loan`.

A reviewing manager must belong to the receiving branch, and approval requires a
linked guarantor. Disbursement requires an active Savings/Current account held by
the applicant. Existing sanctioned loans retain their loan ID, payout account, amount,
rate, and tenure when funded.

EMIs use a reducing-balance calculation with an annual interest rate converted to a
monthly rate. Zero-interest schedules are supported, and the final principal component
absorbs rounding. Partial repayment and payments spanning several installments are
supported. Repayment preserves the payout account's minimum balance.

### Suggested presentation sequence

1. Note account `1001`'s balance, deposit `500`, and refresh Account and BankTransaction.
2. Transfer `100` from `1001` to `4001`; inspect both balances and the transaction report.
3. Apply for a loan using customer `1`, branch `1`, amount `10000`, and purpose `Home repair`.
4. Link guarantor `1` to the returned application ID, then approve through manager `1`.
5. Disburse that application to `1001`, with annual interest `12` and tenure `3` months.
6. Generate installments using the returned LoanID, repay `500`, and inspect Repayment
   and PaymentAllocation. Use the remaining scheduled amount to demonstrate closure.

## Constraints and triggers

The [schema](database/01_schema.sql), [business-rule triggers](database/02_constraints_triggers.sql),
and [loan-date checks](database/02_loan_dates.sql) enforce rules at different levels:

| Rule | Enforcement |
| --- | --- |
| Valid references and unique identities | Primary, foreign, and unique keys |
| Valid PAN and IFSC formats | CHECK constraints |
| Positive amounts, nonnegative balances/rates, and valid FD dates | CHECK constraints |
| Matching account/employee subtypes | Composite foreign keys and fixed discriminator checks |
| Account type cannot change after creation | Account update trigger |
| Account subtype records cannot be deleted or reassigned | Subtype delete/update triggers |
| Approval requires a guarantor; its last guarantor cannot be removed | Approval/link triggers and a designated-guarantor foreign key |
| Loan must reference an approved application | Composite application/status foreign key |
| Sanction amount cannot exceed the application request | Loan and application update/insert triggers |
| Financial references must match the required type, status, amount, and account | Composite foreign keys |
| Decision, sanction, funding, due dates, and repayment follow a valid timeline | Chronology procedures called by triggers |
| Allocations must belong to the same loan as both linked records | Composite foreign keys |

Account-opening procedures create the account, matching subtype, and first holder
together, recording a deposit when the opening amount is positive. Some workflow rules depend on using procedures
through restricted access; privileged direct table writes are a separate access path.

## Experiments

### 1. Concurrency: lost update and row locking

[Instructions and session scripts](experiments/concurrency/README.md)

Two MySQL sessions withdraw `1000` and `2000` from an account starting at `10000`.
Session A waits 15 seconds after reading the balance so the sessions overlap.

| Scenario | Result |
| --- | --- |
| `WithdrawUnsafe` without a locking read | Both read `10000`; the final stored balance becomes `9000`, while the ledger implies `7000` |
| `WithdrawLocked` with `FOR UPDATE` | The second session waits, reads the updated balance, and the final balance is `7000` |

In the MySQL client, prepare the dedicated experiment accounts:

```sql
SOURCE experiments/concurrency/00_setup.sql;
```

Use two separate MySQL terminals. Run A first, then B within 15 seconds:

| Scenario | Session A | Session B |
| --- | --- | --- |
| Lost update | `SOURCE experiments/concurrency/10_lost_update_A.sql;` | `SOURCE experiments/concurrency/10_lost_update_B.sql;` |
| Row-locking fix | `SOURCE experiments/concurrency/20_row_lock_A.sql;` | `SOURCE experiments/concurrency/20_row_lock_B.sql;` |

After each scenario, run:

```sql
SOURCE experiments/concurrency/verify.sql;
```

The script compares stored balance with the successful transaction ledger. The
expected difference is `2000` for the anomaly and `0` for the locking fix. These
scripts target `CooperativeBank`, using accounts `9100000001` and `9100000002`.
Restore them after the demonstration:

```sql
CALL ConcurrencyDemoReset(9100000001);
CALL ConcurrencyDemoReset(9100000002);
```

### 2. Indexing: faster transaction searches

[Index definitions](database/07_indexes.sql) | [Recorded plans and timings](experiments/indexing/results.txt)

`ix_transaction_date` supports date-range searches across accounts.
`ix_transaction_account_date` supports searches for one account within a date range.
These InnoDB B-tree indexes reduce the rows that need to be examined for suitable queries.
They also require storage and maintenance during writes.

| Recorded query | Median before | Median after |
| --- | ---: | ---: |
| Transaction date range | 120 ms | 2.58 ms |
| Account and date range | 0.146 ms | 0.0642 ms |

The recorded benchmark used 300,024 transactions. The plans show a full table scan
changing to a date index range scan, and an account lookup changing to a narrower
account/date range scan. Timings describe that benchmark workload and machine.

### 3. Query optimization: remove repeated work

[Original queries, rewrites, and measured plans](experiments/query_optimization/results.txt)

| Case | Rewrite | Recorded median change |
| --- | --- | --- |
| Accounts above their branch average | Calculate branch averages once in a CTE, then join | 10,770 ms to 12 ms |
| Accounts with more than ten successful transactions | Replace per-account counts with grouped aggregation | 627 ms to 584 ms |

Both rewrites were checked for identical result IDs. The second case showed a modest
improvement with overlapping timing samples. The results files contain SQL, plans,
and measurements; dataset-generation and automated benchmark runners are not included.

## Reports

Ten reports in [06_reports.sql](database/06_reports.sql) cover account overviews,
branch balances/staffing, transaction history, account/customer statements, loan
portfolios, pending applications, and transfer-integrity checks.

They run as SELECT queries and statement-local CTEs. Names, columns, and row keys
come from [report_catalog.json](demo-app/report_catalog.json), in query order.
Include this catalog when sharing the project.

To run one report directly from the terminal:

```powershell
python -B demo-app/reports.py transaction_history | mysql --login-path=local CooperativeBankDemo
```

## Verification

```powershell
python -B -m unittest discover -s tests -p "test_*.py" -v
python -B -m unittest discover -s demo-app -p "test_*.py" -v
python -B demo-app/check_integration.py
```

The core tests cover schema integrity, account opening, seed consistency, financial
operations, loan workflows, rollback, and concurrent sessions. The demo tests cover
the report loader and backend; the HTTP check exercises the operation and report
endpoints. Database integration tests create and remove disposable schemas.

Core tests need credentials with database create/drop privileges; account-access
tests additionally create temporary users/roles. Set `MYSQL_TEST_CLIENT` if `mysql`
is not on PATH, and `MYSQL_TEST_HOST`, `MYSQL_TEST_PORT`, or `MYSQL_TEST_USER` if needed.
Supply credentials through `MYSQL_PWD` when the client has no default credentials.
The HTTP integration check uses the `local` login path and the standard MySQL 8.0
Windows executable path.

After building the main database, these SQL checks should return zero rows:

```powershell
mysql --login-path=local --execute="source tests/smoke_tests.sql"
mysql --login-path=local --execute="source tests/report_checks.sql"
```

The [CRUD walkthrough](docs/report/crud_demo.sql) demonstrates customer, branch, and
account operations and rolls its record changes back. Run it against the seeded
`CooperativeBank` database.

## Repository structure

```text
database/                   Schema, constraints, procedures, seed data, reports, indexes
demo-app/                   Frontend, Python backend, setup tools, report catalog, tests
docs/                       Proposal, requirements, ER diagram, normalization, final report
experiments/concurrency/     Two-session anomaly and row-locking demonstration
experiments/indexing/        Recorded index benchmark results
experiments/query_optimization/ Recorded query-rewrite results
scripts/                    Build/reset scripts and database access grants
tests/                      Database integration tests and SQL consistency checks
```

## Documentation

- [Problem statement](docs/DBIS_problem_statement.pdf)
- [Project proposal](docs/DBIS_proposal.pdf)
- [Requirements specification](docs/requirements.md)
- [ER diagram](docs/er/ER_Diagram.pdf)
- [Normalization and functional dependencies](docs/normalization.md)
- [Final report](docs/report/final_report.md)
- [Detailed demo guide](demo-app/README.md)

The implemented workflows cover banks registered inside one shared database.
External payment-network settlement, FD maturity/closure, and automatic loan-default
classification are outside the current implementation.
