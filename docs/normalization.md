# Normalization and Functional Dependency Analysis

This document explains the relational design of the Multi-Branch Cooperative Bank
Management System and compares the normalized logical model with the implemented
schema in [01_schema.sql](../database/01_schema.sql). The target is Boyce-Codd Normal
Form (BCNF) where applicable. The physical schema includes deliberate redundancy
for integrity enforcement; it should not be described as entirely in BCNF.

## 1. Scope and assumptions

The analysis uses the following business rules:

- Multiple banks may be registered, and each bank operates multiple branches. IFSC uniquely identifies a branch.
- Each employee belongs to one branch. Manager and Clerk are disjoint, partial
  specializations of Employee.
- PAN uniquely identifies a customer within Customer and a guarantor within
  Guarantor. These are separate relations; the schema does not enforce uniqueness
  of PAN across both tables.
- An account belongs to one branch and has one account type. A customer can hold
  multiple accounts, and an account can have multiple holders.
- A nominee is identified within its account by NomineeNo; that number is not a
  global identifier.
- Each transaction has a unique TransactionID and a unique RequestID. A transfer
  has source and destination accounts recorded in TransferDetails.
- An application can have multiple guarantors, and a guarantor can support
  multiple applications. An application produces at most one loan.
- An installment number is unique within its loan. A repayment can cover multiple
  installments, and an installment can receive multiple repayments.
- Names, addresses, phone numbers, customer email addresses, loan types, and
  interest rates are not assumed to be unique.

Dependencies describe all valid database states under these rules, rather than
coincidences in the sample data. A foreign key alone does not make its referencing
column unique or a determinant of every attribute in the referencing relation.

## 2. Notation and normal forms

`X → Y` means that any two rows agreeing on X must agree on Y. X and Y may each
contain multiple attributes. A candidate key is a minimal set of attributes that
determines the entire row; a superkey may contain unnecessary additional attributes.
A prime attribute belongs to at least one candidate key.

| Form | Requirement |
| --- | --- |
| 1NF | Each attribute contains one value from its domain; no repeating groups or nested lists. |
| 2NF | In 1NF, with no non-prime attribute dependent on a proper subset of any candidate key. |
| 3NF | For every non-trivial FD X → A, X is a superkey or A is prime. |
| BCNF | For every non-trivial FD X → Y, X is a superkey. |

Classical normal-form theory assumes relations without SQL NULLs. Optional SQL
attributes are therefore discussed separately. A nullable UNIQUE column is not an
unconditional candidate key: MySQL permits multiple NULL values.

## 3. Illustrative unnormalized design

The following is a teaching starting point, not a claim that this structure was
previously implemented. It combines independent groups into one bank record:

```text
BankRecord(
    BankID, BankName,
    Branches[{BranchID, IFSC, BranchName, Address,
        Employees[{EmployeeID, EmployeeName, Role, Phone, Email}],
        Accounts[{AccountNo, AccountType, Balance, Status, OpenedOn,
            Holders[{CustomerID, CustomerName, PAN, Phone, Email, Address}],
            Nominees[{NomineeNo, NomineeName, Relationship, DateOfBirth, Phone, Address}],
            Transactions[{TransactionID, TransactionDate, Type, Amount, RequestID}]
        }],
        Applications[{ApplicationID, CustomerID, RequestedAmount, Status,
            Guarantors[{GuarantorID, GuarantorName, PAN}],
            Loan{LoanID, SanctionAmount, InterestRate, TenureMonths,
                Installments[{InstallmentNo, DueDate, PrincipalDue, InterestDue}],
                Repayments[{PaymentID, TransactionID, Amount,
                    Allocations[{InstallmentID, AllocatedAmount}]}]
            }
        }]
    }]
)
```

This is not in 1NF because it contains repeating groups and nested records.
It also creates the following anomalies if flattened into duplicated records:

| Anomaly | Example |
| --- | --- |
| Update | A branch address appears in many account rows; changing only some rows produces conflicting addresses. |
| Insertion | A branch cannot be recorded independently if a flattened record requires an account and customer. |
| Deletion | Deleting the last account record for a branch could also remove the only stored branch details. |
| Redundancy | A joint account repeats its balance for each holder, and a guarantor's contact details repeat for every application. |

