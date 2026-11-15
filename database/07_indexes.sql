USE CooperativeBank;

-- Supports transaction date ranges across all accounts.
CREATE INDEX ix_transaction_date
    ON BankTransaction (TransactionDate);

-- Supports a date range within a single account.
CREATE INDEX ix_transaction_account_date
    ON BankTransaction (AccountNo, TransactionDate);