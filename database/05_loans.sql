
-- =====================================================
-- 05_loans.sql
-- Loan Management Module
-- =====================================================
-- Handles:
-- 1. Loan application
-- 2. Loan approval and rejection
-- 3. Loan disbursement (to be implemented)
-- 4. EMI / installment generation (to be implemented)
-- 5. Loan repayment (to be implemented)
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

-- Initialize variables to avoid old session values

SET @demo_bank_id = NULL;
SET @demo_branch_id = NULL;
SET @demo_employee_id = NULL;
SET @demo_customer_id = NULL;
SET @demo_guarantor_id = NULL;


-- 1. Create demo bank if it does not exist

SELECT BankID INTO @demo_bank_id
FROM Bank
WHERE BankName = 'Demo Cooperative Bank'
LIMIT 1;

INSERT INTO Bank (BankName)
SELECT 'Demo Cooperative Bank'
WHERE @demo_bank_id IS NULL;

SET @demo_bank_id = IFNULL(@demo_bank_id, LAST_INSERT_ID());


-- 2. Create demo branch if it does not exist

SELECT BranchID INTO @demo_branch_id
FROM Branch
WHERE IFSC = 'DEMO0IND001'
LIMIT 1;

INSERT INTO Branch
(BankID, IFSC, BranchName, Address)
SELECT
    @demo_bank_id,
    'DEMO0IND001',
    'Indore Main Branch',
    'Vijay Nagar, Indore, Madhya Pradesh'
WHERE @demo_branch_id IS NULL;

SET @demo_branch_id = IFNULL(@demo_branch_id, LAST_INSERT_ID());


-- 3. Create demo employee if it does not exist

SELECT EmployeeID INTO @demo_employee_id
FROM Employee
WHERE Email = 'rahul.demo@bank.com'
LIMIT 1;

INSERT INTO Employee
(BranchID, EmployeeName, Phone, Email)
SELECT
    @demo_branch_id,
    'Rahul Sharma',
    '9876500001',
    'rahul.demo@bank.com'
WHERE @demo_employee_id IS NULL;

SET @demo_employee_id = IFNULL(@demo_employee_id, LAST_INSERT_ID());


-- 4. Make employee a manager if not already a manager

INSERT INTO Manager (EmployeeID)
SELECT @demo_employee_id
WHERE NOT EXISTS (
    SELECT 1
    FROM Manager
    WHERE EmployeeID = @demo_employee_id
);


-- 5. Create demo customer if it does not exist

SELECT CustomerID INTO @demo_customer_id
FROM Customer
WHERE PAN = 'ABCDE1234F'
LIMIT 1;

INSERT INTO Customer
(CustomerName, Phone, Email, PAN, Address)
SELECT
    'Aman Verma',
    '9876500002',
    'aman.demo@gmail.com',
    'ABCDE1234F',
    'Indore, Madhya Pradesh'
WHERE @demo_customer_id IS NULL;

SET @demo_customer_id = IFNULL(@demo_customer_id, LAST_INSERT_ID());


-- 6. Create customer savings account if it does not exist

INSERT INTO Account
(AccountNo, BranchID, AccountType, Balance, Status, OpenedOn)
SELECT
    9001000001,
    @demo_branch_id,
    'SAVINGS',
    500000.00,
    'ACTIVE',
    '2026-01-01'
WHERE NOT EXISTS (
    SELECT 1
    FROM Account
    WHERE AccountNo = 9001000001
);


-- 7. Connect customer with account if not already connected

INSERT INTO AccountHolder (CustomerID, AccountNo)
SELECT @demo_customer_id, 9001000001
WHERE NOT EXISTS (
    SELECT 1
    FROM AccountHolder
    WHERE CustomerID = @demo_customer_id
    AND AccountNo = 9001000001
);


-- 8. Create savings account details if missing

INSERT INTO SavingsAccount
(AccountNo, InterestRate, MinimumBalance)
SELECT
    9001000001,
    4.00,
    1000.00
WHERE NOT EXISTS (
    SELECT 1
    FROM SavingsAccount
    WHERE AccountNo = 9001000001
);


-- 9. Create demo guarantor if it does not exist

SELECT GuarantorID INTO @demo_guarantor_id
FROM Guarantor
WHERE PAN = 'FGHIJ5678K'
LIMIT 1;

INSERT INTO Guarantor
(GuarantorName, Phone, PAN, Address)
SELECT
    'Rohan Mehta',
    '9876500003',
    'FGHIJ5678K',
    'Indore, Madhya Pradesh'
WHERE @demo_guarantor_id IS NULL;

SET @demo_guarantor_id = IFNULL(@demo_guarantor_id, LAST_INSERT_ID());


-- =====================================================
-- PART 2: VERIFY DEMONSTRATION DATASET
-- =====================================================

SELECT * FROM Bank
WHERE BankID = @demo_bank_id;

SELECT * FROM Branch
WHERE BranchID = @demo_branch_id;

