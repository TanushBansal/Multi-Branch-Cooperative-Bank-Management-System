USE CooperativeBank;WITH account_statement AS (
select s.AccountNo,
       s.TransactionID,
       s.TransactionDate,
       s.TransactionType,
       s.Channel,
       s.Status,
       s.CounterpartyAccountNo,
       s.Debit,
       s.Credit,
       sum(case when s.Status = 'SUCCESS' then s.Credit - s.Debit else 0 end)
           over (partition by s.AccountNo
                 order by s.TransactionDate, s.TransactionID
                 rows between unbounded preceding and current row) as RunningBalance
from (
    select t.AccountNo, t.TransactionID, t.TransactionDate, t.TransactionType,
           t.Channel, t.Status,
           null as CounterpartyAccountNo,
           case when t.TransactionType in ('WITHDRAWAL', 'LOAN_REPAYMENT')
                then t.Amount else 0 end as Debit,
           case when t.TransactionType in ('DEPOSIT', 'LOAN_DISBURSEMENT')
                then t.Amount else 0 end as Credit
    from BankTransaction t
    where t.TransactionType <> 'TRANSFER'
    union all
    select d.FromAccountNo, t.TransactionID, t.TransactionDate, t.TransactionType,
           t.Channel, t.Status, d.ToAccountNo, t.Amount, 0
    from BankTransaction t
    join TransferDetails d on d.TransactionID = t.TransactionID
    union all
    select d.ToAccountNo, t.TransactionID, t.TransactionDate, t.TransactionType,
           t.Channel, t.Status, d.FromAccountNo, 0, t.Amount
    from BankTransaction t
    join TransferDetails d on d.TransactionID = t.TransactionID
) s
),
transfer_integrity_violations AS (
select t.TransactionID, t.Status, t.RequestID
from BankTransaction t
where t.TransactionType = 'TRANSFER'
  and not exists (
      select 1 from TransferDetails d where d.TransactionID = t.TransactionID
  )
)


-- Each returned row describes a violation. Zero rows means all checks pass.
SELECT 'Stored balance differs from successful ledger' AS Problem,
       a.AccountNo AS RecordID
FROM Account a
LEFT JOIN (
    SELECT AccountNo, SUM(Credit - Debit) AS NetAmount
    FROM account_statement
    WHERE Status = 'SUCCESS'
    GROUP BY AccountNo
) ledger ON ledger.AccountNo = a.AccountNo
WHERE a.Balance <> COALESCE(ledger.NetAmount, 0)

UNION ALL

SELECT 'Account is missing its subtype row', a.AccountNo
FROM Account a
LEFT JOIN SavingsAccount s ON s.AccountNo = a.AccountNo
LEFT JOIN CurrentAccount c ON c.AccountNo = a.AccountNo
LEFT JOIN FixedDeposit f ON f.AccountNo = a.AccountNo
WHERE (a.AccountType = 'SAVINGS' AND s.AccountNo IS NULL)
   OR (a.AccountType = 'CURRENT' AND c.AccountNo IS NULL)
   OR (a.AccountType = 'FD' AND f.AccountNo IS NULL)

UNION ALL

SELECT 'Transfer is missing its details row', TransactionID
FROM transfer_integrity_violations

UNION ALL

SELECT 'Approved application is missing its designated guarantor', a.ApplicationID
FROM LoanApplication a
LEFT JOIN ApplicationGuarantor g
    ON g.ApplicationID = a.ApplicationID AND g.GuarantorID = a.ApprovalGuarantorID
WHERE a.Status = 'APPROVED' AND g.GuarantorID IS NULL;
