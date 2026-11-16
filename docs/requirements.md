# Requirements Specification

**Project:** Multi-Branch Cooperative Bank Management System

**Course:** DBIS Lab, CS257

**Team:** Eklavya (250001028), Tanush Bansal (250001071),
Chetan Yogbharti (250001023), Parth Kalia (250001054)

## 1. Purpose and sources

The system maintains a single relational database for a cooperative bank operating
through multiple branches. It supports customer and account records, branch and
employee records, financial transactions, a loan lifecycle, and reporting.
The project demonstrates database modeling, normalization, integrity constraints,
transaction management, concurrency control, indexing, and query optimization.

This specification is based on the [project proposal](DBIS_proposal.pdf),
[problem statement](DBIS_problem_statement.pdf), and
[ER diagram](er/ER_Diagram.pdf). Implementation references describe how requirements
map to the repository; they do not imply that every requirement is already complete.
Normalization and its implementation exceptions are documented separately in
[normalization.md](normalization.md).

## 2. Scope

The project covers five functional modules:

1. Customer and account management.
2. Branch and employee management.
3. Transaction processing.
4. Loan management.
5. Reporting and administration.

Banks and branches share one database. Transfers may connect accounts at the same
branch, different branches of one bank, or different banks registered in the system.
All use one atomic database transaction. Integration with external payment networks
and settlement across independently operated databases is outside scope. Account
numbers are globally unique across the modeled banks.

The presentation interface is a local demonstration application with Banking and
Loans sections and refreshable database records. A complete customer-facing banking
portal, payment-network integration, regulatory certification, authentication system,
and automated fixed-deposit maturity/interest-crediting service are not deliverables
of this project. SQL scripts may demonstrate administrative CRUD without dedicated
frontend screens.

## 3. Users and responsibilities

| Actor | Responsibilities |
| --- | --- |
| Database administrator | Build the schema, manage database privileges, load demonstration data, and inspect integrity and performance results. |
| Banking operator | Open accounts and perform supported deposits, withdrawals, and transfers through controlled operations. |
| Branch manager | Review applications received by the manager's own branch and record approval or rejection. |
| Presenter / evaluator | Run example workflows, refresh records, inspect reports, and reproduce experiments. |

These actors describe responsibilities. Employee role records are business data;
they do not automatically create MySQL users or authenticate browser users. The local
demo's ability to enter a manager ID is not an authentication mechanism.

## 4. Functional requirements

### 4.1 Customer and account management

| ID | Requirement |
| --- | --- |
| CA-01 | Record and retrieve customer name, PAN, phone, email, and address. Support profile updates and demonstrate basic CRUD subject to referential constraints. |
| CA-02 | Require a unique, valid PAN for each customer. Customer names, phone numbers, and email addresses need not be unique. |
| CA-03 | Support Savings, Current, and Fixed Deposit accounts at existing branches. A customer may hold accounts at multiple branches. |
| CA-04 | Support joint accounts through a many-to-many customer/account relationship. Each account must retain at least one holder. |
| CA-05 | Create an account, its matching subtype, and its first holder atomically. Opening funds must be recorded in the transaction ledger when positive. |
| CA-06 | Store savings interest rate and minimum balance, current-account minimum balance, and FD principal, interest rate, start date, and maturity date. |
| CA-07 | Support ACTIVE, FROZEN, and CLOSED account states. Ordinary fund movements require active accounts. Closed records should remain available for historical inspection. |
| CA-08 | Store account-dependent nominees with name, relationship, date of birth, and optional contact details. Identify each nominee by (AccountNo, NomineeNo). |
| CA-09 | Demonstrate record deletion only where permitted by relationships and retention rules; referenced financial history must not be silently removed. |

### 4.2 Branch and employee management

| ID | Requirement |
| --- | --- |
| BE-01 | Store bank and branch records, including branch name, IFSC, and address. Every branch belongs to an existing bank. |
| BE-02 | Enforce unique, correctly formatted IFSC values. Demonstrate branch creation, retrieval, update, and permitted deletion. |
| BE-03 | Store employee name, contact information, and branch assignment. Every employee belongs to one existing branch. |
| BE-04 | Represent Manager and Clerk as disjoint, partial specializations: an employee may be neither, but may not be both. |
| BE-05 | Expose branch staffing and account/loan information through administrative queries or reporting views. |

