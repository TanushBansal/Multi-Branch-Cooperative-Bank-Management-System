# Concurrency Experiment: Lost Update and Its Resolution

This experiment demonstrates a concurrency anomaly (the lost update) on a bank account, and then resolves it in two ways: with a row lock and with the SERIALIZABLE isolation level. It satisfies the end-evaluation deliverable "documented concurrency anomaly and its resolution via isolation levels or locking".

The production procedures in `database/04_transactions.sql` are not modified. The experiment adds two demonstration procedures, which differ in exactly one clause, and three dedicated demonstration accounts.

## Files

    00_setup.sql             Creates WithdrawUnsafe, WithdrawLocked, ConcurrencyDemoReset and opens the three accounts
    10_lost_update_A.sql     Scenario 1, session A (the anomaly)
    10_lost_update_B.sql     Scenario 1, session B
    20_row_lock_A.sql        Scenario 2, session A (resolution with FOR UPDATE)
    20_row_lock_B.sql        Scenario 2, session B
    30_serializable_A.sql    Scenario 3, session A (resolution with SERIALIZABLE)
    30_serializable_B.sql    Scenario 3, session B
    99_verify.sql            Compares stored balance with the ledger for the demonstration accounts

## Preparation

Build the database first (files 01 to 04 and 06), then run the setup once. From the repository root:

    mysql -u root -p
    mysql> SOURCE experiments/concurrency/00_setup.sql;

The result shows three accounts, 9100000001 to 9100000003, each with a balance of 10000.00. Setup can be rerun at any time, and it also restores the accounts to 10000.00.

## How to run a scenario

Each scenario needs two sessions open at the same time. Open two terminal windows, start `mysql -u root -p` in each from the repository root, and call them A and B. (Two separate terminals are safer than two tabs of one Workbench window, because each terminal is guaranteed to be an independent session.)

Type the `SOURCE` command for session B in terminal B but do not press Enter yet. Then press Enter in terminal A, and within 15 seconds press Enter in terminal B. Session A deliberately waits 15 seconds between reading and writing the balance, which simulates processing time and gives B a window to run.

After each scenario, run `SOURCE experiments/concurrency/99_verify.sql;` in either terminal.

## Scenario 1: the anomaly

    A:  SOURCE experiments/concurrency/10_lost_update_A.sql;
    B:  SOURCE experiments/concurrency/10_lost_update_B.sql;

Session A withdraws 1000.00 and session B withdraws 2000.00 from account 9100000001, which holds 10000.00. Both sessions read 10000.00. B writes 8000.00 and commits straight away. A then wakes up and writes 9000.00, which is its stale read minus its own amount, so B's withdrawal is overwritten.

Expected outcome:

- Session A reports BalanceReadBySession 10000.00 and BalanceWrittenBySession 9000.00.
- Session B reports 10000.00 and 8000.00.
- `99_verify.sql` shows a StoredBalance of 9000.00 but a LedgerBalance of 7000.00, so Difference is 2000.00. Both withdrawals are recorded as successful in the ledger, yet the account lost only one of them. The customer keeps 2000.00 that the ledger says was paid out.

This happens even at the default REPEATABLE READ isolation level, because the problem is not what each session can see. The update writes an absolute value computed from a stale read.

## Scenario 2: resolution with a row lock

    A:  SOURCE experiments/concurrency/20_row_lock_A.sql;
    B:  SOURCE experiments/concurrency/20_row_lock_B.sql;

The procedure WithdrawLocked is identical to WithdrawUnsafe except that the read is `SELECT ... FOR UPDATE`. Session A takes an exclusive lock on the account row and keeps it until COMMIT. Session B's read blocks, and its call does not return for about 15 seconds. When A commits, B reads the up-to-date balance.

Expected outcome:

- Session A reads 10000.00 and writes 9000.00.
- Session B, after waiting, reads 9000.00 and writes 7000.00.
- `99_verify.sql` shows StoredBalance 7000.00, LedgerBalance 7000.00 and Difference 0.00.

The production Withdraw procedure uses this technique, and the automated tests `test_concurrent_withdrawals_cannot_overspend` and `test_concurrent_deposits_have_no_lost_updates` in `tests/test_transactions.py` exercise it.

## Scenario 3: resolution with the SERIALIZABLE isolation level

    A:  SOURCE experiments/concurrency/30_serializable_A.sql;
    B:  SOURCE experiments/concurrency/30_serializable_B.sql;

This scenario reuses the unsafe procedure unchanged, but each session first runs `SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;`, which applies to the next transaction only. At this level InnoDB turns the plain read into a shared-locking read. Both sessions obtain a shared lock on the row, and then each needs an exclusive lock for its update, which the other's shared lock blocks. This is a deadlock. InnoDB detects it immediately and rolls back one session with error 1213.

Expected outcome:

- One session fails with `ERROR 1213 (40001): Deadlock found when trying to get lock; try restarting transaction`. Either session may be chosen as the victim.
- The other session commits.
- `99_verify.sql` shows Difference 0.00 for account 9100000003, and the failed withdrawal left no ledger row, because its whole transaction was rolled back.

The anomaly is therefore prevented, at the cost that one request fails and must be retried by the application. To show the retry, rerun the failed call with a new RequestID once the other has committed, for example `CALL WithdrawUnsafe(9100000003, 1000.00, 'cdemo-sr-retry', 0);`. The stored balance and the ledger will then both read 7000.00.

## Restoring the database

The anomaly in scenario 1 deliberately leaves account 9100000001 inconsistent with its ledger. Before the project is evaluated, restore it:

    CALL ConcurrencyDemoReset(9100000001);
    CALL ConcurrencyDemoReset(9100000002);
    CALL ConcurrencyDemoReset(9100000003);

Each call removes the demonstration withdrawals and sets the balance back to 10000.00, which matches the opening deposit still in the ledger.

## Text for the report

A lost update occurs when two transactions read the same value, both compute a new value from what they read, and the later write silently overwrites the earlier one. In the experiment, two concurrent withdrawals from the same account (1000.00 and 2000.00 from a balance of 10000.00) both read 10000.00. The second to write stored 9000.00, discarding the 2000.00 withdrawal, so the account balance disagreed with its transaction ledger by 2000.00. Two resolutions were demonstrated. Adding `FOR UPDATE` to the initial read makes the second transaction wait for the first to commit, after which it reads the current balance and produces the correct final balance of 7000.00. Running the same unmodified procedure at the SERIALIZABLE isolation level makes the database detect the conflict as a deadlock and roll one transaction back, preserving consistency, with the failed request retried by the application. The production Withdraw procedure applies the explicit locking approach.

## Points to remember for the viva

- A lost update is a violation of isolation (the I in ACID). Concurrent transactions must produce a result equivalent to some serial order, and here no serial order gives 9000.00.
- The default REPEATABLE READ level does not prevent this anomaly in this form, because the application writes a value derived from its earlier read.
- Locking read (`FOR UPDATE`) serializes access to the one contended row and keeps other work concurrent, so it is usually cheaper than raising the isolation level for everything.
- SERIALIZABLE gives the strongest guarantee but resolves the conflict by aborting a transaction, so callers must be ready to retry.
- An alternative fix is a single atomic statement, `UPDATE Account SET Balance = Balance - amount`, which does not depend on a prior read, but the withdrawal also needs to check the balance and minimum, which is why locking the row first is used.
- The transfer procedure locks the two accounts in ascending account number order, so that two opposite transfers cannot deadlock each other.
