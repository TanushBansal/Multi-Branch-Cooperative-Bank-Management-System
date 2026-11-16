use CooperativeBank;

-- transfers missing details
select t.TransactionID, t.Status, t.RequestID
from BankTransaction t
where t.TransactionType = 'TRANSFER'
  and not exists (
      select 1 from TransferDetails d where d.TransactionID = t.TransactionID
  );

-- account overview
select a.AccountNo,
       a.AccountType,
       a.Status,
       a.Balance,
       a.OpenedOn,
       b.BranchID,
       b.BranchName,
       coalesce(s.MinimumBalance, cu.MinimumBalance) as MinimumBalance,
       coalesce(s.InterestRate, f.InterestRate) as InterestRate,
       count(ah.CustomerID) as HolderCount,
       group_concat(c.CustomerName order by c.CustomerID separator ', ') as Holders
from Account a
join Branch b on b.BranchID = a.BranchID
left join SavingsAccount s on s.AccountNo = a.AccountNo
left join CurrentAccount cu on cu.AccountNo = a.AccountNo
left join FixedDeposit f on f.AccountNo = a.AccountNo
left join AccountHolder ah on ah.AccountNo = a.AccountNo
left join Customer c on c.CustomerID = ah.CustomerID
group by a.AccountNo, a.AccountType, a.Status, a.Balance, a.OpenedOn,
         b.BranchID, b.BranchName,
         s.MinimumBalance, cu.MinimumBalance, s.InterestRate, f.InterestRate;

-- branch account summary
select b.BranchID,
       b.BranchName,
       b.IFSC,
       count(a.AccountNo) as TotalAccounts,
       coalesce(sum(a.AccountType = 'SAVINGS'), 0) as SavingsAccounts,
       coalesce(sum(a.AccountType = 'CURRENT'), 0) as CurrentAccounts,
       coalesce(sum(a.AccountType = 'FD'), 0) as FixedDeposits,
       coalesce(sum(a.Status = 'ACTIVE'), 0) as ActiveAccounts,
       coalesce(sum(a.Status = 'FROZEN'), 0) as FrozenAccounts,
       coalesce(sum(a.Status = 'CLOSED'), 0) as ClosedAccounts,
       coalesce(sum(a.Balance), 0) as TotalBalance
from Branch b
left join Account a on a.BranchID = b.BranchID
group by b.BranchID, b.BranchName, b.IFSC;

-- branch staff
select b.BranchID,
       b.BranchName,
       count(e.EmployeeID) as TotalEmployees,
       coalesce(sum(e.EmployeeRole = 'MANAGER'), 0) as Managers,
       coalesce(sum(e.EmployeeRole = 'CLERK'), 0) as Clerks,
       group_concat(case when e.EmployeeRole = 'MANAGER' then e.EmployeeName end
                    order by e.EmployeeID separator ', ') as ManagerNames
from Branch b
left join Employee e on e.BranchID = b.BranchID
group by b.BranchID, b.BranchName;

-- transaction history
select t.TransactionID,
       t.TransactionDate,
       t.TransactionType,
       t.Status,
       t.Channel,
       t.Amount,
       t.RequestID,
       case
           when t.TransactionType = 'TRANSFER' then d.FromAccountNo
           when t.TransactionType in ('WITHDRAWAL', 'LOAN_REPAYMENT') then t.AccountNo
       end as SourceAccountNo,
       case
           when t.TransactionType = 'TRANSFER' then d.ToAccountNo
           when t.TransactionType in ('DEPOSIT', 'LOAN_DISBURSEMENT') then t.AccountNo
       end as DestinationAccountNo,
       fb.BankID as SourceBankID,
       source_bank.BankName as SourceBankName,
       tb.BankID as DestinationBankID,
       destination_bank.BankName as DestinationBankName,
       case
           when t.TransactionType <> 'TRANSFER' or d.TransactionID is null then null
           when fb.BankID <> tb.BankID then 'INTER_BANK'
           when fa.BranchID = ta.BranchID then 'INTRA_BRANCH'
           else 'INTER_BRANCH'
       end as TransferScope
from BankTransaction t
left join TransferDetails d on d.TransactionID = t.TransactionID
left join Account fa on fa.AccountNo = d.FromAccountNo
left join Account ta on ta.AccountNo = d.ToAccountNo
left join Branch fb on fb.BranchID = fa.BranchID
left join Branch tb on tb.BranchID = ta.BranchID
left join Bank source_bank on source_bank.BankID = fb.BankID
left join Bank destination_bank on destination_bank.BankID = tb.BankID;

-- account statement
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
) s;

-- customer statement
with account_statement as (
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
)
select c.CustomerID,
       c.CustomerName,
       st.AccountNo,
       st.TransactionID,
       st.TransactionDate,
       st.TransactionType,
       st.Channel,
       st.Status,
       st.CounterpartyAccountNo,
       st.Debit,
       st.Credit,
       st.RunningBalance
from Customer c
join AccountHolder ah on ah.CustomerID = c.CustomerID
join account_statement st on st.AccountNo = ah.AccountNo;

