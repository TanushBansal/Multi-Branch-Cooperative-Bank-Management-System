USE CooperativeBank;

START TRANSACTION;

INSERT INTO Customer (CustomerName, PAN) VALUES ('CRUD demo customer', 'DEMON1234A');
SET @crud_customer = LAST_INSERT_ID();

INSERT INTO Branch (BankID, IFSC, BranchName)
VALUES (1, 'DEMO0000123', 'CRUD demo branch');
SET @crud_branch = LAST_INSERT_ID();

SAVEPOINT before_crud_account;

SET @crud_account = 9800000001;
INSERT INTO Account (AccountNo, BranchID, AccountType, OpenedOn)
VALUES (@crud_account, @crud_branch, 'SAVINGS', CURDATE());
INSERT INTO SavingsAccount (AccountNo, InterestRate) VALUES (@crud_account, 3);
INSERT INTO AccountHolder (CustomerID, AccountNo) VALUES (@crud_customer, @crud_account);WITH account_overview AS (
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
         s.MinimumBalance, cu.MinimumBalance, s.InterestRate, f.InterestRate
)


SELECT c.CustomerName, v.BranchName, v.AccountNo, v.AccountType, v.Status
FROM account_overview v
JOIN Customer c ON c.CustomerID = @crud_customer
WHERE v.AccountNo = @crud_account;

UPDATE Customer SET Phone = '9999999999' WHERE CustomerID = @crud_customer;
UPDATE Branch SET BranchName = 'CRUD demo branch updated' WHERE BranchID = @crud_branch;
UPDATE Account SET Status = 'FROZEN' WHERE AccountNo = @crud_account;WITH account_overview AS (
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
         s.MinimumBalance, cu.MinimumBalance, s.InterestRate, f.InterestRate
)


SELECT c.CustomerName, c.Phone, v.BranchName, v.AccountNo, v.Status
FROM account_overview v
JOIN Customer c ON c.CustomerID = @crud_customer
WHERE v.AccountNo = @crud_account;

UPDATE Account SET Status = 'CLOSED' WHERE AccountNo = @crud_account;
SELECT AccountNo, Status FROM Account WHERE AccountNo = @crud_account;

ROLLBACK TO SAVEPOINT before_crud_account;

DELETE FROM Customer WHERE CustomerID = @crud_customer;
SELECT ROW_COUNT() AS CustomersDeleted;
DELETE FROM Branch WHERE BranchID = @crud_branch;
SELECT ROW_COUNT() AS BranchesDeleted;

ROLLBACK;
