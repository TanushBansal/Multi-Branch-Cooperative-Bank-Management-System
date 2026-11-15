-- 05_loans.sql: to be written
-- =====================================================
-- 05_loans.sql
-- Loan Management Module
-- =====================================================
-- Handles:
-- 1. Loan application
-- 2. Loan approval and rejection
-- 3. Loan disbursement
-- 4. EMI / installment generation
-- 5. Loan repayment
--
-- Uses MySQL stored procedures and transactions.
--
-- Run after:
-- 01_schema.sql
-- 02_constraints_triggers.sql
-- =====================================================

USE CooperativeBank;

-- =====================================================
-- PART 1: LOAN MODULE DEMONSTRATION DATASET
-- =====================================================

START TRANSACTION;

-- 1. Create demo bank

INSERT INTO Bank (BankName)
VALUES ('Demo Cooperative Bank');

SET @demo_bank_id = LAST_INSERT_ID();


-- 2. Create demo branch

INSERT INTO Branch
(BankID, IFSC, BranchName, Address)
VALUES
(@demo_bank_id, 'DEMO0IND001', 'Indore Main Branch',
 'Vijay Nagar, Indore, Madhya Pradesh');

SET @demo_branch_id = LAST_INSERT_ID();


-- 3. Create branch employee

INSERT INTO Employee
(BranchID, EmployeeName, Phone, Email)
VALUES
(@demo_branch_id, 'Rahul Sharma', '9876500001',
 'rahul.demo@bank.com');

SET @demo_employee_id = LAST_INSERT_ID();


-- 4. Make employee a manager

INSERT INTO Manager (EmployeeID)
VALUES (@demo_employee_id);


-- 5. Create demo customer

INSERT INTO Customer
(CustomerName, Phone, Email, PAN, Address)
VALUES
('Aman Verma', '9876500002',
 'aman.demo@gmail.com', 'ABCDE1234F',
 'Indore, Madhya Pradesh');

SET @demo_customer_id = LAST_INSERT_ID();


-- 6. Create customer savings account

INSERT INTO Account
(AccountNo, BranchID, AccountType, Balance, Status, OpenedOn)
VALUES
(9001000001, @demo_branch_id, 'SAVINGS',
 500000.00, 'ACTIVE', '2026-01-01');


-- 7. Connect customer with account

INSERT INTO AccountHolder (CustomerID, AccountNo)
VALUES
(@demo_customer_id, 9001000001);


-- 8. Create savings account details

INSERT INTO SavingsAccount
(AccountNo, InterestRate, MinimumBalance)
VALUES
(9001000001, 4.00, 1000.00);


-- 9. Create demo guarantor

INSERT INTO Guarantor
(GuarantorName, Phone, PAN, Address)
VALUES
('Rohan Mehta', '9876500003',
 'FGHIJ5678K', 'Indore, Madhya Pradesh');

SET @demo_guarantor_id = LAST_INSERT_ID();


COMMIT;


-- =====================================================
-- PART 2: VERIFY DEMONSTRATION DATASET
-- =====================================================

-- Bank and branch

SELECT *
FROM Bank
WHERE BankID = @demo_bank_id;

SELECT *
FROM Branch
WHERE BranchID = @demo_branch_id;


-- Manager details

SELECT E.*, M.EmployeeID AS ManagerID
FROM Employee E
JOIN Manager M ON E.EmployeeID = M.EmployeeID
WHERE E.EmployeeID = @demo_employee_id;


-- Customer and account details

SELECT
    C.CustomerID,
    C.CustomerName,
    C.PAN,
    A.AccountNo,
    A.AccountType,
    A.Balance,
    A.Status,
    S.InterestRate,
    S.MinimumBalance
FROM Customer C
JOIN AccountHolder AH ON C.CustomerID = AH.CustomerID
JOIN Account A ON AH.AccountNo = A.AccountNo
JOIN SavingsAccount S ON A.AccountNo = S.AccountNo
WHERE C.CustomerID = @demo_customer_id;


-- Guarantor details

SELECT *
FROM Guarantor
WHERE GuarantorID = @demo_guarantor_id;


-- =====================================================
-- PART 3: LOAN PROCEDURES
-- Will be implemented below.
-- =====================================================

DELIMITER $$

-- Procedures will be added here.

DELIMITER ;


-- =====================================================
-- PART 4: LOAN TRANSACTION TEST CASES
-- Will be added after procedure implementation.
-- =====================================================
