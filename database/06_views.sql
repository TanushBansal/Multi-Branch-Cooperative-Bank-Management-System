USE CooperativeBank;

-- Administrative audit: transfers imported directly must include their details.
-- Applies to PENDING, SUCCESS, and FAILED records alike. An empty result is valid.
-- The application creates transfers atomically through the Transfer procedure.
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_transfer_integrity_violations AS
SELECT t.TransactionID, t.Status, t.RequestID
FROM BankTransaction t
WHERE t.TransactionType = 'TRANSFER'
  AND NOT EXISTS (
      SELECT 1 FROM TransferDetails d WHERE d.TransactionID = t.TransactionID
  );


-- ====================================================================
-- Reporting and administration views (Functional Module 5).
-- Branch-wise account summaries, account and customer statements,
-- transaction history, branch staffing and loan portfolios.
-- Read-only; safe to rerun (CREATE OR REPLACE).
-- ====================================================================

-- ---------------------------------------------------------------
-- 1. Account overview: one row per account with branch, subtype terms
--    and the names of all holders (joint accounts list every holder).
-- ---------------------------------------------------------------
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_account_overview AS
SELECT a.AccountNo,
       a.AccountType,
       a.Status,
       a.Balance,
       a.OpenedOn,
       b.BranchID,
       b.BranchName,
       COALESCE(s.MinimumBalance, cu.MinimumBalance) AS MinimumBalance,
       COALESCE(s.InterestRate, f.InterestRate)      AS InterestRate,
       COUNT(ah.CustomerID)                          AS HolderCount,
       GROUP_CONCAT(c.CustomerName ORDER BY c.CustomerID SEPARATOR ', ') AS Holders
FROM Account a
JOIN Branch b              ON b.BranchID  = a.BranchID
LEFT JOIN SavingsAccount s ON s.AccountNo = a.AccountNo
LEFT JOIN CurrentAccount cu ON cu.AccountNo = a.AccountNo
LEFT JOIN FixedDeposit f   ON f.AccountNo = a.AccountNo
LEFT JOIN AccountHolder ah ON ah.AccountNo = a.AccountNo
LEFT JOIN Customer c       ON c.CustomerID = ah.CustomerID
GROUP BY a.AccountNo, a.AccountType, a.Status, a.Balance, a.OpenedOn,
         b.BranchID, b.BranchName,
         s.MinimumBalance, cu.MinimumBalance, s.InterestRate, f.InterestRate;

-- ---------------------------------------------------------------
-- 2. Branch-wise account summary: counts by type and status, and the
--    total balance held at each branch.
-- ---------------------------------------------------------------
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_branch_account_summary AS
SELECT b.BranchID,
       b.BranchName,
       b.IFSC,
       COUNT(a.AccountNo)                                  AS TotalAccounts,
       COALESCE(SUM(a.AccountType = 'SAVINGS'), 0)         AS SavingsAccounts,
       COALESCE(SUM(a.AccountType = 'CURRENT'), 0)         AS CurrentAccounts,
       COALESCE(SUM(a.AccountType = 'FD'), 0)              AS FixedDeposits,
       COALESCE(SUM(a.Status = 'ACTIVE'), 0)               AS ActiveAccounts,
       COALESCE(SUM(a.Status = 'FROZEN'), 0)               AS FrozenAccounts,
       COALESCE(SUM(a.Status = 'CLOSED'), 0)               AS ClosedAccounts,
       COALESCE(SUM(a.Balance), 0)                         AS TotalBalance
FROM Branch b
LEFT JOIN Account a ON a.BranchID = b.BranchID
GROUP BY b.BranchID, b.BranchName, b.IFSC;

-- ---------------------------------------------------------------
-- 3. Branch staffing: employees by role and the managers' names.
-- ---------------------------------------------------------------
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_branch_staff AS
SELECT b.BranchID,
       b.BranchName,
       COUNT(e.EmployeeID)                          AS TotalEmployees,
       COALESCE(SUM(e.EmployeeRole = 'MANAGER'), 0) AS Managers,
       COALESCE(SUM(e.EmployeeRole = 'CLERK'), 0)   AS Clerks,
       GROUP_CONCAT(CASE WHEN e.EmployeeRole = 'MANAGER' THEN e.EmployeeName END
                    ORDER BY e.EmployeeID SEPARATOR ', ') AS ManagerNames
FROM Branch b
LEFT JOIN Employee e ON e.BranchID = b.BranchID
GROUP BY b.BranchID, b.BranchName;

