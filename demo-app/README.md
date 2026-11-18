# Presentation demo

A local, dependency-free web app: Python 3.9+ and your installed MySQL CLI.
Banking and Loans have separate operation forms. The data explorer reads all 21 tables,
50 rows per page. Refresh highlights new rows and changed cells on a previously viewed page.
Records stay visible until you refresh, so you can explain the before/after in your presentation.

## Start

From the repository root, create the presentation database once:

```powershell
python demo-app/setup_demo.py
```

This creates **CooperativeBankDemo**, never replaces an existing database, and does
not modify CooperativeBank or any project SQL file. It loads the schema, constraints,
seed data, account opening, transactions, and indexes. It installs
the five loan procedures directly from 05_loans.sql without rewriting their bodies. On a setup failure it retains the new database for inspection.
Use `--name AnotherDemoName` to create a fresh separate demonstration database.

To update loan procedures in an existing presentation database without resetting its data:

```powershell
python demo-app/install_loans.py --database CooperativeBankDemo
```

Restart the server after changing its Python code, then reload the browser.
The installer also adds LinkLoanGuarantor for linking an existing guarantor to an
application. To refresh banking/loan routines and indexes together:

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

## Restricted demo user

After creating the demo schema, use an administrator connection to install the
role. For the default schema, open `mysql --login-path=local` from the repo root
and run:

```sql
SOURCE scripts/demo_access.sql;
```

If your presentation uses `CooperativeBankDemo2`, apply the grants to that
schema from PowerShell:

```powershell
(Get-Content -Raw .\scripts\demo_access.sql).Replace(
    'CooperativeBankDemo', 'CooperativeBankDemo2'
) | mysql --login-path=local
```

In the administrator's MySQL session, create the demo user if it does not already
exist and keep the generated password for startup. Reuse your existing
`bank_demo` account if it has the role.

```sql
CREATE USER 'bank_demo'@'localhost' IDENTIFIED BY RANDOM PASSWORD;
GRANT 'cooperative_demo_operator' TO 'bank_demo'@'localhost';
SET DEFAULT ROLE 'cooperative_demo_operator' TO 'bank_demo'@'localhost';
```

Start the app with the restricted user:

```powershell
python -B demo-app/server.py --database CooperativeBankDemo --user bank_demo --password
```

Replace `CooperativeBankDemo` with `CooperativeBankDemo2` in the startup and
verification commands if you granted access to the second schema. Check that
the app can read a table and post a deposit. The following verification
command should return `UPDATE command denied`:

```powershell
mysql -h 127.0.0.1 -u bank_demo -p CooperativeBankDemo -e "UPDATE Account SET Balance = Balance WHERE 1 = 0;"
```

## Operation requirements

Approval requires a linked guarantor and a manager from the application's branch.
Review can also reject a pending application. Disbursement requires approval and an
active account held by the applicant. Repayment requires generated installments.

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

## Multi-bank sample data

New demo databases contain Sahyog Cooperative Bank (three branches) and Pragati
Cooperative Bank (Mumbai Central, accounts 4001 Savings and 4002 Current).
Seed transactions 27 and 28 are successful inter-bank transfers in opposite
directions; 29 is pending and 30 failed. Pending/failed examples do not move balances.

An update of an existing demo refreshes procedures but does not append or
reload seed records. For the complete new dataset without resetting existing work:

```powershell
python demo-app/setup_demo.py --name CooperativeBankMultiBankDemo
python demo-app/server.py --database CooperativeBankMultiBankDemo --port 8081
```

Open http://127.0.0.1:8081 for this separate demo.

All participating bank accounts are stored in this one database; there is no
external payment-network connection. After reinstalling procedures, reapply the
restricted-user grants to the database you use for the presentation.

## Approval and disbursement are separate stages

ReviewLoan approves or rejects the application in LoanApplication. Approval alone
does not create a Loan or credit funds: the payout account, interest rate, and tenure
are supplied in DisburseLoan. After disbursement, inspect Loan and Account, then
run GenerateInstallments with the returned LoanID. The Next button carries the
application/loan identifier into the next form without submitting it automatically.

Repayment requires an active Savings/Current payout account and preserves its
minimum balance. Application and repayment amounts must contain whole cents.
Loan procedures own their transactions and reject calls inside another active
transaction without committing or rolling back the caller's work.
