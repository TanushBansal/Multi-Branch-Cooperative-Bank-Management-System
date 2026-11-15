-- 05_loans.sql
-- Handles:
-- 1. Loan application
-- 2. Loan approval and rejection
-- 3. Loan disbursement
-- 4. EMI / installment generation
-- 5. Loan repayment
--
-- Run after:
-- 01_schema.sql
-- 02_constraints_triggers.sql

USE CooperativeBank;

-- PART 1: LOAN MODULE DEMONSTRATION DATASET

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


-- PART 2: VERIFY DEMONSTRATION DATASET

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

-- PART 3: LOAN PROCEDURES


-- PROCEDURE 1: APPLY FOR A LOAN

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

    IF p_requested_amount IS NULL OR p_requested_amount <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Requested amount must be positive';
    END IF;

    IF p_loan_type IS NULL OR TRIM(p_loan_type) = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan type cannot be empty';
    END IF;

    IF p_purpose IS NULL OR TRIM(p_purpose) = '' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan purpose cannot be empty';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM Customer
    WHERE CustomerID = p_customer_id;

    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Customer does not exist';
    END IF;

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


-- PROCEDURE 2: REVIEW A LOAN APPLICATION

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

    IF p_decision IS NULL OR UPPER(TRIM(p_decision)) NOT IN ('APPROVED', 'REJECTED') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid decision';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM LoanApplication
    WHERE ApplicationID = p_application_id;

    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan application does not exist';
    END IF;

    SELECT Status, BranchID
    INTO v_current_status, v_application_branch
    FROM LoanApplication
    WHERE ApplicationID = p_application_id
    FOR UPDATE;

    IF v_current_status <> 'PENDING' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Application is already reviewed';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM Manager
    WHERE EmployeeID = p_manager_id;

    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Employee is not a manager';
    END IF;

    SELECT BranchID
    INTO v_manager_branch
    FROM Employee
    WHERE EmployeeID = p_manager_id;

    IF v_manager_branch <> v_application_branch THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Manager belongs to a different branch';
    END IF;

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


-- PROCEDURE 3: DISBURSE A LOAN

DROP PROCEDURE IF EXISTS DisburseLoan;

DELIMITER $$

CREATE PROCEDURE DisburseLoan(
    IN p_application_id INT,
    IN p_account_no BIGINT,
    IN p_interest_rate DECIMAL(5,2),
    IN p_tenure_months INT
)
BEGIN

    DECLARE v_count INT DEFAULT 0;
    DECLARE v_customer_id INT;
    DECLARE v_amount DECIMAL(15,2);
    DECLARE v_status VARCHAR(20);
    DECLARE v_account_status VARCHAR(20);
    DECLARE v_transaction_id BIGINT;
    DECLARE v_loan_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Check application

    SELECT COUNT(*)
    INTO v_count
    FROM LoanApplication
    WHERE ApplicationID = p_application_id;

    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan application does not exist';
    END IF;

    SELECT CustomerID, RequestedAmount, Status
    INTO v_customer_id, v_amount, v_status
    FROM LoanApplication
    WHERE ApplicationID = p_application_id
    FOR UPDATE;

    IF v_status <> 'APPROVED' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan application is not approved';
    END IF;

    -- Check whether loan already exists

    SELECT COUNT(*)
    INTO v_count
    FROM Loan
    WHERE ApplicationID = p_application_id;

    IF v_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan has already been disbursed';
    END IF;

    -- Validate interest rate and tenure

    IF p_interest_rate IS NULL OR p_interest_rate < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid interest rate';
    END IF;

    IF p_tenure_months IS NULL OR p_tenure_months <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid loan tenure';
    END IF;

    -- Check payout account belongs to customer

    SELECT COUNT(*)
    INTO v_count
    FROM Account A
    JOIN AccountHolder AH ON A.AccountNo = AH.AccountNo
    WHERE A.AccountNo = p_account_no
    AND AH.CustomerID = v_customer_id;

    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Account does not belong to customer';
    END IF;

    SELECT Status
    INTO v_account_status
    FROM Account
    WHERE AccountNo = p_account_no
    FOR UPDATE;

    IF v_account_status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Payout account is not active';
    END IF;

    -- Create disbursement transaction

    INSERT INTO BankTransaction
    (
        AccountNo,
        TransactionType,
        Amount,
        Channel,
        Status,
        RequestID
    )
    VALUES
    (
        p_account_no,
        'LOAN_DISBURSEMENT',
        v_amount,
        'SYSTEM',
        'SUCCESS',
        UUID()
    );

    SET v_transaction_id = LAST_INSERT_ID();

    -- Credit customer account

    UPDATE Account
    SET Balance = Balance + v_amount
    WHERE AccountNo = p_account_no;

    -- Create loan record

    INSERT INTO Loan
    (
        ApplicationID,
        PayoutAccountNo,
        SanctionDate,
        SanctionAmount,
        InterestRate,
        TenureMonths,
        Status,
        DisbursementTransactionID
    )
    VALUES
    (
        p_application_id,
        p_account_no,
        CURDATE(),
        v_amount,
        p_interest_rate,
        p_tenure_months,
        'ACTIVE',
        v_transaction_id
    );

    SET v_loan_id = LAST_INSERT_ID();

    COMMIT;

    SELECT
        v_loan_id AS LoanID,
        v_amount AS DisbursedAmount,
        'Loan disbursed successfully' AS Message;