SELECT E.*, M.EmployeeID AS ManagerID
FROM Employee E
JOIN Manager M ON E.EmployeeID = M.EmployeeID
WHERE E.EmployeeID = @demo_employee_id;

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

SELECT * FROM Guarantor
WHERE GuarantorID = @demo_guarantor_id;


-- =====================================================
-- PART 3: LOAN PROCEDURES
-- =====================================================


-- =====================================================
-- PROCEDURE 1: APPLY FOR A LOAN
-- =====================================================

DROP PROCEDURE IF EXISTS ApplyLoan;

DELIMITER $$

CREATE PROCEDURE ApplyLoan(
    IN p_customer_id INT,
    IN p_branch_id INT,
    IN p_loan_type VARCHAR(50),
    IN p_requested_amount DECIMAL(15,2),
    IN p_purpose VARCHAR(100)
)
BEGIN

    DECLARE v_count INT DEFAULT 0;
    DECLARE v_application_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- Check requested amount

    IF p_requested_amount IS NULL OR p_requested_amount <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Requested amount must be positive';
    END IF;

    -- Check loan type

    IF p_loan_type IS NULL OR TRIM(p_loan_type) = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan type cannot be empty';
    END IF;

    -- Check purpose

    IF p_purpose IS NULL OR TRIM(p_purpose) = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan purpose cannot be empty';
    END IF;

    -- Check customer

    SELECT COUNT(*)
    INTO v_count
    FROM Customer
    WHERE CustomerID = p_customer_id;

    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Customer does not exist';
    END IF;

    -- Check branch

    SELECT COUNT(*)
    INTO v_count
    FROM Branch
    WHERE BranchID = p_branch_id;

    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Branch does not exist';
    END IF;

    START TRANSACTION;

    INSERT INTO LoanApplication
    (
        CustomerID,
        BranchID,
        ApplicationDate,
        LoanType,
        RequestedAmount,
        Purpose,
        Status
    )
    VALUES
    (
        p_customer_id,
        p_branch_id,
        CURDATE(),
        p_loan_type,
        p_requested_amount,
        p_purpose,
        'PENDING'
    );

    SET v_application_id = LAST_INSERT_ID();

    COMMIT;

    SELECT
        v_application_id AS ApplicationID,
        'PENDING' AS ApplicationStatus,
        'Loan application submitted successfully' AS Message;

END $$

DELIMITER ;


-- =====================================================
-- PROCEDURE 2: REVIEW A LOAN APPLICATION
-- =====================================================

DROP PROCEDURE IF EXISTS ReviewLoan;

DELIMITER $$

CREATE PROCEDURE ReviewLoan(
    IN p_application_id INT,
    IN p_manager_id INT,
    IN p_decision VARCHAR(20)
)
BEGIN

    DECLARE v_count INT DEFAULT 0;
    DECLARE v_application_branch INT;
    DECLARE v_manager_branch INT;
    DECLARE v_current_status VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Check whether the decision is valid

    IF p_decision IS NULL OR UPPER(TRIM(p_decision)) NOT IN ('APPROVED', 'REJECTED') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid decision';
    END IF;

    -- Check whether the application exists

    SELECT COUNT(*)
    INTO v_count
    FROM LoanApplication
    WHERE ApplicationID = p_application_id;

    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan application does not exist';
    END IF;

    -- Get application status and branch

    SELECT Status, BranchID
    INTO v_current_status, v_application_branch
    FROM LoanApplication
    WHERE ApplicationID = p_application_id
    FOR UPDATE;

    -- Check whether the application is still pending

    IF v_current_status <> 'PENDING' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Application is already reviewed';
    END IF;

    -- Check whether the employee is a manager

    SELECT COUNT(*)
    INTO v_count
    FROM Manager
    WHERE EmployeeID = p_manager_id;

    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Employee is not a manager';
    END IF;

    -- Get manager branch

    SELECT BranchID
    INTO v_manager_branch
    FROM Employee
    WHERE EmployeeID = p_manager_id;

    -- Check whether manager belongs to the same branch

    IF v_manager_branch <> v_application_branch THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Manager belongs to a different branch';
    END IF;

    -- Update loan application

    UPDATE LoanApplication
    SET
        Status = UPPER(TRIM(p_decision)),
        ReviewedBy = p_manager_id,
        DecisionDate = CURDATE()
    WHERE ApplicationID = p_application_id;

    COMMIT;

    SELECT 'Loan application reviewed successfully' AS Message;

END $$

DELIMITER ;


-- =====================================================
-- PART 4: TEST CASES
-- =====================================================

-- Test 1: Apply for a loan
-- CALL ApplyLoan(
--     @demo_customer_id,
--     @demo_branch_id,
--     'PERSONAL',
--     200000.00,
--     'Home renovation'
-- );


-- Test 2: Review a loan application
-- Use an existing PENDING application ID.
-- CALL ReviewLoan(4, 1, 'REJECTED');


-- Test 3: Verify loan applications

SELECT * FROM LoanApplication;