-- ---------------------------------------------------------------
-- 4. Transaction history: one row per transaction, with source and
--    destination accounts and, for transfers, whether the two accounts
--    are at the same branch, different branches of one bank, or different banks.
-- ---------------------------------------------------------------
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_transaction_history AS
SELECT t.TransactionID,
       t.TransactionDate,
       t.TransactionType,
       t.Status,
       t.Channel,
       t.Amount,
       t.RequestID,
       CASE
           WHEN t.TransactionType = 'TRANSFER' THEN d.FromAccountNo
           WHEN t.TransactionType IN ('WITHDRAWAL', 'LOAN_REPAYMENT') THEN t.AccountNo
       END AS SourceAccountNo,
       CASE
           WHEN t.TransactionType = 'TRANSFER' THEN d.ToAccountNo
           WHEN t.TransactionType IN ('DEPOSIT', 'LOAN_DISBURSEMENT') THEN t.AccountNo
       END AS DestinationAccountNo,
       fb.BankID AS SourceBankID,
       source_bank.BankName AS SourceBankName,
       tb.BankID AS DestinationBankID,
       destination_bank.BankName AS DestinationBankName,
       CASE
           WHEN t.TransactionType <> 'TRANSFER' OR d.TransactionID IS NULL THEN NULL
           WHEN fb.BankID <> tb.BankID THEN 'INTER_BANK'
           WHEN fa.BranchID = ta.BranchID THEN 'INTRA_BRANCH'
           ELSE 'INTER_BRANCH'
       END AS TransferScope
FROM BankTransaction t
LEFT JOIN TransferDetails d ON d.TransactionID = t.TransactionID
LEFT JOIN Account fa        ON fa.AccountNo = d.FromAccountNo
LEFT JOIN Account ta        ON ta.AccountNo = d.ToAccountNo
LEFT JOIN Branch fb         ON fb.BranchID = fa.BranchID
LEFT JOIN Branch tb         ON tb.BranchID = ta.BranchID
LEFT JOIN Bank source_bank  ON source_bank.BankID = fb.BankID
LEFT JOIN Bank destination_bank ON destination_bank.BankID = tb.BankID;