## 4. Conversion to 1NF

Represent each repeating group by separate rows and use identifiers to associate
the rows. In particular, do not store comma-separated account holders, guarantors,
or nominees in a base-table column.

For illustration, a flattened account-holder record could be:

```text
AccountHolderFlat(
    CustomerID, AccountNo,
    CustomerName, PAN, CustomerPhone, CustomerAddress,
    BranchID, IFSC, BranchName, BranchAddress,
    AccountType, Balance, Status, OpenedOn
)
Candidate key: (CustomerID, AccountNo)
```

Every field is now scalar, but customer details and account details still repeat.
Other repeating groups must be flattened separately; combining every holder,
nominee, and transaction into a single table would multiply unrelated rows.
An address remains one value in this project's chosen domain; splitting it into
street/city/postcode is not required merely to claim 1NF.

## 5. Conversion to 2NF

In AccountHolderFlat, the dependencies include:

```text
CustomerID → CustomerName, PAN, CustomerPhone, CustomerAddress
AccountNo  → BranchID, IFSC, BranchName, BranchAddress,
             AccountType, Balance, Status, OpenedOn
```

Both determinants are proper subsets of the composite key. Decompose into:

```text
Customer(CustomerID, CustomerName, PAN, Phone, Email, Address)
AccountWithBranch(AccountNo, BranchID, IFSC, BranchName, BranchAddress,
                  AccountType, Balance, Status, OpenedOn)
AccountHolder(CustomerID, AccountNo)
```

Similarly, keep application details outside ApplicationGuarantor and keep
guarantor details in Guarantor. Store nominee details under the complete key
`(AccountNo, NomineeNo)`; neither component alone identifies a nominee.

These decompositions remove the illustrated partial dependencies. Merely adding
an auto-increment ID would not remove dependencies associated with other candidate
keys or with the underlying business facts.

## 6. Conversion to 3NF

AccountWithBranch still contains transitive dependencies:

```text
AccountNo → BranchID
BranchID  → IFSC, BranchName, BranchAddress, BankID
BankID    → BankName
```

Store the branch and bank facts separately:

```text
Bank(BankID, BankName)
Branch(BranchID, BankID, IFSC, BranchName, Address)
Account(AccountNo, BranchID, AccountType, Balance, Status, OpenedOn)
```

Apply the same principle elsewhere:

- Employee stores BranchID, rather than repeating branch names and addresses.
- LoanApplication references Customer instead of copying applicant contact data.
- ApplicationGuarantor links applications and guarantors without copying either
  entity's descriptive attributes.
- LoanInstallment references Loan instead of repeating its sanction amount,
  interest rate, or tenure on every installment.
- TransferDetails references accounts instead of copying their branch/customer data.

Account subtypes are separated into SavingsAccount, CurrentAccount, and FixedDeposit
so that type-specific terms are stored only where they apply. This is also an EER
specialization mapping decision; normalization alone does not require this exact
choice of subtype tables.

## 7. Keys and principal dependencies in the implemented tables

In this table, “remaining attributes” means every other column of that relation.
The constant discriminator fields and other qualifications are analyzed in Section 8.

