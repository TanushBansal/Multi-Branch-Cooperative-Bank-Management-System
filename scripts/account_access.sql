-- Optional administrator setup: run after building database/01 through 07.
-- Assign this role to a dedicated application user with no other write grants.
-- Do not assign it to root and expect root's existing privileges to disappear.
CREATE ROLE IF NOT EXISTS 'cooperative_account_operator';

GRANT SELECT ON CooperativeBank.Account TO 'cooperative_account_operator';
GRANT SELECT ON CooperativeBank.AccountHolder TO 'cooperative_account_operator';
GRANT SELECT ON CooperativeBank.SavingsAccount TO 'cooperative_account_operator';
GRANT SELECT ON CooperativeBank.CurrentAccount TO 'cooperative_account_operator';
GRANT SELECT ON CooperativeBank.FixedDeposit TO 'cooperative_account_operator';
GRANT SELECT ON CooperativeBank.BankTransaction TO 'cooperative_account_operator';

GRANT EXECUTE ON PROCEDURE CooperativeBank.OpenSavingsAccount TO 'cooperative_account_operator';
GRANT EXECUTE ON PROCEDURE CooperativeBank.OpenCurrentAccount TO 'cooperative_account_operator';
GRANT EXECUTE ON PROCEDURE CooperativeBank.OpenFixedDeposit TO 'cooperative_account_operator';
GRANT EXECUTE ON PROCEDURE CooperativeBank.Deposit TO 'cooperative_account_operator';
GRANT EXECUTE ON PROCEDURE CooperativeBank.Withdraw TO 'cooperative_account_operator';
GRANT EXECUTE ON PROCEDURE CooperativeBank.Transfer TO 'cooperative_account_operator';

-- For an existing dedicated user (replace bank_app and host as appropriate):
-- GRANT 'cooperative_account_operator' TO 'bank_app'@'localhost';
-- SET DEFAULT ROLE 'cooperative_account_operator' TO 'bank_app'@'localhost';
