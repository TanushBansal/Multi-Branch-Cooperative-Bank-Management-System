USE CooperativeBank;

CREATE INDEX ix_transaction_date
    ON BankTransaction (TransactionDate);

CREATE INDEX ix_transaction_account_date
    ON BankTransaction (AccountNo, TransactionDate);