
CREATE ROLE IF NOT EXISTS 'cooperative_demo_operator';

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


GRANT EXECUTE ON CooperativeBankDemo.* TO 'cooperative_demo_operator';
