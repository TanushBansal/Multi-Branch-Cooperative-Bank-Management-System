# Design and Implementation of a Multi-Branch Cooperative Bank Management System

**DBIS Lab (CS257) | Final Project Report**

| Team member | Roll number |
|---|---|
| Eklavya | 250001028 |
| Tanush Bansal | 250001071 |
| Chetan Yogbharti | 250001023 |
| Parth Kalia | 250001054 |

## 1. Problem and scope

A cooperative bank needs to operate across branches while keeping customer information, account balances, financial transactions and loan records consistent. This project implements a shared MySQL 8.0 database for five functional areas.

| Area | Implemented scope |
|---|---|
| Customer and account management | Customer profiles, joint ownership, nominees, and opening savings, current and fixed-deposit accounts |
| Branch and employee management | Branch identifiers, staff assignments, and manager and clerk roles |
| Transaction processing | Deposits, withdrawals, and same-branch, inter-branch and inter-bank transfers within the shared database |
| Loan management | Application, guarantor linkage, approval or rejection, funding, EMI schedules, repayment allocation and closure |
| Reporting | Account and customer statements, branch summaries, pending applications and loan portfolios |

The project scope and acceptance criteria are described in the [requirements specification](../requirements.md). The [proposal](../DBIS_proposal.pdf) defines the evaluation objectives.

## 2. ER model and relational design

The [ER diagram](../er/ER_Diagram.pdf) models one bank with multiple branches. An account belongs to one branch, and customers and accounts have a many-to-many relationship through AccountHolder. The account-opening routines create an account, its first holder and its matching subtype in one transaction. Manager and Clerk are disjoint employee subtypes, and an employee may belong to neither subtype.

Nominee is a weak entity. Its partial key is NomineeNo, which is unique within the owning account. The implemented primary key is (AccountNo, NomineeNo). Applications and guarantors have a many-to-many relationship through ApplicationGuarantor. A loan can have several installments, with (LoanID, InstallmentNo) as the natural key and InstallmentID as the surrogate identifier used in allocations.

## 3. Normalization

The [normalization analysis](../normalization.md) starts from a register with repeating groups for accounts, nominees, transactions, guarantors and installments. The decomposition represents each group at its own grain, separates customer and account details from the composite ownership key, and removes transitive dependencies such as AccountNo determining BranchID and BranchID determining IFSC and branch details.

The analysis identifies candidate keys and explains deliberate exceptions in the physical schema. For example, PaymentAllocation retains LoanID even though either linked parent determines it. Two composite foreign keys use that column to ensure a payment can only be allocated to installments of the same loan. The normalization document records this partial dependency and the conditional dependency between reviewer and branch on reviewed applications.

## 4. Database implementation and demonstration

The [schema](../../database/01_schema.sql) defines 21 base tables. The build adds sample data, 26 triggers, stored procedures, ten views and two explicit benchmark indexes. Primary, foreign and unique keys enforce identity and references. CHECK constraints guard domains and valid field combinations. Triggers enforce cross-record rules such as manager and branch agreement, approval with a linked guarantor, sanction amount within the request, and loan event chronology.

The [CRUD walkthrough](crud_demo.sql) creates, reads and updates a customer, a branch and a savings account. The account moves from ACTIVE to FROZEN to CLOSED. The script rolls the account work back to a savepoint, deletes the now-unreferenced customer and branch, and rolls back at the end. The demonstration run reported one deletion for each parent record.

The [reporting views](../../database/06_views.sql) include account and customer statements, branch account and staff summaries, loan portfolios, pending loan applications and a transfer audit. A successful transfer appears as a debit for the sender and a credit for the recipient. Pending and failed transactions remain visible in history and contribute zero to ledger balance.

## 5. Transaction integrity and concurrency

The [banking procedures](../../database/04_transactions.sql) commit ledger entries and balance changes together, or roll back the entire operation on failure. Withdrawal locks the account before checking funds. Transfer locks both account rows in ascending account-number order. Request identifiers are unique, so duplicate banking submissions cannot post the same movement twice.

The [two-session concurrency experiment](../../experiments/concurrency/README.md) started each fixture at 10,000.00. Sessions A and B attempted withdrawals of 1,000.00 and 2,000.00.

