# Multi-Branch Cooperative Bank Management System

A MySQL database project for **CS257 — Database and Information Systems Lab**.
It models banking across multiple branches, with transaction-safe financial
operations, a loan workflow, and SQL reporting. A local web app lets you perform
operations and refresh the tables to see their effects.

## Features

| Area | Supported functionality |
| --- | --- |
| Accounts | Savings, Current, and Fixed Deposit account opening; joint ownership; nominees; account states and subtype-specific terms |
| Banking | Deposits, withdrawals, and same-branch, inter-branch, and inter-bank transfers |
| Loans | Applications, guarantor linkage, approval/rejection, disbursement, monthly installments, repayment allocation, and closure |
| Reporting | Account/customer statements, transaction history, branch summaries, staffing, loan portfolios, and pending applications |
| Integrity | Primary/foreign keys, domain checks, composite references, chronology checks, and transactional balance updates |
| Concurrency | Row locking, concurrent-operation tests, and a separate lost-update experiment |

The schema contains **21 base tables**. Sample data covers two banks and four branches, all account
types, joint accounts, nominees, and loans at different lifecycle stages.

## Prerequisites

- **MySQL Server 8.0.16+**, running locally with InnoDB support. The performance experiments require 8.0.18+ for EXPLAIN ANALYZE.
- **MySQL command-line client** (`mysql`).
- **Python 3.9+** for the demo server and automated tests.
- A modern browser for the demo.

The app uses Python's standard library and plain HTML, CSS, and JavaScript.
No `pip install`, `npm install`, or frontend build step is needed. Node.js is optional
and used only for JavaScript syntax checks.

Run commands from the repository root. Examples below use PowerShell on Windows.
Demo scripts find `mysql` on PATH or use the standard MySQL Server 8.0 Windows path.

## Quick start

### 1. Configure MySQL access

Save a login once, entering your MySQL password when prompted:

```powershell
mysql_config_editor set --login-path=local --host=127.0.0.1 --user=root --password
mysql --login-path=local --execute="SELECT VERSION();"
```

If the executables are not on PATH, use their full paths from your MySQL `bin`
directory. The saved login avoids repeated password prompts and stays outside the
repository. Alternatively, add `--password` to the Python setup/server commands
below to enter the password once per process.

### 2. Create the presentation database — once

```powershell
python demo-app/setup_demo.py
```

This creates **CooperativeBankDemo**, loads sample data, and installs the schema,
constraints, banking procedures, loan procedures, reporting views, and indexes. It does not
change an existing `CooperativeBank` database or overwrite an existing demo database.

If the demo database already exists, skip setup. For a fresh dataset under a new name:

```powershell
python demo-app/setup_demo.py --name CooperativeBankDemo2
```

### 3. Start the app

```powershell
python demo-app/server.py --database CooperativeBankDemo
```

Open **http://127.0.0.1:8080**. Keep the terminal running; press **Ctrl+C** to stop.
Always pass the intended database: the server's default is `CooperativeBank`.

Choose **Banking** or **Loans**, select an operation, complete its form, and click
**Run operation**. Select a table and press **Refresh** to see the results. Changed
cells and new rows are highlighted on previously viewed pages. Tables display
50 rows per page.

## Presentation walkthrough

Use these seeded IDs in a newly created demo database:

| Step | Operation | Tables to inspect after Refresh |
| --- | --- | --- |
| 1 | Deposit `500` into account `1001`, channel `BRANCH` | Account, BankTransaction |
| 2 | Transfer `250` from `1001` to `2001`, channel `ONLINE` | Account, BankTransaction, TransferDetails |
| 3 | Transfer `100` from `1001` to `4001` (Pragati Cooperative Bank), then try withdrawing more than the available funds | Verify the error and unchanged balances/ledger |
| 4 | Apply for a PERSONAL loan: customer `1`, branch `1`, amount `10000`, purpose `Home renovation` | LoanApplication; note the returned application ID |
| 5 | Link guarantor `1` to that application, then approve using manager `1` | ApplicationGuarantor, LoanApplication |
| 6 | Disburse to account `1001`, annual interest `12`, tenure `3` months | Account, BankTransaction, Loan; note the returned loan ID |
| 7 | Generate installments using that loan ID | LoanInstallment |
| 8 | Repay `500` against that loan | Account, BankTransaction, Repayment, PaymentAllocation |

The interface generates banking RequestIDs. Reusing one is rejected without moving
funds again. Use a new application for another loan demonstration; an application
cannot be disbursed twice.

To inspect reports, connect to the demo database:

```powershell
mysql --login-path=local CooperativeBankDemo
```

```sql
SELECT * FROM v_branch_account_summary;
SELECT * FROM v_account_statement
WHERE AccountNo = 1001
ORDER BY TransactionDate, TransactionID;
SELECT * FROM v_loan_portfolio;
SELECT * FROM v_pending_applications;
```

The explorer groups its dropdown into Tables and Reports and audit views. Choose a
report and press Refresh to inspect statements, summaries, staffing, and portfolios.
The SQL queries above provide the same reports directly.

## Updating loan procedures

After changing `database/05_loans.sql`, update the existing demo database:

```powershell
python demo-app/install_loans.py --database CooperativeBankDemo
```

This replaces installed loan routines without resetting table data. Restart the
server after backend code changes, then reload the browser.

To refresh banking/loan routines, reporting views, and indexes together in an existing demo:

```powershell
python demo-app/setup_demo.py --update --name CooperativeBankDemo
```

This retains table records and skips indexes already installed with matching columns.
It also replaces the banking procedures, including the multi-bank Transfer procedure.
It does not migrate table definitions or reload sample data. For schema changes,
create a fresh demo database under a new name or prepare an explicit migration.

Loan procedures are installed directly from `database/05_loans.sql`, with no SQL
compatibility rewrites. The demo also installs `LinkLoanGuarantor` for its guarantor
form. `scripts/run_all.sh` builds the numbered SQL files for `CooperativeBank`; the
Python setup chooses a separate presentation database and adds that demo helper.

## Tests

Tests need MySQL credentials with permission to create and drop disposable databases.
Account-opening access tests also create and remove temporary users and roles.
They use generated database names rather than resetting the project database.

Run the demo unit checks and real MySQL/HTTP integration check:

```powershell
python -B -m unittest discover -s demo-app -p "test_*.py" -v
python -B demo-app/check_integration.py
```

The integration check covers banking, the loan lifecycle through closure, rejected
operations, table/report endpoints, reporting consistency, installed indexes, and repeatable updates. It currently uses the standard MySQL 8.0 Windows
client path and the `local` login path.

Run the core schema, seed, banking, account-opening, and loan tests:

```powershell
python -B -m unittest discover -s tests -p "test_*.py" -v
```

Core tests use `mysql` on PATH, or the `MYSQL_TEST_CLIENT` executable path.
Connection defaults are `127.0.0.1:3306`, user `root`. Override them with
`MYSQL_TEST_HOST`, `MYSQL_TEST_PORT`, and `MYSQL_TEST_USER`. Supply the
password through `MYSQL_PWD` when the client has no default credentials.
The demo HTTP integration check uses the separate `local` login path.

Account-opening tests need credentials that can grant privileges. The
[loan suite](tests/test_loans.py) builds and tests `05_loans.sql` in a disposable
database. Its concurrent repayment case reads MySQL's Performance Schema lock
tables to coordinate the two sessions.

After building `CooperativeBank`, run the two SQL checks. Both should return zero rows.

```powershell
mysql --login-path=local -e "source tests/smoke_tests.sql"
mysql --login-path=local -e "source tests/report_views_checks.sql"
```

Additional checks:

- [Concurrency experiment](experiments/concurrency/README.md) provides two-session
  demonstrations of lost updates, row locking, and SERIALIZABLE isolation.
- `node --check demo-app/app.js` checks JavaScript syntax if Node is installed.

## Repository guide

```text
database/
  01_schema.sql                 Tables, keys, and domain checks
  02_account_opening.sql        Atomic account-opening procedures
  02_constraints_triggers.sql   Additional business rules
  02_loan_dates.sql             Loan event chronology
  03_seed_data.sql              Representative sample records
  04_transactions.sql          Deposit, withdrawal, and transfer
  05_loans.sql                 Loan lifecycle procedures
  06_views.sql                 Reporting and integrity views
  07_indexes.sql               Transaction date and account/date indexes
demo-app/                     Frontend, Python server, setup, and tests
docs/                         Proposal, problem statement, ER, and design documents
experiments/concurrency/       Lost-update and locking/isolation demonstrations
experiments/indexing/          Measured plans before and after adding indexes
experiments/query_optimization/ SQL rewrites, measured plans, and result checks
scripts/                      Bash build/reset helpers and access grants
tests/                        Core integration tests, smoke tests, and reporting checks
```

## Design documents

- [Problem statement](docs/DBIS_problem_statement.pdf)
- [Project proposal](docs/DBIS_proposal.pdf)
- [Requirements specification](docs/requirements.md)
- [ER diagram](docs/er/ER_Diagram.pdf)
- [Normalization and functional dependencies](docs/normalization.md)
- [Final project report](docs/report/final_report.md)
- [CRUD walkthrough](docs/report/crud_demo.sql)
- [Indexing results](experiments/indexing/results.txt)
- [Query optimization results](experiments/query_optimization/results.txt)
- [Demo instructions and restricted-user setup](demo-app/README.md#restricted-demo-user)

## Scope limits

Ordinary deposits, withdrawals, and transfers support Savings and Current accounts.
FD maturity and closure require a separate workflow. Loan approval requires a linked
guarantor and a manager from the receiving branch; repayment requires an unpaid schedule.

Inter-bank transfers cover accounts of banks registered in this shared database.
The seed includes Sahyog (accounts `1001`?`3003`) and Pragati (accounts `4001`, `4002`).
The transaction history distinguishes `INTRA_BRANCH`, `INTER_BRANCH`, and `INTER_BANK`
and includes source/destination bank identifiers and names. External payment networks
and distributed settlement are outside scope. Account numbers remain globally unique.

The app is a local academic demo that runs real financial procedures against the
selected database. Use the separate presentation dataset for experiments. Sample
records have fixed IDs and should be loaded only once into empty tables.

The Bash helper `scripts/reset_db.sh` explicitly **drops and recreates CooperativeBank**,
deleting its data. It is unnecessary for the quick-start demo setup.

## Team

| Member | Roll number |
| --- | --- |
| Eklavya | 250001028 |
| Tanush Bansal | 250001071 |
| Chetan Yogbharti | 250001023 |
| Parth Kalia | 250001054 |
