USE CooperativeBank;

-- Each returned row describes a violation. Zero rows means all checks pass.
SELECT 'Stored balance differs from successful ledger' AS Problem,
       a.AccountNo AS RecordID
FROM Account a
LEFT JOIN (
    SELECT AccountNo, SUM(Credit - Debit) AS NetAmount
    FROM v_account_statement
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
FROM v_transfer_integrity_violations

UNION ALL

SELECT 'Approved application is missing its designated guarantor', a.ApplicationID
FROM LoanApplication a
LEFT JOIN ApplicationGuarantor g
    ON g.ApplicationID = a.ApplicationID AND g.GuarantorID = a.ApprovalGuarantorID
WHERE a.Status = 'APPROVED' AND g.GuarantorID IS NULL;