| Scenario | Outcome observed |
|---|---|
| Unlocked reads | Both sessions read 10,000.00. Both withdrawals posted, but A's later write left 9,000.00 stored against a 7,000.00 ledger balance. The mismatch was 2,000.00. |
| Row locking | B waited 12.77 seconds for A to commit, then read 9,000.00 and wrote 7,000.00. Both withdrawals were applied. |

The demo fixtures were reset after the experiment. The post-reset smoke test returned zero rows.

## 6. Loan workflow

The [loan routines](../../database/05_loans.sql) submit an application, record the receiving branch manager's decision, and fund an approved loan to an active account held by the applicant. Approval requires a linked guarantor. The demo exposes guarantor linkage as a separate operation.

Disbursement can create and fund a loan for an approved application or fund an existing sanction. Funding seeded loan 3 preserved its ID and terms and credited 30,000.00. When a schedule is generated after funding, due dates start one month after disbursement. The final principal installment absorbs rounding. Repayment posts a ledger debit, applies the payment to the oldest unpaid installments and closes the loan when the schedule is fully paid.

A loan test exposed a race in which two 3,000.00 payments succeeded despite only 5,000.00 being due. The final procedure locks the loan before reading the outstanding balance. The regression test verifies that only the first payment succeeds and that the second is rejected because it would exceed the remaining outstanding amount.

## 7. Indexing and query optimization

The experiments used the scratch database `CooperativeBank_perf_1f47ce75`, with 5,010 accounts and 300,024 transactions. Each version was warmed up once and timed five times with `EXPLAIN ANALYZE`. The table reports the median completion time of the root iterator. The [indexing transcript](../../experiments/indexing/results.txt) and [query optimization transcript](../../experiments/query_optimization/results.txt) contain the plans and samples.

| Experiment | Original median | Changed median | Execution plan evidence |
|---|---:|---:|---|
| Date range across all accounts | 120 ms | 2.58 ms | A table scan of 300,024 rows became an index range scan of 822 matching rows using `ix_transaction_date`. |
| Date range for one account | 0.146 ms | 0.0642 ms | The account index retrieved 60 rows before filtering. `ix_transaction_account_date` retrieved the six matching rows directly. |
| Accounts above their branch average | 10,770 ms | 12 ms | The correlated aggregate ran 5,010 times. The CTE computed three branch averages once. Both versions returned the same 2,409 account IDs. |
| Accounts with more than ten successful transactions | 627 ms | 584 ms | A grouped scan replaced 5,010 transaction lookups. Both versions returned the same 5,000 account IDs. The timing samples overlapped. |

The [index definitions](../../database/07_indexes.sql) target date predicates because PAN, account identifiers and the transaction account foreign key already had indexes. The two query rewrites were measured with the same indexes in place for both versions. The grouped transaction-count rewrite yielded a smaller measured improvement and still scanned all transaction rows. These results describe the seeded and synthetic workload used for the experiment.

## 8. Access control and verification

The [demo application](../../demo-app/README.md) uses a separate seeded schema. The [demo role](../../scripts/demo_access.sql) grants reads for the table and report explorer and procedure execution within the demo schema. Its financial operations go through stored procedures. In the restricted-user demonstration, a web deposit changed the account balance. A direct SQL UPDATE as the same user returned error 1142.

| Check | Recorded evidence |
|---|---|
| [Smoke test](../../tests/smoke_tests.sql) and [report assertions](../../tests/report_views_checks.sql) | Both returned empty sets after rebuilding the database. |
| [Loan integration tests](../../tests/test_loans.py) | Three tests passed on MySQL 8.0.46 against the final loan routines, covering seeded funding, duplicate operations, repayment allocation and concurrency. |
| [Demo unit tests](../../demo-app/test_server.py) | Five tests passed. |
| [Demo HTTP integration](../../demo-app/check_integration.py) | The run reported PASS for 12 operations, 21 tables, ten views, both indexes, reporting checks, data-preserving updates, rollback and token protection. |

## 9. Scope boundaries

The shared database now models multiple banks, with seeded Sahyog and Pragati branches. Transfers between their accounts commit atomically and appear as INTER_BANK in transaction history. This extends the original single-bank proposal; historical benchmark measurements above describe the earlier benchmark fixture. Fixed-deposit maturity and closure, external payment-network settlement and automatic loan default classification are outside the implemented workflows. Total account specialization is established by the account-opening procedures and checked by the smoke test. Privileged administrative writes can bypass some procedural invariants, so the demo account uses restricted grants for normal operation.
