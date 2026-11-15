# Presentation demo

A local, dependency-free web app: Python 3.9+ and your installed MySQL CLI.
Banking and Loans have separate operation forms. Data explorer reads all 21 tables and 10 reporting/audit views,
50 rows per page. Refresh highlights new rows and changed cells on a previously viewed page.
Records stay visible until you refresh, so you can explain the before/after in your presentation.

## Start

From the repository root, create the presentation database once:

```powershell
python demo-app/setup_demo.py
```

This creates **CooperativeBankDemo**, never replaces an existing database, and does
not modify CooperativeBank or any project SQL file. It loads the schema, constraints,
seed data, account opening, transactions, reporting views, and indexes. It installs
the five loan procedures directly from 05_loans.sql without rewriting their bodies. On a setup failure it retains the new database for inspection.
Use `--name AnotherDemoName` to create a fresh separate demonstration database.

To update loan procedures in an existing presentation database without resetting its data:

```powershell
python demo-app/install_loans.py --database CooperativeBankDemo
```

Restart the server after changing its Python code, then reload the browser.
The installer also adds LinkLoanGuarantor for linking an existing guarantor to an
application. To refresh loans, reporting views, and indexes together:

```powershell
python demo-app/setup_demo.py --update --name CooperativeBankDemo
```

This preserves table records and skips matching existing indexes. It does not
migrate table definitions or reload seed data; create a fresh database for schema
changes or use a separate migration.

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
7. Select Link a guarantor: use the returned application ID and existing guarantor 1.
8. Select Approve or reject application: use that application ID, manager 1, and Approve.
9. Select Disburse a loan: use that application ID, account 1001, interest rate 12,
   and tenure 3 months. Note the returned LoanID; refresh Loan and Account.
10. Select Generate installments with that LoanID, then refresh LoanInstallment.
11. Select Repay a loan with that LoanID and amount 500. Refresh Repayment,
    PaymentAllocation, and Account. Repaying the remaining schedule balance closes the loan.

Approval requires a linked guarantor and a manager from the application's branch.
Review can also reject a pending application. Disbursement requires approval and an
active account held by the applicant. Repayment requires generated installments.

In the data explorer, choose Reports and audit views to inspect account/customer
statements, branch summaries, staffing, transaction history, loan portfolios, pending
applications, or missing transfer details. Refresh loads the latest report values.

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
