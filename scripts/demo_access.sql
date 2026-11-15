-- Run as an administrator after setting up CooperativeBankDemo.
-- Assign this role to a dedicated demo user and make it the user's default role.
-- Rerun after reinstalling the demo procedures.

CREATE ROLE IF NOT EXISTS 'cooperative_demo_operator';

-- The explorer lists these objects. Invoker views also need underlying table reads.
GRANT SELECT ON CooperativeBankDemo.Bank TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.Branch TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.Employee TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.Manager TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.Clerk TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.Customer TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.Account TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.AccountHolder TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.Nominee TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.SavingsAccount TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.CurrentAccount TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.FixedDeposit TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.BankTransaction TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.TransferDetails TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.LoanApplication TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.Guarantor TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.ApplicationGuarantor TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.Loan TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.LoanInstallment TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.Repayment TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.PaymentAllocation TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.v_transfer_integrity_violations TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.v_account_overview TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.v_branch_account_summary TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.v_branch_staff TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.v_transaction_history TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.v_account_statement TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.v_customer_statement TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.v_loan_portfolio TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.v_branch_loan_portfolio TO 'cooperative_demo_operator';
GRANT SELECT ON CooperativeBankDemo.v_pending_applications TO 'cooperative_demo_operator';

-- The demo performs writes through stored procedures.
GRANT EXECUTE ON CooperativeBankDemo.* TO 'cooperative_demo_operator';
