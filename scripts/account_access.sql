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