### 4.3 Transaction processing

| ID | Requirement |
| --- | --- |
| TP-01 | Deposit a positive amount into an eligible Savings or Current account and increase its balance by that amount. |
| TP-02 | Withdraw a positive amount from an eligible account while preserving its minimum balance. |
| TP-03 | Transfer a positive amount between distinct eligible accounts, within a branch, across branches, or across registered banks. Debit and credit must commit together. |
| TP-04 | Store transaction ID, timestamp, type, amount, channel, status, and unique request ID. Distinguish PENDING, SUCCESS, and FAILED records. |
| TP-05 | Record exactly one TransferDetails row for a transfer, with its source and destination. Other transaction types must not have transfer details. |
| TP-06 | For a non-transfer transaction, identify its affected account in BankTransaction. A transfer uses its detail row instead of that account field. |
| TP-07 | Reject invalid account references, inactive accounts, unsupported FD operations, insufficient funds, and invalid monetary amounts. Roll back partial changes. |
| TP-08 | Reject reuse of a transaction RequestID without moving funds a second time. This is duplicate rejection, not a requirement to return a cached success response. |
| TP-09 | Preserve correct balances and ledger records under concurrent operations on the same accounts. |

### 4.4 Loan management

| ID | Requirement |
| --- | --- |
| LM-01 | Submit a loan application for an existing customer and receiving branch, recording date, loan type, requested amount, purpose, and PENDING status. |
| LM-02 | Record guarantor identity/contact data and support many-to-many application/guarantor links. PAN must be valid and unique within Guarantor. |
| LM-03 | Allow a manager of the receiving branch to approve or reject a pending application. Record reviewer and decision date together. |
| LM-04 | Require at least one linked guarantor for approval and prevent later removal of the last guarantor while the application remains approved. |
| LM-05 | Create at most one loan for an approved application. SanctionAmount must not exceed RequestedAmount. |
| LM-06 | Disburse to an active account held by the applicant. Credit the account and record the loan and successful disbursement transaction atomically. |
| LM-07 | Link a disbursed loan to a successful LOAN_DISBURSEMENT transaction with matching payout account and sanction amount. |
| LM-08 | Generate a monthly EMI schedule using the sanctioned amount, annual interest rate, and tenure. Support zero interest and adjust the final principal component for rounding. Reject duplicate schedule generation. |
| LM-09 | Record repayments against eligible funded loans with generated unpaid installments. Reject nonpositive payments, payments above scheduled outstanding, and insufficient funds. |
| LM-10 | Debit the payment account and create a successful LOAN_REPAYMENT transaction, matching repayment record, and installment allocations atomically. |
| LM-11 | Allocate repayment to the oldest unpaid installments first. Every allocation must reference an installment of the same loan, and allocations must sum to the repayment amount without overpaying an installment. |
| LM-12 | Close a loan when its generated schedule is fully repaid. Retain loan, installment, repayment, and transaction records. |
| LM-13 | Represent SANCTIONED, ACTIVE, CLOSED, and DEFAULTED loan states. A sanctioned, undisbursed loan has no disbursement reference; funded states require one. Automatic default classification is outside the current workflow. |
| LM-14 | Preserve chronology: decision not before application, sanction not before approval, funding not before sanction, installments after funding day (or sanction when prepared before funding), and repayments not before funding. |

### 4.5 Reporting and administration

| ID | Requirement |
| --- | --- |
| RA-01 | Provide account overviews with branch, account type, terms, holder information, balance, and status. |
| RA-02 | Provide branch-wise account counts, balances, and staffing summaries. |
| RA-03 | Provide transaction histories identifying transfer endpoints, source/destination banks, and INTRA_BRANCH, INTER_BRANCH, or INTER_BANK scope. |
| RA-04 | Provide account statements with debit, credit, and running balance, plus customer statements across held accounts. Only successful events affect balances. |
| RA-05 | Provide loan portfolios showing schedule totals, repayments, scheduled outstanding, overdue amounts, and next unpaid due dates. |
| RA-06 | Provide branch-wise loan summaries and pending-application queues. |
| RA-07 | Provide an integrity audit for transfer transactions missing their required details, including administrative imports. |

