
USE CooperativeBank;

DELIMITER $$

CREATE PROCEDURE Deposit (
    IN p_AccountNo BIGINT,
    IN p_Amount DECIMAL(19,4),
    IN p_Channel VARCHAR(30),
    IN p_RequestID VARCHAR(100),
    OUT p_TransactionID BIGINT
)
BEGIN
    DECLARE v_Balance DECIMAL(15,2);
    DECLARE v_Status VARCHAR(10);
    DECLARE v_AccountType VARCHAR(10);
    DECLARE v_Started BOOLEAN DEFAULT FALSE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_Started THEN
            ROLLBACK;
        END IF;
        SET p_TransactionID = NULL;
        RESIGNAL;
    END;

    SET p_TransactionID = NULL;

    IF p_AccountNo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account number is required';
    END IF;
    IF p_Amount IS NULL OR p_Amount <= 0
       OR p_Amount > 9999999999999.99 OR p_Amount <> ROUND(p_Amount, 2) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Amount must be positive and contain whole cents within DECIMAL(15,2)';
    END IF;
    IF p_RequestID IS NULL OR CHAR_LENGTH(TRIM(p_RequestID)) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RequestID is required';
    END IF;

    -- SET TRANSACTION rejects an already active transaction, avoiding an
    -- implicit commit of the caller's work by START TRANSACTION.
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_Started = TRUE;

    SELECT Balance, Status, AccountType
    INTO v_Balance, v_Status, v_AccountType
    FROM Account WHERE AccountNo = p_AccountNo FOR UPDATE;

    IF v_Balance IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account does not exist';
    END IF;
    IF v_Status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account must be active';
    END IF;
    IF v_AccountType = 'FD' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ordinary deposits are not allowed for fixed deposits';
    END IF;
    IF v_Balance + p_Amount > 9999999999999.99 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Deposit would exceed the balance limit';
    END IF;

    INSERT INTO BankTransaction (AccountNo, TransactionType, Amount, Channel, Status, RequestID)
    VALUES (p_AccountNo, 'DEPOSIT', p_Amount, p_Channel, 'PENDING', p_RequestID);
    SET p_TransactionID = LAST_INSERT_ID();

    UPDATE Account SET Balance = Balance + p_Amount WHERE AccountNo = p_AccountNo;
    UPDATE BankTransaction SET Status = 'SUCCESS' WHERE TransactionID = p_TransactionID;

    COMMIT;
END$$

CREATE PROCEDURE Withdraw (
    IN p_AccountNo BIGINT,
    IN p_Amount DECIMAL(19,4),
    IN p_Channel VARCHAR(30),
    IN p_RequestID VARCHAR(100),
    OUT p_TransactionID BIGINT
)
BEGIN
    DECLARE v_Balance DECIMAL(15,2);
    DECLARE v_Status VARCHAR(10);
    DECLARE v_AccountType VARCHAR(10);
    DECLARE v_MinimumBalance DECIMAL(15,2);
    DECLARE v_Started BOOLEAN DEFAULT FALSE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_Started THEN
            ROLLBACK;
        END IF;
        SET p_TransactionID = NULL;
        RESIGNAL;
    END;

    SET p_TransactionID = NULL;

    IF p_AccountNo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account number is required';
    END IF;
    IF p_Amount IS NULL OR p_Amount <= 0
       OR p_Amount > 9999999999999.99 OR p_Amount <> ROUND(p_Amount, 2) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Amount must be positive and contain whole cents within DECIMAL(15,2)';
    END IF;
    IF p_RequestID IS NULL OR CHAR_LENGTH(TRIM(p_RequestID)) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RequestID is required';
    END IF;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_Started = TRUE;

    SELECT Balance, Status, AccountType
    INTO v_Balance, v_Status, v_AccountType
    FROM Account WHERE AccountNo = p_AccountNo FOR UPDATE;

    IF v_Balance IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account does not exist';
    END IF;
    IF v_Status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account must be active';
    END IF;

    IF v_AccountType = 'SAVINGS' THEN
        SELECT MinimumBalance INTO v_MinimumBalance
        FROM SavingsAccount WHERE AccountNo = p_AccountNo FOR UPDATE;
    ELSEIF v_AccountType = 'CURRENT' THEN
        SELECT MinimumBalance INTO v_MinimumBalance
        FROM CurrentAccount WHERE AccountNo = p_AccountNo FOR UPDATE;
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ordinary withdrawals are not allowed for fixed deposits';
    END IF;

    IF v_MinimumBalance IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account subtype record is missing';
    END IF;
    IF v_Balance - p_Amount < 0 OR v_Balance - p_Amount < v_MinimumBalance THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient funds or minimum balance would be violated';
    END IF;

    INSERT INTO BankTransaction (AccountNo, TransactionType, Amount, Channel, Status, RequestID)
    VALUES (p_AccountNo, 'WITHDRAWAL', p_Amount, p_Channel, 'PENDING', p_RequestID);
    SET p_TransactionID = LAST_INSERT_ID();

    UPDATE Account SET Balance = Balance - p_Amount WHERE AccountNo = p_AccountNo;
    UPDATE BankTransaction SET Status = 'SUCCESS' WHERE TransactionID = p_TransactionID;

    COMMIT;