-- ---------------------------------------------------------------
-- 5. Account statement: every transaction as a debit or credit line on
--    each account it touches (a transfer appears twice, once per account),
--    with a running balance. Only SUCCESS lines change the running balance;
--    PENDING and FAILED lines are listed but do not move it.
--    Usage: SELECT * FROM v_account_statement WHERE AccountNo = 1001
--           ORDER BY TransactionDate, TransactionID;
-- ---------------------------------------------------------------
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_account_statement AS
SELECT s.AccountNo,
       s.TransactionID,
       s.TransactionDate,
       s.TransactionType,
       s.Channel,
       s.Status,
       s.CounterpartyAccountNo,
       s.Debit,
       s.Credit,
       SUM(CASE WHEN s.Status = 'SUCCESS' THEN s.Credit - s.Debit ELSE 0 END)
           OVER (PARTITION BY s.AccountNo
                 ORDER BY s.TransactionDate, s.TransactionID
                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningBalance
FROM (
    SELECT t.AccountNo, t.TransactionID, t.TransactionDate, t.TransactionType,
           t.Channel, t.Status,
           NULL AS CounterpartyAccountNo,
           CASE WHEN t.TransactionType IN ('WITHDRAWAL', 'LOAN_REPAYMENT')
                THEN t.Amount ELSE 0 END AS Debit,
           CASE WHEN t.TransactionType IN ('DEPOSIT', 'LOAN_DISBURSEMENT')
                THEN t.Amount ELSE 0 END AS Credit
    FROM BankTransaction t
    WHERE t.TransactionType <> 'TRANSFER'
    UNION ALL
    SELECT d.FromAccountNo, t.TransactionID, t.TransactionDate, t.TransactionType,
           t.Channel, t.Status, d.ToAccountNo, t.Amount, 0
    FROM BankTransaction t
    JOIN TransferDetails d ON d.TransactionID = t.TransactionID
    UNION ALL
    SELECT d.ToAccountNo, t.TransactionID, t.TransactionDate, t.TransactionType,
           t.Channel, t.Status, d.FromAccountNo, 0, t.Amount
    FROM BankTransaction t
    JOIN TransferDetails d ON d.TransactionID = t.TransactionID
) s;

-- ---------------------------------------------------------------
-- 6. Customer statement: the account statement for every account a
--    customer holds. Joint accounts appear under each holder.
--    Usage: SELECT * FROM v_customer_statement WHERE CustomerID = 1
--           ORDER BY AccountNo, TransactionDate, TransactionID;
-- ---------------------------------------------------------------
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_customer_statement AS
SELECT c.CustomerID,
       c.CustomerName,
       st.AccountNo,
       st.TransactionID,
       st.TransactionDate,
       st.TransactionType,
       st.Channel,
       st.Status,
       st.CounterpartyAccountNo,
       st.Debit,
       st.Credit,
       st.RunningBalance
FROM Customer c
JOIN AccountHolder ah    ON ah.CustomerID = c.CustomerID
JOIN v_account_statement st ON st.AccountNo = ah.AccountNo;

-- ---------------------------------------------------------------
-- 7. Loan portfolio: one row per loan with its schedule and repayment
--    position. Scheduled amounts come from the EMI schedule, paid amounts
--    from payment allocations, and overdue means due before today and
--    not yet fully allocated. A loan with no schedule shows zeros.
-- ---------------------------------------------------------------
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_loan_portfolio AS
WITH inst AS (
    SELECT i.LoanID,
           i.InstallmentID,
           i.DueDate,
           i.PrincipalDue + i.InterestDue AS AmountDue,
           COALESCE(SUM(pa.AllocatedAmount), 0) AS AmountPaid
    FROM LoanInstallment i
    LEFT JOIN PaymentAllocation pa ON pa.InstallmentID = i.InstallmentID
    GROUP BY i.LoanID, i.InstallmentID, i.DueDate, i.PrincipalDue, i.InterestDue
),
sched AS (
    SELECT LoanID,
           COUNT(*)                                              AS InstallmentsGenerated,
           SUM(AmountDue)                                        AS ScheduledTotal,
           SUM(AmountPaid)                                       AS ScheduledPaid,
           SUM(CASE WHEN DueDate < CURDATE() AND AmountPaid < AmountDue
                    THEN AmountDue - AmountPaid ELSE 0 END)      AS OverdueAmount,
           MIN(CASE WHEN AmountPaid < AmountDue THEN DueDate END) AS NextUnpaidDueDate
    FROM inst
    GROUP BY LoanID
),
repaid AS (
    SELECT LoanID, SUM(Amount) AS AmountRepaid
    FROM Repayment
    GROUP BY LoanID
)
SELECT l.LoanID,
       la.ApplicationID,
       c.CustomerID,
       c.CustomerName,
       la.BranchID,
       b.BranchName,
       la.LoanType,
       l.SanctionDate,
       l.SanctionAmount,
       l.InterestRate,
       l.TenureMonths,
       l.Status,
       COALESCE(s.InstallmentsGenerated, 0)                    AS InstallmentsGenerated,
       COALESCE(s.ScheduledTotal, 0)                           AS ScheduledTotal,
       COALESCE(r.AmountRepaid, 0)                             AS AmountRepaid,
       COALESCE(s.ScheduledTotal, 0) - COALESCE(s.ScheduledPaid, 0) AS ScheduledOutstanding,
       COALESCE(s.OverdueAmount, 0)                            AS OverdueAmount,
       s.NextUnpaidDueDate
FROM Loan l
JOIN LoanApplication la ON la.ApplicationID = l.ApplicationID
JOIN Customer c         ON c.CustomerID = la.CustomerID
JOIN Branch b           ON b.BranchID = la.BranchID
LEFT JOIN sched s       ON s.LoanID = l.LoanID
LEFT JOIN repaid r      ON r.LoanID = l.LoanID;

-- ---------------------------------------------------------------
-- 8. Branch loan portfolio: loans by status, amounts and the number of
--    applications still awaiting a decision.
-- ---------------------------------------------------------------
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_branch_loan_portfolio AS
SELECT b.BranchID,
       b.BranchName,
       COUNT(p.LoanID)                                       AS TotalLoans,
       COALESCE(SUM(p.Status = 'SANCTIONED'), 0)             AS Sanctioned,
       COALESCE(SUM(p.Status = 'ACTIVE'), 0)                 AS ActiveLoans,
       COALESCE(SUM(p.Status = 'CLOSED'), 0)                 AS ClosedLoans,
       COALESCE(SUM(p.Status = 'DEFAULTED'), 0)              AS DefaultedLoans,
       COALESCE(SUM(p.SanctionAmount), 0)                    AS TotalSanctionedAmount,
       COALESCE(SUM(p.ScheduledOutstanding), 0)              AS TotalScheduledOutstanding,
       COALESCE(SUM(p.OverdueAmount), 0)                     AS TotalOverdue,
       (SELECT COUNT(*) FROM LoanApplication x
        WHERE x.BranchID = b.BranchID AND x.Status = 'PENDING') AS PendingApplications
FROM Branch b
LEFT JOIN v_loan_portfolio p ON p.BranchID = b.BranchID
GROUP BY b.BranchID, b.BranchName;

-- ---------------------------------------------------------------
-- 9. Pending applications: the work queue for branch managers.
-- ---------------------------------------------------------------
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_pending_applications AS
SELECT la.ApplicationID,
       la.ApplicationDate,
       la.BranchID,
       b.BranchName,
       c.CustomerID,
       c.CustomerName,
       la.LoanType,
       la.RequestedAmount,
       la.Purpose,
       COUNT(ag.GuarantorID) AS GuarantorsLinked
FROM LoanApplication la
JOIN Branch b   ON b.BranchID = la.BranchID
JOIN Customer c ON c.CustomerID = la.CustomerID
LEFT JOIN ApplicationGuarantor ag ON ag.ApplicationID = la.ApplicationID
WHERE la.Status = 'PENDING'
GROUP BY la.ApplicationID, la.ApplicationDate, la.BranchID, b.BranchName,
         c.CustomerID, c.CustomerName, la.LoanType, la.RequestedAmount, la.Purpose;