## 5. Data and integrity requirements

The schema contains 21 base tables:

| Area | Relations |
| --- | --- |
| Organization | Bank, Branch, Employee, Manager, Clerk |
| Customers and accounts | Customer, Account, AccountHolder, Nominee, SavingsAccount, CurrentAccount, FixedDeposit |
| Financial events | BankTransaction, TransferDetails |
| Loans | LoanApplication, Guarantor, ApplicationGuarantor, Loan, LoanInstallment, Repayment, PaymentAllocation |

The following rules apply across modules:

- Primary keys must uniquely identify rows. Foreign keys must reject references
  to missing parents. Relationship tables must reject duplicate links.
- Account specialization is total and disjoint: exactly one matching subtype per
  account. Account type cannot change after creation.
- A nominee number is unique within its account, and an installment number is
  unique within its loan.
- PAN has five uppercase letters, four digits, and one uppercase letter. IFSC has
  four uppercase letters, zero, and six uppercase alphanumeric characters.
- Amounts use exact decimal storage. Financial inputs must fit the permitted
  precision; operations must not silently accept fractional cents as intended funds.
- Account balances and minimum balances cannot be negative. Fund movements must
  preserve applicable minimum-balance requirements.
- Requested amounts, sanction amounts, transaction amounts, repayment amounts, and
  allocations must be positive. Interest rates cannot be negative; tenure must be positive.
- FD principal must be positive, and maturity must follow the start date.
- PENDING applications have no reviewer or decision date; decided applications
  have both. Approval's designated guarantor must be one of its actual links.
- Successful ledger movements must reconcile with stored account balances.
  Pending and failed records must not change balances.

Some requirements are enforced through procedures and restricted permissions,
rather than arbitrary administrator DML. For example, opening an account through
the controlled interface establishes its initial holder and subtype together.
Acceptance testing must distinguish these access paths and identify any remaining
unprotected cases; this specification does not assert that all listed invariants
are already enforced against every possible table write.

## 6. Non-functional requirements

| ID | Requirement and acceptance evidence |
| --- | --- |
| NF-01 Correctness | Successful operations preserve account/ledger agreement and relational integrity; rejected operations leave no partial financial changes. |
| NF-02 Atomicity and durability | Related writes execute in an InnoDB transaction and persist after commit. Exceptions roll back the operation. |
| NF-03 Isolation | Concurrent deposits, withdrawals, and transfers must not lose updates or overspend available funds. Demonstrate locking and explain deadlock handling. |
| NF-04 Access control | Application credentials should receive the reads and procedure execution needed for supported operations, with no unrestricted direct financial-table writes. Administrative imports are a separate access path. |
| NF-05 Credential handling | The demo must keep database credentials server-side and avoid repeated password prompts during a presentation session. |
| NF-06 Usability | Use separate Banking and Loans sections, labeled forms, visible validation errors, and a refreshable table explorer. Missing installed procedures must be visibly unavailable. |
| NF-07 Reproducibility | Supply ordered build instructions, representative sample data, executable tests, and reproducible experiments. Destructive resets must be explicit. |
| NF-08 Performance evaluation | Measure query behavior on a documented dataset before and after indexing and query rewrites. Record timings and execution plans; no arbitrary response-time guarantee is assumed. |
| NF-09 Maintainability | Keep schema, triggers, procedures, reporting, indexes, experiments, and documentation organized and readable. Document deliberate normalization exceptions. |

The target database is MySQL 8.0.16 or later with enforced CHECK constraints and
InnoDB transactions. The local demo requires Python 3.9+, the MySQL CLI, and a modern
browser; its frontend uses HTML, CSS, and JavaScript. The demo uses a separate
presentation database and listens on the local loopback interface.

## 7. Academic deliverables

