-- CRUD demonstration for the seeded CooperativeBank database.
-- All changes are rolled back. Account removal is demonstrated by closure.
USE CooperativeBank;

START TRANSACTION;

-- Create customer and branch records.
INSERT INTO Customer (CustomerName, PAN) VALUES ('CRUD demo customer', 'DEMON1234A');
SET @crud_customer = LAST_INSERT_ID();

INSERT INTO Branch (BankID, IFSC, BranchName)
VALUES (1, 'DEMO0000123', 'CRUD demo branch');
SET @crud_branch = LAST_INSERT_ID();

-- Roll back only the account portion before demonstrating parent deletion.
SAVEPOINT before_crud_account;

-- Create a zero-balance savings account, its subtype and its first holder.
SET @crud_account = 9800000001;
INSERT INTO Account (AccountNo, BranchID, AccountType, OpenedOn)
VALUES (@crud_account, @crud_branch, 'SAVINGS', CURDATE());
INSERT INTO SavingsAccount (AccountNo, InterestRate) VALUES (@crud_account, 3);
INSERT INTO AccountHolder (CustomerID, AccountNo) VALUES (@crud_customer, @crud_account);

-- Read customer, branch and account data together.
SELECT c.CustomerName, v.BranchName, v.AccountNo, v.AccountType, v.Status
FROM v_account_overview v
JOIN Customer c ON c.CustomerID = @crud_customer
WHERE v.AccountNo = @crud_account;

-- Update the customer profile, branch name and account status.
UPDATE Customer SET Phone = '9999999999' WHERE CustomerID = @crud_customer;
UPDATE Branch SET BranchName = 'CRUD demo branch updated' WHERE BranchID = @crud_branch;
UPDATE Account SET Status = 'FROZEN' WHERE AccountNo = @crud_account;

SELECT c.CustomerName, c.Phone, v.BranchName, v.AccountNo, v.Status
FROM v_account_overview v
JOIN Customer c ON c.CustomerID = @crud_customer
WHERE v.AccountNo = @crud_account;

UPDATE Account SET Status = 'CLOSED' WHERE AccountNo = @crud_account;
SELECT AccountNo, Status FROM Account WHERE AccountNo = @crud_account;

ROLLBACK TO SAVEPOINT before_crud_account;

-- Delete customer and branch records after the demo account is removed by rollback.
DELETE FROM Customer WHERE CustomerID = @crud_customer;
SELECT ROW_COUNT() AS CustomersDeleted;
DELETE FROM Branch WHERE BranchID = @crud_branch;
SELECT ROW_COUNT() AS BranchesDeleted;

ROLLBACK;
