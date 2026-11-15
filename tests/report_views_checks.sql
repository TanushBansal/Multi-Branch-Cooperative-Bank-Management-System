-- report_views_checks.sql
-- Self-checks for the reporting views in database/06_report_views.sql.
-- Each row returned describes a problem. An EMPTY result means every check passed.
-- Run after building the database (files 01 to 04 and the views).

USE CooperativeBank;

-- 1. The last running balance on every account's statement must equal its stored balance.
SELECT 'Statement running balance differs from stored balance' AS Problem,
       a.AccountNo AS Detail
FROM Account a
LEFT JOIN (
    SELECT AccountNo, RunningBalance,
           ROW_NUMBER() OVER (PARTITION BY AccountNo
                              ORDER BY TransactionDate DESC, TransactionID DESC) AS rn
    FROM v_account_statement
) x ON x.AccountNo = a.AccountNo AND x.rn = 1
WHERE a.Balance <> COALESCE(x.RunningBalance, 0)

UNION ALL
-- 2. Branch summary totals must add up to the whole bank.
SELECT 'Branch summary balance total differs from Account table', NULL
WHERE (SELECT COALESCE(SUM(TotalBalance), 0) FROM v_branch_account_summary)
   <> (SELECT COALESCE(SUM(Balance), 0) FROM Account)

UNION ALL
SELECT 'Branch summary account count differs from Account table', NULL
WHERE (SELECT COALESCE(SUM(TotalAccounts), 0) FROM v_branch_account_summary)
   <> (SELECT COUNT(*) FROM Account)

UNION ALL
-- 3. Each view must return exactly one row per base record.
SELECT 'v_account_overview row count differs from Account', NULL
WHERE (SELECT COUNT(*) FROM v_account_overview) <> (SELECT COUNT(*) FROM Account)

UNION ALL
SELECT 'v_transaction_history row count differs from BankTransaction', NULL
WHERE (SELECT COUNT(*) FROM v_transaction_history) <> (SELECT COUNT(*) FROM BankTransaction)

UNION ALL
SELECT 'v_loan_portfolio row count differs from Loan', NULL
WHERE (SELECT COUNT(*) FROM v_loan_portfolio) <> (SELECT COUNT(*) FROM Loan)

UNION ALL
-- 4. Overdue amount can never exceed the outstanding scheduled amount.
SELECT 'Overdue amount exceeds scheduled outstanding', LoanID
FROM v_loan_portfolio
WHERE OverdueAmount > ScheduledOutstanding

UNION ALL
-- 5. Branch loan totals must add up to the loan portfolio.
SELECT 'Branch loan total differs from loan portfolio', NULL
WHERE (SELECT COALESCE(SUM(TotalSanctionedAmount), 0) FROM v_branch_loan_portfolio)
   <> (SELECT COALESCE(SUM(SanctionAmount), 0) FROM v_loan_portfolio);