| ID | Required deliverable |
| --- | --- |
| AD-01 | Requirements specification defining scope, functional expectations, and business rules. |
| AD-02 | An ER/EER diagram showing specialization, many-to-many relationships, and account-dependent nominees as weak entities. |
| AD-03 | Illustrative unnormalized design, functional dependencies, candidate keys, normalization through BCNF where applicable, and justification of exceptions. |
| AD-04 | DDL with constraints, representative sample data, and basic CRUD demonstrations for customers, accounts, and branches. |
| AD-05 | Working banking and loan workflows, reporting queries/views, and evidence of transactional integrity. |
| AD-06 | A documented concurrency anomaly and its resolution through locking or isolation levels, with actual execution evidence. |
| AD-07 | An indexing experiment explaining relevant B+ Tree-based indexes and measured before/after performance. |
| AD-08 | Query optimization case studies with equivalent query rewrites, execution-plan analysis, and measured results. |
| AD-09 | A final report covering requirements, design, normalization, implementation, testing, concurrency, indexing, optimization, and limitations. |

## 8. Acceptance scenarios

| Scenario | Expected outcome |
| --- | --- |
| Open each account type | Account, correct subtype, first holder, and positive opening-fund event are committed together. Invalid input leaves none of those new records. |
| Open a joint account / add a holder | Multiple distinct customers may hold one account; duplicate links are rejected. |
| Deposit, withdraw, and transfer | Exact expected balance changes and matching successful financial events appear after refresh. Transfer details contain the correct endpoints. |
| Reject an invalid operation | Frozen/closed account use, minimum-balance violation, duplicate request ID, or invalid input produces a clear error and no partial movement. |
| Execute concurrent withdrawals | Committed withdrawals cannot exceed available funds or violate the minimum balance; ledger and balances agree. |
| Complete a loan lifecycle | Apply, link a guarantor, approve through the correct manager, disburse, generate installments, repay partially, and repay the remainder to close the loan. |
| Reject invalid loan steps | Wrong-branch reviewer, missing approval guarantor, rejected application disbursement, duplicate schedule, or excessive repayment is rejected. |
| Check repayment allocation | Every allocation belongs to the payment's loan; totals equal the payment and do not exceed installment obligations. |
| Inspect statements and summaries | Statement ending balances agree with accounts; branch aggregates agree with base tables; loan totals agree with schedules and allocations. |
| Run experiments | Reproduce the lost update and its resolution, then reproduce indexing and query-optimization measurements with recorded results. |

The scenarios describe completion criteria, not a record of tests executed while
writing this document. Detailed demo commands are in [demo-app/README.md](../demo-app/README.md).

## 9. Implementation and verification evidence

| Requirements | Principal implementation location |
| --- | --- |
| Entity and domain integrity | `database/01_schema.sql`, `database/02_constraints_triggers.sql` |
| Account opening | `database/02_account_opening.sql` |
| Loan chronology | `database/02_loan_dates.sql` |
| Representative data | `database/03_seed_data.sql` |
| Financial operations | `database/04_transactions.sql` |
| Loan workflow | `database/05_loans.sql`; demo integration in `demo-app/install_loans.py` |
| Reporting | `database/06_views.sql`, `tests/report_views_checks.sql` |
| Indexing | `database/07_indexes.sql` and [timings and plans](../experiments/indexing/results.txt) |
| Query optimization | [Original queries, rewrites, timings, and plans](../experiments/query_optimization/results.txt) |
| Concurrency demonstration | `experiments/concurrency/` |
| Presentation interface | `demo-app/` |
| Automated verification | `tests/`, `demo-app/test_server.py`, `demo-app/check_integration.py` |

The demo installs the source loan procedures and adds a guarantor-linking
helper. Its update mode refreshes procedures, reports, and indexes while
retaining table data.

The [CRUD walkthrough](report/crud_demo.sql) demonstrates customer and branch
deletion and account closure. The [restricted demo role](../scripts/demo_access.sql)
allows table and report reads and procedure calls. The demo user cannot directly
write to financial tables. Privileged administrative writes can bypass procedural
checks, so the smoke test checks for ledger and relationship violations.

The [final report](report/final_report.md) summarizes the implemented design,
verification, and measured results.