| Relation | Candidate keys / SQL qualifications | Principal functional dependencies |
| --- | --- | --- |
| Bank | BankID | BankID → BankName |
| Branch | BranchID; IFSC | Each candidate key → remaining attributes |
| Employee | EmployeeID; Email is UNIQUE but nullable | EmployeeID → remaining attributes; a supplied non-NULL Email identifies at most one employee |
| Manager | EmployeeID | EmployeeID → EmployeeRole; EmployeeRole is fixed to MANAGER |
| Clerk | EmployeeID | EmployeeID → EmployeeRole; EmployeeRole is fixed to CLERK |
| Customer | CustomerID; PAN | Each candidate key → remaining attributes |
| Account | AccountNo | AccountNo → BranchID, AccountType, Balance, Status, OpenedOn |
| AccountHolder | (CustomerID, AccountNo) | No non-trivial FDs beyond key dependencies in this two-column relation |
| Nominee | (AccountNo, NomineeNo) | Complete composite key → NomineeName, Relationship, DateOfBirth, Phone, Address |
| SavingsAccount | AccountNo | AccountNo → AccountType, InterestRate, MinimumBalance |
| CurrentAccount | AccountNo | AccountNo → AccountType, MinimumBalance |
| FixedDeposit | AccountNo | AccountNo → AccountType, Principal, InterestRate, StartDate, MaturityDate |
| BankTransaction | TransactionID; RequestID | Each candidate key → remaining attributes |
| TransferDetails | TransactionID | TransactionID → TransactionType, FromAccountNo, ToAccountNo |
| LoanApplication | ApplicationID | ApplicationID → remaining attributes; ReviewedBy → BranchID for reviewed applications under the same-branch rule |
| Guarantor | GuarantorID; PAN | Each candidate key → remaining attributes |
| ApplicationGuarantor | (ApplicationID, GuarantorID) | No non-trivial FDs beyond key dependencies in this two-column relation |
| Loan | LoanID; ApplicationID; DisbursementTransactionID is UNIQUE but nullable | LoanID and ApplicationID each → remaining attributes; a non-NULL disbursement reference identifies at most one loan |
| LoanInstallment | InstallmentID; (LoanID, InstallmentNo) | Each candidate key → remaining attributes |
| Repayment | PaymentID; TransactionID | Each candidate key → remaining attributes |
| PaymentAllocation | (PaymentID, InstallmentID) | Complete key → AllocatedAmount, LoanID; PaymentID → LoanID; InstallmentID → LoanID |

The extra SQL UNIQUE constraints `(AccountNo, AccountType)`,
`(EmployeeID, EmployeeRole)`, `(ApplicationID, Status)`, `(InstallmentID, LoanID)`,
and the wider transaction reference tuples are superkeys, not additional minimal
candidate keys. They support composite foreign keys that enforce matching values.

## 8. BCNF assessment and deliberate implementation redundancy

### 8.1 Logical relations that satisfy BCNF

Under the stated business dependencies, Bank, Branch, Customer, Account,
AccountHolder, Nominee, BankTransaction, Guarantor, ApplicationGuarantor, and
LoanInstallment satisfy BCNF: every identified non-trivial determinant is a superkey.
Employee's optional Email needs the SQL NULL qualification described above; its
non-NULL identifying values do not introduce a non-key determinant.

The subtype and transaction-extension logical relations also satisfy BCNF when
their fixed implementation discriminators are omitted. Repayment's Amount is
determined by TransactionID, which is itself a candidate key of Repayment; its
agreement with BankTransaction.Amount is a cross-table consistency requirement,
not a non-key dependency within Repayment.

### 8.2 Fixed discriminator columns

The physical schema repeats fixed values to make composite foreign keys enforce
subtype and transaction eligibility:

- Manager.EmployeeRole and Clerk.EmployeeRole.
- AccountType in SavingsAccount, CurrentAccount, and FixedDeposit.
- TransferDetails.TransactionType.
- Loan.ApplicationStatus.
- Repayment.TransactionType and Repayment.TransactionStatus.

In strict FD notation, a fixed value gives a dependency such as
`∅ → EmployeeRole` in Manager. The empty determinant is not generally a superkey,
so these physical relations are not strictly BCNF under that treatment. Their
logical projections without the constant columns avoid this issue. The implemented
columns are retained as constraint witnesses rather than independent business facts.

Loan's disbursement type/status fields are conditionally fixed: both are NULL before
disbursement and LOAN_DISBURSEMENT/SUCCESS afterward. These should not be described
as unconditional constants. The composite reference also repeats the payout account
and amount from the referenced transaction to enforce their equality.

### 8.3 PaymentAllocation: a genuine partial dependency

The physical relation is:

```text
PaymentAllocation(PaymentID, InstallmentID, LoanID, AllocatedAmount)
Key: (PaymentID, InstallmentID)

PaymentID     → LoanID
InstallmentID → LoanID
```