END $$

DELIMITER ;

-- PROCEDURE 4: GENERATE LOAN INSTALLMENTS

DROP PROCEDURE IF EXISTS GenerateInstallments;

DELIMITER $$

CREATE PROCEDURE GenerateInstallments(
    IN p_loan_id INT
)
BEGIN

    DECLARE v_count INT DEFAULT 0;
    DECLARE v_amount DECIMAL(15,2);
    DECLARE v_rate DECIMAL(10,8);
    DECLARE v_monthly_rate DECIMAL(10,8);
    DECLARE v_tenure INT;
    DECLARE v_sanction_date DATE;
    DECLARE v_loan_status VARCHAR(20);

    DECLARE v_emi DECIMAL(15,2);
    DECLARE v_balance DECIMAL(15,2);
    DECLARE v_interest DECIMAL(15,2);
    DECLARE v_principal DECIMAL(15,2);

    DECLARE v_i INT DEFAULT 1;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Check loan

    SELECT COUNT(*)
    INTO v_count
    FROM Loan
    WHERE LoanID = p_loan_id;

    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan does not exist';
    END IF;

    SELECT
        SanctionAmount,
        InterestRate,
        TenureMonths,
        SanctionDate,
        Status
    INTO
        v_amount,
        v_rate,
        v_tenure,
        v_sanction_date,
        v_loan_status
    FROM Loan
    WHERE LoanID = p_loan_id
    FOR UPDATE;

    IF v_loan_status NOT IN ('ACTIVE', 'SANCTIONED') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan is not active';
    END IF;

    -- Check whether installments already exist

    SELECT COUNT(*)
    INTO v_count
    FROM LoanInstallment
    WHERE LoanID = p_loan_id;

    IF v_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Installments already generated';
    END IF;

    SET v_monthly_rate = v_rate / 1200;

    -- Calculate EMI

    IF v_monthly_rate = 0 THEN

        SET v_emi = v_amount / v_tenure;

    ELSE

        SET v_emi =
            v_amount * v_monthly_rate *
            POW(1 + v_monthly_rate, v_tenure) /
            (POW(1 + v_monthly_rate, v_tenure) - 1);

    END IF;

    SET v_balance = v_amount;

    -- Generate monthly installments

    WHILE v_i <= v_tenure DO

        SET v_interest = ROUND(v_balance * v_monthly_rate, 2);

        IF v_i = v_tenure THEN
            SET v_principal = v_balance;
        ELSE
            SET v_principal = ROUND(v_emi - v_interest, 2);
        END IF;

        INSERT INTO LoanInstallment
        (
            LoanID,
            InstallmentNo,
            DueDate,
            PrincipalDue,
            InterestDue
        )
        VALUES
        (
            p_loan_id,
            v_i,
            DATE_ADD(v_sanction_date, INTERVAL v_i MONTH),
            v_principal,
            v_interest
        );

        SET v_balance = v_balance - v_principal;
        SET v_i = v_i + 1;

    END WHILE;

    COMMIT;

    SELECT
        p_loan_id AS LoanID,
        v_tenure AS InstallmentsGenerated,
        ROUND(v_emi, 2) AS MonthlyEMI,
        'Installments generated successfully' AS Message;

END $$

DELIMITER ;


-- PROCEDURE 5: REPAY A LOAN

DROP PROCEDURE IF EXISTS RepayLoan;

DELIMITER $$

