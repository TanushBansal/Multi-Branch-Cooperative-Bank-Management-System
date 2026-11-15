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