END$$

CREATE PROCEDURE Transfer (
    IN p_FromAccountNo BIGINT,
    IN p_ToAccountNo BIGINT,
    IN p_Amount DECIMAL(19,4),
    IN p_Channel VARCHAR(30),
    IN p_RequestID VARCHAR(100),
    OUT p_TransactionID BIGINT
)
BEGIN
    DECLARE v_LockedAccountNo BIGINT;
    DECLARE v_FromBalance DECIMAL(15,2);
    DECLARE v_ToBalance DECIMAL(15,2);
    DECLARE v_FromStatus VARCHAR(10);
    DECLARE v_ToStatus VARCHAR(10);
    DECLARE v_FromType VARCHAR(10);
    DECLARE v_ToType VARCHAR(10);
    DECLARE v_MinimumBalance DECIMAL(15,2);
    DECLARE v_Started BOOLEAN DEFAULT FALSE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_Started THEN
            ROLLBACK;
        END IF;
        SET p_TransactionID = NULL;
        RESIGNAL;
    END;

    SET p_TransactionID = NULL;

    IF p_FromAccountNo IS NULL OR p_ToAccountNo IS NULL
       OR p_FromAccountNo = p_ToAccountNo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Two different account numbers are required';
    END IF;
    IF p_Amount IS NULL OR p_Amount <= 0
       OR p_Amount > 9999999999999.99 OR p_Amount <> ROUND(p_Amount, 2) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Amount must be positive and contain whole cents within DECIMAL(15,2)';
    END IF;
    IF p_RequestID IS NULL OR CHAR_LENGTH(TRIM(p_RequestID)) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RequestID is required';
    END IF;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_Started = TRUE;

    SELECT AccountNo INTO v_LockedAccountNo FROM Account
    WHERE AccountNo = LEAST(p_FromAccountNo, p_ToAccountNo) FOR UPDATE;
    IF v_LockedAccountNo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account does not exist';
    END IF;
    SET v_LockedAccountNo = NULL;
    SELECT AccountNo INTO v_LockedAccountNo FROM Account
    WHERE AccountNo = GREATEST(p_FromAccountNo, p_ToAccountNo) FOR UPDATE;
    IF v_LockedAccountNo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account does not exist';
    END IF;

    SELECT Balance, Status, AccountType
    INTO v_FromBalance, v_FromStatus, v_FromType
    FROM Account WHERE AccountNo = p_FromAccountNo FOR UPDATE;
    SELECT Balance, Status, AccountType
    INTO v_ToBalance, v_ToStatus, v_ToType
    FROM Account WHERE AccountNo = p_ToAccountNo FOR UPDATE;

    IF v_FromStatus <> 'ACTIVE' OR v_ToStatus <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Both accounts must be active';
    END IF;
    IF v_FromType = 'FD' OR v_ToType = 'FD' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ordinary transfers cannot use fixed deposit accounts';
    END IF;

    IF v_FromType = 'SAVINGS' THEN
        SELECT MinimumBalance INTO v_MinimumBalance
        FROM SavingsAccount WHERE AccountNo = p_FromAccountNo FOR UPDATE;
    ELSE
        SELECT MinimumBalance INTO v_MinimumBalance
        FROM CurrentAccount WHERE AccountNo = p_FromAccountNo FOR UPDATE;
    END IF;

    IF v_MinimumBalance IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Source account subtype record is missing';
    END IF;
    IF v_FromBalance - p_Amount < 0 OR v_FromBalance - p_Amount < v_MinimumBalance THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient funds or minimum balance would be violated';
    END IF;
    IF v_ToBalance + p_Amount > 9999999999999.99 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transfer would exceed the destination balance limit';
    END IF;

    INSERT INTO BankTransaction (AccountNo, TransactionType, Amount, Channel, Status, RequestID)
    VALUES (NULL, 'TRANSFER', p_Amount, p_Channel, 'PENDING', p_RequestID);
    SET p_TransactionID = LAST_INSERT_ID();

    INSERT INTO TransferDetails (TransactionID, FromAccountNo, ToAccountNo)
    VALUES (p_TransactionID, p_FromAccountNo, p_ToAccountNo);

    UPDATE Account SET Balance = Balance - p_Amount WHERE AccountNo = p_FromAccountNo;
    UPDATE Account SET Balance = Balance + p_Amount WHERE AccountNo = p_ToAccountNo;
    UPDATE BankTransaction SET Status = 'SUCCESS' WHERE TransactionID = p_TransactionID;

    COMMIT;
END$$

DELIMITER ;

