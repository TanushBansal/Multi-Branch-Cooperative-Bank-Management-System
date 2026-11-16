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

-- PROCEDURE 1: APPLY FOR A LOAN

DROP PROCEDURE IF EXISTS ApplyLoan;

DELIMITER $$

CREATE PROCEDURE ApplyLoan(
    IN p_customer_id INT,
    IN p_branch_id INT,
    IN p_loan_type VARCHAR(50),
    IN p_requested_amount DECIMAL(19,4),
    IN p_purpose VARCHAR(100)
)
BEGIN

    DECLARE v_count INT DEFAULT 0;
    DECLARE v_application_id INT;

    DECLARE v_started BOOLEAN DEFAULT FALSE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_started THEN
            ROLLBACK;
        END IF;
        RESIGNAL;
    END;

    IF p_requested_amount IS NULL OR p_requested_amount <= 0
       OR p_requested_amount > 9999999999999.99
       OR p_requested_amount <> ROUND(p_requested_amount, 2) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Requested amount must be positive whole cents within DECIMAL(15,2)';
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

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_started = TRUE;

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

    DECLARE v_started BOOLEAN DEFAULT FALSE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_started THEN
            ROLLBACK;
        END IF;
        RESIGNAL;
    END;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_started = TRUE;

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

    SELECT p_application_id AS ApplicationID,
           UPPER(TRIM(p_decision)) AS ApplicationStatus,
           CASE WHEN UPPER(TRIM(p_decision)) = 'APPROVED'
                THEN 'Application approved. Disburse it with payout account, interest rate and tenure to create the Loan record.'
                ELSE 'Application rejected. No loan or funds were created.'
           END AS Message;

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
    DECLARE v_account_type VARCHAR(10);
    DECLARE v_account_balance DECIMAL(15,2);
    DECLARE v_holder INT DEFAULT NULL;
    DECLARE v_transaction_id BIGINT;
    DECLARE v_loan_id INT;
    DECLARE v_loan_status VARCHAR(20);
    DECLARE v_sanctioned_account BIGINT;
    DECLARE v_sanctioned_amount DECIMAL(15,2);
    DECLARE v_sanctioned_rate DECIMAL(5,2);
    DECLARE v_sanctioned_tenure INT;

    DECLARE v_started BOOLEAN DEFAULT FALSE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_started THEN
            ROLLBACK;
        END IF;
        RESIGNAL;
    END;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_started = TRUE;

    -- Check application

    SELECT CustomerID, RequestedAmount, Status
    INTO v_customer_id, v_amount, v_status
    FROM LoanApplication
    WHERE ApplicationID = p_application_id
    FOR UPDATE;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan application does not exist';
    END IF;

    IF v_status <> 'APPROVED' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan application is not approved';
    END IF;

    -- Existing sanctions keep their loan identity, payout account and terms.

    SELECT LoanID, Status, PayoutAccountNo, SanctionAmount, InterestRate, TenureMonths
    INTO v_loan_id, v_loan_status, v_sanctioned_account, v_sanctioned_amount,
         v_sanctioned_rate, v_sanctioned_tenure
    FROM Loan
    WHERE ApplicationID = p_application_id
    FOR UPDATE;

    IF v_loan_id IS NOT NULL AND v_loan_status <> 'SANCTIONED' THEN
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

    IF v_loan_id IS NOT NULL THEN
        IF NOT (p_account_no <=> v_sanctioned_account)
           OR p_interest_rate <> v_sanctioned_rate
           OR p_tenure_months <> v_sanctioned_tenure THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Payout account, interest rate and tenure must match the sanction';
        END IF;

        SET v_amount = v_sanctioned_amount;
    END IF;

    -- Check payout account belongs to customer

    SELECT Balance, Status, AccountType
    INTO v_account_balance, v_account_status, v_account_type
    FROM Account
    WHERE AccountNo = p_account_no
    FOR UPDATE;

    IF v_account_status IS NULL OR v_account_status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Payout account is not active or does not exist';
    END IF;
    IF v_account_type = 'FD' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan payout requires a Savings or Current account';
    END IF;

    SELECT CustomerID INTO v_holder
    FROM AccountHolder
    WHERE AccountNo = p_account_no AND CustomerID = v_customer_id
    FOR SHARE;
    IF v_holder IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Account does not belong to customer';
    END IF;
    IF v_account_balance + v_amount > 9999999999999.99 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Disbursement would exceed the balance limit';
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

    IF v_loan_id IS NULL THEN
        INSERT INTO Loan
        (
            ApplicationID,
            PayoutAccountNo,
            SanctionDate,
            SanctionAmount,
            InterestRate,
            TenureMonths,
            Status,
            DisbursementTransactionID,
            DisbursementTransactionType,
            DisbursementTransactionStatus
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
            v_transaction_id,
            'LOAN_DISBURSEMENT',
            'SUCCESS'
        );

        SET v_loan_id = LAST_INSERT_ID();
    ELSE
        UPDATE Loan
        SET Status = 'ACTIVE',
            DisbursementTransactionID = v_transaction_id,
            DisbursementTransactionType = 'LOAN_DISBURSEMENT',
            DisbursementTransactionStatus = 'SUCCESS'
        WHERE LoanID = v_loan_id;
    END IF;

    COMMIT;

    SELECT
        v_loan_id AS LoanID,
        v_amount AS DisbursedAmount,
        p_application_id AS ApplicationID,
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
    DECLARE v_rate DECIMAL(7,2);
    DECLARE v_monthly_rate DECIMAL(16,12);
    DECLARE v_tenure INT;
    DECLARE v_schedule_start DATE;
    DECLARE v_loan_status VARCHAR(20);

    DECLARE v_emi DECIMAL(15,2);
    DECLARE v_balance DECIMAL(15,2);
    DECLARE v_interest DECIMAL(15,2);
    DECLARE v_principal DECIMAL(15,2);

    DECLARE v_i INT DEFAULT 1;

    DECLARE v_started BOOLEAN DEFAULT FALSE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_started THEN
            ROLLBACK;
        END IF;
        RESIGNAL;
    END;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_started = TRUE;

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
        COALESCE(DATE(t.TransactionDate), l.SanctionDate),
        l.Status
    INTO
        v_amount,
        v_rate,
        v_tenure,
        v_schedule_start,
        v_loan_status
    FROM Loan l
    LEFT JOIN BankTransaction t ON t.TransactionID = l.DisbursementTransactionID
    WHERE l.LoanID = p_loan_id
    FOR UPDATE OF l;

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
            DATE_ADD(v_schedule_start, INTERVAL v_i MONTH),
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
    IN p_amount DECIMAL(19,4)
)
BEGIN

    DECLARE v_account_no BIGINT;
    DECLARE v_loan_status VARCHAR(20);
    DECLARE v_balance DECIMAL(15,2);
    DECLARE v_account_type VARCHAR(10);
    DECLARE v_minimum_balance DECIMAL(15,2);
    DECLARE v_outstanding DECIMAL(15,2);

    DECLARE v_transaction_id BIGINT;
    DECLARE v_payment_id BIGINT;

    DECLARE v_installment_id INT;
    DECLARE v_installment_amount DECIMAL(15,2);
    DECLARE v_allocate DECIMAL(15,2);
    DECLARE v_remaining DECIMAL(15,2);

    DECLARE v_started BOOLEAN DEFAULT FALSE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_started THEN
            ROLLBACK;
        END IF;
        RESIGNAL;
    END;

    IF p_amount IS NULL OR p_amount <= 0 OR p_amount > 9999999999999.99
       OR p_amount <> ROUND(p_amount, 2) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Repayment amount must be positive whole cents within DECIMAL(15,2)';
    END IF;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_started = TRUE;

    -- Lock the loan before opening a consistent-read snapshot.

    SELECT PayoutAccountNo, Status
    INTO v_account_no, v_loan_status
    FROM Loan
    WHERE LoanID = p_loan_id
    FOR UPDATE;

    IF v_loan_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Loan does not exist';
    END IF;

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

    SELECT Balance, AccountType
    INTO v_balance, v_account_type
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

    IF v_account_type = 'SAVINGS' THEN
        SELECT MinimumBalance INTO v_minimum_balance
        FROM SavingsAccount WHERE AccountNo = v_account_no FOR UPDATE;
    ELSEIF v_account_type = 'CURRENT' THEN
        SELECT MinimumBalance INTO v_minimum_balance
        FROM CurrentAccount WHERE AccountNo = v_account_no FOR UPDATE;
    ELSE
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Repayment requires a Savings or Current account';
    END IF;
    IF v_minimum_balance IS NULL OR v_balance - p_amount < v_minimum_balance THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Repayment would violate the account minimum balance';
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
                LoanID,
                AllocatedAmount
            )
            VALUES
            (
                v_payment_id,
                v_installment_id,
                p_loan_id,
                v_allocate
            );

            SET v_remaining = v_remaining - v_allocate;

        END LOOP;

        CLOSE cur_installments;

    END;

    IF v_remaining <> 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Repayment could not be fully allocated';
    END IF;

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
        p_loan_id AS LoanID,
        IF(v_outstanding = 0, 'CLOSED', 'ACTIVE') AS LoanStatus,
        'Repayment recorded successfully' AS Message;

END $$

DELIMITER ;
