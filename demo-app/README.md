# Presentation demo

A local, dependency-free web app: Python 3.9+ and your installed MySQL CLI.
Banking and Loans have separate operation forms. Table explorer reads all 21 tables,
50 rows per page. Refresh highlights new rows and changed cells on a previously viewed page.
Records stay visible until you refresh, so you can explain the before/after in your presentation.

## Start

From the repository root, create the presentation database once:

```powershell
python demo-app/setup_demo.py
```

This creates **CooperativeBankDemo**, never replaces an existing database, and does
not modify CooperativeBank or any project SQL file. It loads the schema, constraints,
seed data, account opening, transactions, and reporting view. It extracts only the
ApplyLoan procedure from 05_loans.sql, excluding that file's independent demo inserts
and sample calls. On a setup failure it retains the new database for inspection.
Use `--name AnotherDemoName` to create a fresh separate demonstration database.

Then start the app:

```powershell
python demo-app/server.py --database CooperativeBankDemo
```

Open **http://127.0.0.1:8080**. Stop with Ctrl+C.
Both commands use your saved MySQL `local` login path. If unavailable, add
`--password` to enter your password once in the terminal; it is not saved in files
or sent to the browser. The server accepts `--port`, `--mysql`, and `--database`.
Running without `--database` selects CooperativeBank, so use the command above for the demo.

## Presentation walkthrough

1. Open Banking → Deposit money. View Account and note account 1001's balance.
2. Enter account 1001, amount 500, channel BRANCH. A unique request ID is provided.
3. Run operation, then Refresh. The changed balance is highlighted.
4. Select BankTransaction to show the successful transaction and its returned ID.
5. Transfer funds from 1001 to 2001, amount 250, channel ONLINE. Refresh Account;
   view TransferDetails and BankTransaction to explain the atomic operation.
6. Open Loans → Apply for a loan. Use customer 1, branch 1, type PERSONAL,
   amount 10000, purpose Home renovation. Run and refresh LoanApplication to see PENDING.
7. Explore Loan, LoanInstallment, Repayment, and PaymentAllocation to show the seeded
   examples. Approval/rejection, disbursement, EMI generation, and repayment procedures
   are not implemented in the project's current loan file; the interface labels them pending.

The three account-opening procedures are also supported. Use an unused account
number, an existing branch/customer, and values satisfying your database constraints.
Missing installed procedures are disabled. Database validation errors are displayed.

## Scope

This is a single-presenter local app, listening only on 127.0.0.1. Financial actions
call the actual procedures; there is no simulated success or direct balance update.
It does not install procedures automatically on startup. Credentials remain server-side.
The HTTP write endpoint uses an unpredictable session token and checks the local Host.
Use the isolated demo database for presentation experiments. No external assets,
Python packages, Node dependencies, or build step are required.

## Checks

```powershell
python -B -m unittest discover -s demo-app -p "test_*.py" -v
node --check demo-app/app.js
```

The real MySQL/HTTP integration check creates and removes its own disposable database:

```powershell
python -B demo-app/check_integration.py
```