-- loan portfolio
with inst as (
    select i.LoanID,
           i.InstallmentID,
           i.DueDate,
           i.PrincipalDue + i.InterestDue as AmountDue,
           coalesce(sum(pa.AllocatedAmount), 0) as AmountPaid
    from LoanInstallment i
    left join PaymentAllocation pa on pa.InstallmentID = i.InstallmentID
    group by i.LoanID, i.InstallmentID, i.DueDate, i.PrincipalDue, i.InterestDue
),
sched as (
    select LoanID,
           count(*) as InstallmentsGenerated,
           sum(AmountDue) as ScheduledTotal,
           sum(AmountPaid) as ScheduledPaid,
           sum(case when DueDate < curdate() and AmountPaid < AmountDue
                    then AmountDue - AmountPaid else 0 end) as OverdueAmount,
           min(case when AmountPaid < AmountDue then DueDate end) as NextUnpaidDueDate
    from inst
    group by LoanID
),
repaid as (
    select LoanID, sum(Amount) as AmountRepaid
    from Repayment
    group by LoanID
)
select l.LoanID,
       la.ApplicationID,
       c.CustomerID,
       c.CustomerName,
       la.BranchID,
       b.BranchName,
       la.LoanType,
       l.SanctionDate,
       l.SanctionAmount,
       l.InterestRate,
       l.TenureMonths,
       l.Status,
       coalesce(s.InstallmentsGenerated, 0) as InstallmentsGenerated,
       coalesce(s.ScheduledTotal, 0) as ScheduledTotal,
       coalesce(r.AmountRepaid, 0) as AmountRepaid,
       coalesce(s.ScheduledTotal, 0) - coalesce(s.ScheduledPaid, 0) as ScheduledOutstanding,
       coalesce(s.OverdueAmount, 0) as OverdueAmount,
       s.NextUnpaidDueDate
from Loan l
join LoanApplication la on la.ApplicationID = l.ApplicationID
join Customer c on c.CustomerID = la.CustomerID
join Branch b on b.BranchID = la.BranchID
left join sched s on s.LoanID = l.LoanID
left join repaid r on r.LoanID = l.LoanID;

-- branch loan portfolio
with loan_portfolio as (
with inst as (
    select i.LoanID,
           i.InstallmentID,
           i.DueDate,
           i.PrincipalDue + i.InterestDue as AmountDue,
           coalesce(sum(pa.AllocatedAmount), 0) as AmountPaid
    from LoanInstallment i
    left join PaymentAllocation pa on pa.InstallmentID = i.InstallmentID
    group by i.LoanID, i.InstallmentID, i.DueDate, i.PrincipalDue, i.InterestDue
),
sched as (
    select LoanID,
           count(*) as InstallmentsGenerated,
           sum(AmountDue) as ScheduledTotal,
           sum(AmountPaid) as ScheduledPaid,
           sum(case when DueDate < curdate() and AmountPaid < AmountDue
                    then AmountDue - AmountPaid else 0 end) as OverdueAmount,
           min(case when AmountPaid < AmountDue then DueDate end) as NextUnpaidDueDate
    from inst
    group by LoanID
),
repaid as (
    select LoanID, sum(Amount) as AmountRepaid
    from Repayment
    group by LoanID
)
select l.LoanID,
       la.ApplicationID,
       c.CustomerID,
       c.CustomerName,
       la.BranchID,
       b.BranchName,
       la.LoanType,
       l.SanctionDate,
       l.SanctionAmount,
       l.InterestRate,
       l.TenureMonths,
       l.Status,
       coalesce(s.InstallmentsGenerated, 0) as InstallmentsGenerated,
       coalesce(s.ScheduledTotal, 0) as ScheduledTotal,
       coalesce(r.AmountRepaid, 0) as AmountRepaid,
       coalesce(s.ScheduledTotal, 0) - coalesce(s.ScheduledPaid, 0) as ScheduledOutstanding,
       coalesce(s.OverdueAmount, 0) as OverdueAmount,
       s.NextUnpaidDueDate
from Loan l
join LoanApplication la on la.ApplicationID = l.ApplicationID
join Customer c on c.CustomerID = la.CustomerID
join Branch b on b.BranchID = la.BranchID
left join sched s on s.LoanID = l.LoanID
left join repaid r on r.LoanID = l.LoanID
)
select b.BranchID,
       b.BranchName,
       count(p.LoanID) as TotalLoans,
       coalesce(sum(p.Status = 'SANCTIONED'), 0) as Sanctioned,
       coalesce(sum(p.Status = 'ACTIVE'), 0) as ActiveLoans,
       coalesce(sum(p.Status = 'CLOSED'), 0) as ClosedLoans,
       coalesce(sum(p.Status = 'DEFAULTED'), 0) as DefaultedLoans,
       coalesce(sum(p.SanctionAmount), 0) as TotalSanctionedAmount,
       coalesce(sum(p.ScheduledOutstanding), 0) as TotalScheduledOutstanding,
       coalesce(sum(p.OverdueAmount), 0) as TotalOverdue,
       (select count(*) from LoanApplication x
        where x.BranchID = b.BranchID and x.Status = 'PENDING') as PendingApplications
from Branch b
left join loan_portfolio p on p.BranchID = b.BranchID
group by b.BranchID, b.BranchName;

-- pending applications
select la.ApplicationID,
       la.ApplicationDate,
       la.BranchID,
       b.BranchName,
       c.CustomerID,
       c.CustomerName,
       la.LoanType,
       la.RequestedAmount,
       la.Purpose,
       count(ag.GuarantorID) as GuarantorsLinked
from LoanApplication la
join Branch b on b.BranchID = la.BranchID
join Customer c on c.CustomerID = la.CustomerID
left join ApplicationGuarantor ag on ag.ApplicationID = la.ApplicationID
where la.Status = 'PENDING'
group by la.ApplicationID, la.ApplicationDate, la.BranchID, b.BranchName,
         c.CustomerID, c.CustomerName, la.LoanType, la.RequestedAmount, la.Purpose;