Every payment belongs to one loan, and every installment belongs to one loan.
Neither PaymentID nor InstallmentID uniquely identifies an allocation. LoanID is
therefore a non-prime attribute dependent on a proper subset of the key. This table
is in 1NF but not 2NF, and consequently not 3NF or BCNF.

The normalized alternative is:

```text
PaymentAllocation(PaymentID, InstallmentID, AllocatedAmount)
```

LoanID is then obtained through Repayment or LoanInstallment. Matching their loans
would require a separate enforcement mechanism. The current implementation instead
retains LoanID and uses two composite foreign keys to reject allocations connecting
different loans. This is an explicit tradeoff between normalization and declarative
integrity enforcement, not a BCNF decomposition.

### 8.4 LoanApplication: branch and reviewer overlap

An employee belongs to one branch, and a manager may review only that branch's
applications. Thus, among reviewed applications:

```text
ReviewedBy → BranchID
```

ReviewedBy is not a candidate key: the same manager may review many applications.
BranchID is non-prime. The reviewed projection therefore has a 3NF/BCNF violation.
The nullable pending-review state means this must be treated as a conditional
business dependency rather than an unconditional classical FD over SQL NULLs.

BranchID must also exist before a reviewer is assigned. The implementation retains
both the receiving branch and the eventual reviewer, and checks agreement through
triggers. A stricter normalized redesign could represent pending and reviewed
application states separately and derive the reviewed branch through Employee,
but would need to preserve the original receiving-branch semantics. Such a redesign
has not been implemented and is not assumed in this document.

## 9. Lossless decomposition and dependency preservation

For a binary decomposition of R into R1 and R2, the classical FD-based lossless-join
test is that their intersection determines R1 or R2. For example:

```text
AccountWithBranch → Account + Branch
Intersection: BranchID
BranchID → all attributes of Branch
```

The decomposition is lossless for valid account/branch records. Similarly,
CustomerID determines Customer when extracting customer facts from AccountHolderFlat.
The remaining AccountHolder relation preserves the actual customer/account pairings;
joining Customer and Account without it would create spurious ownership combinations.

Dependencies such as `BranchID → BranchName` and `CustomerID → PAN` can be checked
within their own tables after decomposition. Referential constraints ensure that
the identifiers used by relationship tables refer to existing entities.

This is not a claim that all 21 tables arise from a single universal relation by
FD decomposition. Independent repeating groups and optional relationships are
modeled separately. For example, inner-joining every table would incorrectly omit
customers without loans or accounts without transactions.

Some dependencies and workflow conditions span tables. The retained composite
foreign-key witnesses in Section 8 are one way to enforce those conditions locally;
removing them for a stricter normalized representation would require replacement
checks, not merely deleting columns.

## 10. Derived data and integrity rules

The following design choices avoid unnecessary stored totals:

- A joint account's holder names are assembled by direct reporting queries.
- Installment paid amounts are derived from PaymentAllocation.
- Scheduled outstanding and overdue amounts are computed by loan direct reporting queries.
- Branch account counts, balances, and loan totals are aggregated by report queries.
- Account statements calculate running balances from successful financial events.

Account.Balance is intentionally stored as an operational summary of the ledger.
Procedures must update it atomically with successful transactions. Its redundancy
is an aggregate consistency concern across relations, not by itself a non-key FD
inside Account. EMI principal/interest amounts are stored schedule obligations;
recording them preserves the agreed schedule and rounding decisions.

Normalization does not prove constraints such as a nonnegative balance, sufficient
funds, at least one holder, guarantor availability at approval, sanction not exceeding
the request, or allocation totals equaling a payment. These require CHECK constraints,
foreign keys, triggers, procedures, or restricted access as appropriate. Their
implementation and completeness must be evaluated separately from normal forms.

## 11. Conclusion

The design separates entity facts and many-to-many relationships to remove the
major insertion, update, and deletion anomalies of the illustrative unnormalized
record. Most core logical relations satisfy BCNF under the stated dependencies.
The implemented schema deliberately retains discriminator/reference witnesses,
LoanID in PaymentAllocation, and overlapping reviewer/branch information.
These exceptions must accompany any claim that the project is normalized up to
BCNF where applicable; the entire physical schema is not strictly BCNF.