CREATE PROCEDURE RepayLoan(
    IN p_loan_id INT,
    IN p_amount DECIMAL(15,2)
)
BEGIN

    DECLARE v_count INT DEFAULT 0;
    DECLARE v_account_no BIGINT;
    DECLARE v_loan_status VARCHAR(20);
    DECLARE v_balance DECIMAL(15,2);
    DECLARE v_outstanding DECIMAL(15,2);

    DECLARE v_transaction_id BIGINT;
    DECLARE v_payment_id BIGINT;

    DECLARE v_installment_id INT;
    DECLARE v_installment_amount DECIMAL(15,2);
    DECLARE v_allocate DECIMAL(15,2);
    DECLARE v_remaining DECIMAL(15,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Repayment amount must be positive';
    END IF;

    START TRANSACTION;

    -- Check loan

    SELECT COUNT(*)
    INTO v_count
    FROM Loan
    WHERE LoanID = p_loan_id;

    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan does not exist';
    END IF;

    SELECT PayoutAccountNo, Status
    INTO v_account_no, v_loan_status
    FROM Loan
    WHERE LoanID = p_loan_id
    FOR UPDATE;

    IF v_loan_status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan is not active';
    END IF;

    -- Calculate total outstanding amount

    SELECT
        COALESCE(
            SUM(
                LI.PrincipalDue + LI.InterestDue
                - COALESCE(PA.TotalPaid, 0)
            ),
            0
        )
    INTO v_outstanding
    FROM LoanInstallment LI
    LEFT JOIN (
        SELECT
            InstallmentID,
            SUM(AllocatedAmount) AS TotalPaid
        FROM PaymentAllocation
        GROUP BY InstallmentID
    ) PA ON LI.InstallmentID = PA.InstallmentID
    WHERE LI.LoanID = p_loan_id;

    IF v_outstanding <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No outstanding installments';
    END IF;

    IF p_amount > v_outstanding THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Repayment exceeds outstanding amount';
    END IF;

    -- Check account balance

    SELECT Balance
    INTO v_balance
    FROM Account
    WHERE AccountNo = v_account_no
    AND Status = 'ACTIVE'
    FOR UPDATE;

    IF v_balance IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Payout account is not active';
    END IF;

    IF v_balance < p_amount THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Insufficient account balance';
    END IF;

    -- Create repayment transaction

    INSERT INTO BankTransaction
    (
        AccountNo,
        TransactionType,
        Amount,
        Channel,
        Status,
        RequestID
    )
    VALUES
    (
        v_account_no,
        'LOAN_REPAYMENT',
        p_amount,
        'SYSTEM',
        'SUCCESS',
        UUID()
    );

    SET v_transaction_id = LAST_INSERT_ID();

    -- Debit customer account

    UPDATE Account
    SET Balance = Balance - p_amount
    WHERE AccountNo = v_account_no;

    -- Create repayment record

    INSERT INTO Repayment
    (
        LoanID,
        TransactionID,
        Amount
    )
    VALUES
    (
        p_loan_id,
        v_transaction_id,
        p_amount
    );

    SET v_payment_id = LAST_INSERT_ID();

    SET v_remaining = p_amount;

    -- Allocate repayment to oldest installments first

    BEGIN

        DECLARE cur_done INT DEFAULT 0;

        DECLARE cur_installments CURSOR FOR
            SELECT
                LI.InstallmentID,
                LI.PrincipalDue + LI.InterestDue
                - COALESCE(SUM(PA.AllocatedAmount), 0) AS RemainingAmount
            FROM LoanInstallment LI
            LEFT JOIN PaymentAllocation PA
                ON LI.InstallmentID = PA.InstallmentID
            WHERE LI.LoanID = p_loan_id
            GROUP BY
                LI.InstallmentID,
                LI.InstallmentNo,
                LI.PrincipalDue,
                LI.InterestDue
            HAVING RemainingAmount > 0
            ORDER BY LI.InstallmentNo;

        DECLARE CONTINUE HANDLER FOR NOT FOUND
            SET cur_done = 1;

        OPEN cur_installments;

        allocation_loop: LOOP

            FETCH cur_installments
            INTO v_installment_id, v_installment_amount;

            IF cur_done = 1 OR v_remaining <= 0 THEN
                LEAVE allocation_loop;
            END IF;

            IF v_remaining >= v_installment_amount THEN
                SET v_allocate = v_installment_amount;
            ELSE
                SET v_allocate = v_remaining;
            END IF;

            INSERT INTO PaymentAllocation
            (
                PaymentID,
                InstallmentID,
                AllocatedAmount
            )
            VALUES
            (
                v_payment_id,
                v_installment_id,
                v_allocate
            );

            SET v_remaining = v_remaining - v_allocate;

        END LOOP;

        CLOSE cur_installments;

    END;

    -- Close loan if fully repaid

    SELECT
        COALESCE(
            SUM(
                LI.PrincipalDue + LI.InterestDue
                - COALESCE(PA.TotalPaid, 0)
            ),
            0
        )
    INTO v_outstanding
    FROM LoanInstallment LI
    LEFT JOIN (
        SELECT
            InstallmentID,
            SUM(AllocatedAmount) AS TotalPaid
        FROM PaymentAllocation
        GROUP BY InstallmentID
    ) PA ON LI.InstallmentID = PA.InstallmentID
    WHERE LI.LoanID = p_loan_id;

    IF v_outstanding = 0 THEN
        UPDATE Loan
        SET Status = 'CLOSED'
        WHERE LoanID = p_loan_id;
    END IF;

    COMMIT;

    SELECT
        v_payment_id AS PaymentID,
        p_amount AS AmountPaid,
        v_outstanding AS RemainingAmount,
        'Repayment recorded successfully' AS Message;

END $$

DELIMITER ;


-- PART 4: VERIFICATION QUERIES

SELECT * FROM LoanApplication;
SELECT * FROM Loan;
SELECT * FROM LoanInstallment;
SELECT * FROM Repayment;
SELECT * FROM PaymentAllocation;


-- TEST CASES

-- 1. Apply for a loan:
-- CALL ApplyLoan(@demo_customer_id, @demo_branch_id,
--     'PERSONAL', 50000.00, 'Home renovation');

-- 2. Approve a pending application:
-- CALL ReviewLoan(6, 1, 'APPROVED');

-- 3. Disburse the approved loan:
-- CALL DisburseLoan(6, 9001000001, 12.00, 12);

-- 4. Generate installments:
-- CALL GenerateInstallments(2);

-- 5. Repay part of the loan:
-- CALL RepayLoan(2, 5000.00);
