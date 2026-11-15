-- Create accounts through these procedures using the restricted application role.
-- Each call creates the account, its subtype, and its first holder atomically.
-- Positive opening funds are recorded as a successful DEPOSIT; zero-funded
-- Savings/Current accounts are allowed only when MinimumBalance is zero.
-- Calls own their transactions and must run outside an existing transaction.

USE CooperativeBank;

DELIMITER $$

CREATE PROCEDURE OpenSavingsAccount (
    IN p_AccountNo BIGINT,
    IN p_BranchID INT,
    IN p_CustomerID INT,
    IN p_OpenedOn DATE,
    IN p_InterestRate DECIMAL(5,2),
    IN p_MinimumBalance DECIMAL(15,2),
    IN p_OpeningAmount DECIMAL(19,4),
    IN p_RequestID VARCHAR(100)
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_Started BOOLEAN DEFAULT FALSE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_Started THEN
            ROLLBACK;
        END IF;
        RESIGNAL;
    END;

    IF p_OpeningAmount IS NULL OR p_OpeningAmount < 0
       OR p_OpeningAmount > 9999999999999.99 OR p_OpeningAmount <> ROUND(p_OpeningAmount, 2) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid opening amount';
    END IF;
    IF p_MinimumBalance IS NULL OR p_MinimumBalance < 0 OR p_OpeningAmount < p_MinimumBalance THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Opening amount must meet the minimum balance';
    END IF;
    IF p_OpeningAmount > 0 AND (p_RequestID IS NULL OR CHAR_LENGTH(TRIM(p_RequestID)) = 0) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RequestID is required for opening funds';
    END IF;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_Started = TRUE;

    INSERT INTO Account (AccountNo, BranchID, AccountType, Balance, OpenedOn)
    VALUES (p_AccountNo, p_BranchID, 'SAVINGS', p_OpeningAmount, p_OpenedOn);

    INSERT INTO SavingsAccount (AccountNo, InterestRate, MinimumBalance)
    VALUES (p_AccountNo, p_InterestRate, p_MinimumBalance);

    INSERT INTO AccountHolder (CustomerID, AccountNo) VALUES (p_CustomerID, p_AccountNo);

    IF p_OpeningAmount > 0 THEN
        INSERT INTO BankTransaction
            (AccountNo, TransactionDate, TransactionType, Amount, Channel, Status, RequestID)
        VALUES (p_AccountNo, p_OpenedOn, 'DEPOSIT', p_OpeningAmount, 'BRANCH', 'SUCCESS', p_RequestID);
    END IF;

    COMMIT;
END$$

CREATE PROCEDURE OpenCurrentAccount (
    IN p_AccountNo BIGINT,
    IN p_BranchID INT,
    IN p_CustomerID INT,
    IN p_OpenedOn DATE,
    IN p_MinimumBalance DECIMAL(15,2),
    IN p_OpeningAmount DECIMAL(19,4),
    IN p_RequestID VARCHAR(100)
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_Started BOOLEAN DEFAULT FALSE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_Started THEN
            ROLLBACK;
        END IF;
        RESIGNAL;
    END;

    IF p_OpeningAmount IS NULL OR p_OpeningAmount < 0
       OR p_OpeningAmount > 9999999999999.99 OR p_OpeningAmount <> ROUND(p_OpeningAmount, 2) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid opening amount';
    END IF;
    IF p_MinimumBalance IS NULL OR p_MinimumBalance < 0 OR p_OpeningAmount < p_MinimumBalance THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Opening amount must meet the minimum balance';
    END IF;
    IF p_OpeningAmount > 0 AND (p_RequestID IS NULL OR CHAR_LENGTH(TRIM(p_RequestID)) = 0) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RequestID is required for opening funds';
    END IF;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_Started = TRUE;

    INSERT INTO Account (AccountNo, BranchID, AccountType, Balance, OpenedOn)
    VALUES (p_AccountNo, p_BranchID, 'CURRENT', p_OpeningAmount, p_OpenedOn);

    INSERT INTO CurrentAccount (AccountNo, MinimumBalance)
    VALUES (p_AccountNo, p_MinimumBalance);

    INSERT INTO AccountHolder (CustomerID, AccountNo) VALUES (p_CustomerID, p_AccountNo);

    IF p_OpeningAmount > 0 THEN
        INSERT INTO BankTransaction
            (AccountNo, TransactionDate, TransactionType, Amount, Channel, Status, RequestID)
        VALUES (p_AccountNo, p_OpenedOn, 'DEPOSIT', p_OpeningAmount, 'BRANCH', 'SUCCESS', p_RequestID);
    END IF;

    COMMIT;
END$$

CREATE PROCEDURE OpenFixedDeposit (
    IN p_AccountNo BIGINT,
    IN p_BranchID INT,
    IN p_CustomerID INT,
    IN p_StartDate DATE,
    IN p_MaturityDate DATE,
    IN p_Principal DECIMAL(19,4),
    IN p_InterestRate DECIMAL(5,2),
    IN p_RequestID VARCHAR(100)
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_Started BOOLEAN DEFAULT FALSE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_Started THEN
            ROLLBACK;
        END IF;
        RESIGNAL;
    END;

    IF p_Principal IS NULL OR p_Principal <= 0
       OR p_Principal > 9999999999999.99 OR p_Principal <> ROUND(p_Principal, 2) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid opening amount';
    END IF;
    IF p_Principal > 0 AND (p_RequestID IS NULL OR CHAR_LENGTH(TRIM(p_RequestID)) = 0) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RequestID is required for opening funds';
    END IF;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_Started = TRUE;

    INSERT INTO Account (AccountNo, BranchID, AccountType, Balance, OpenedOn)
    VALUES (p_AccountNo, p_BranchID, 'FD', p_Principal, p_StartDate);

    INSERT INTO FixedDeposit (AccountNo, Principal, InterestRate, StartDate, MaturityDate)
    VALUES (p_AccountNo, p_Principal, p_InterestRate, p_StartDate, p_MaturityDate);

    INSERT INTO AccountHolder (CustomerID, AccountNo) VALUES (p_CustomerID, p_AccountNo);

    IF p_Principal > 0 THEN
        INSERT INTO BankTransaction
            (AccountNo, TransactionDate, TransactionType, Amount, Channel, Status, RequestID)
        VALUES (p_AccountNo, p_StartDate, 'DEPOSIT', p_Principal, 'BRANCH', 'SUCCESS', p_RequestID);
    END IF;

    COMMIT;
END$$

DELIMITER ;
