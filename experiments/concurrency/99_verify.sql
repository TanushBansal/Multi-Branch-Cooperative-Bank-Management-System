-- 99_verify.sql
-- Compares each demonstration account's stored balance with the balance
-- implied by its successful transactions. Difference must be 0 for a
-- healthy account. Run after each scenario, in any session.

USE CooperativeBank;

SELECT a.AccountNo,
       a.Balance AS StoredBalance,
       SUM(CASE t.TransactionType
               WHEN 'DEPOSIT'    THEN  t.Amount
               WHEN 'WITHDRAWAL' THEN -t.Amount
           END) AS LedgerBalance,
       a.Balance - SUM(CASE t.TransactionType
               WHEN 'DEPOSIT'    THEN  t.Amount
               WHEN 'WITHDRAWAL' THEN -t.Amount
           END) AS Difference
FROM Account a
JOIN BankTransaction t
  ON t.AccountNo = a.AccountNo AND t.Status = 'SUCCESS'
WHERE a.AccountNo BETWEEN 9100000001 AND 9100000002
GROUP BY a.AccountNo, a.Balance
ORDER BY a.AccountNo;

SELECT AccountNo, TransactionType, Amount, Status, RequestID
FROM BankTransaction
WHERE AccountNo BETWEEN 9100000001 AND 9100000002
ORDER BY AccountNo, TransactionID;
