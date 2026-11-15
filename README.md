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
      02_constraints_triggers.sql   Additional constraints and triggers
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
