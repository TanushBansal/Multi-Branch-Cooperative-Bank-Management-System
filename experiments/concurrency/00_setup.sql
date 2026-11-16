-- 00_setup.sql
-- Concurrency experiment:
-- Creates two demonstration procedures that differ in exactly one clause,
-- and helpers that open and restore two dedicated demonstration accounts.
-- The production procedures in 04_transactions.sql are not modified.

USE CooperativeBank;

DROP PROCEDURE IF EXISTS WithdrawUnsafe;
DROP PROCEDURE IF EXISTS WithdrawLocked;
DROP PROCEDURE IF EXISTS ConcurrencyDemoReset;

DELIMITER $$

-- UNSAFE: reads the balance without locking, waits, then writes an absolute
-- value computed from what it read. If another session changes the balance
-- during the wait, that change is overwritten (lost update).
CREATE PROCEDURE WithdrawUnsafe (
    IN p_AccountNo BIGINT,
    IN p_Amount DECIMAL(15,2),
    IN p_RequestID VARCHAR(100),
    IN p_DelaySeconds INT
)
BEGIN
    DECLARE v_Balance DECIMAL(15,2);
    DECLARE v_TransactionID BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Step 1: read the balance (plain read, no lock)
    SELECT Balance INTO v_Balance
    FROM Account
    WHERE AccountNo = p_AccountNo;

    IF v_Balance IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account does not exist';
    END IF;
    IF v_Balance < p_Amount THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient funds';
    END IF;

    -- Simulated processing time between the read and the write
    DO SLEEP(p_DelaySeconds);

    -- Step 2: write a value derived from the (possibly stale) read
    UPDATE Account
    SET Balance = v_Balance - p_Amount
    WHERE AccountNo = p_AccountNo;

    INSERT INTO BankTransaction
        (AccountNo, TransactionType, Amount, Channel, Status, RequestID)
    VALUES
        (p_AccountNo, 'WITHDRAWAL', p_Amount, 'BRANCH', 'PENDING', p_RequestID);
    SET v_TransactionID = LAST_INSERT_ID();

    UPDATE BankTransaction SET Status = 'SUCCESS'
    WHERE TransactionID = v_TransactionID;

    COMMIT;

    SELECT v_TransactionID       AS TransactionID,
           v_Balance             AS BalanceReadBySession,
           v_Balance - p_Amount  AS BalanceWrittenBySession;
END$$

-- LOCKED: identical to WithdrawUnsafe except for FOR UPDATE on the read.
-- The row stays locked until COMMIT, so a concurrent withdrawal waits and
-- then reads the up-to-date balance.
CREATE PROCEDURE WithdrawLocked (
    IN p_AccountNo BIGINT,
    IN p_Amount DECIMAL(15,2),
    IN p_RequestID VARCHAR(100),
    IN p_DelaySeconds INT
)
BEGIN
    DECLARE v_Balance DECIMAL(15,2);
    DECLARE v_TransactionID BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Step 1: read the balance and lock the row (the only difference)
    SELECT Balance INTO v_Balance
    FROM Account
    WHERE AccountNo = p_AccountNo
    FOR UPDATE;

    IF v_Balance IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account does not exist';
    END IF;
    IF v_Balance < p_Amount THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient funds';
    END IF;

    DO SLEEP(p_DelaySeconds);

    UPDATE Account
    SET Balance = v_Balance - p_Amount
    WHERE AccountNo = p_AccountNo;

    INSERT INTO BankTransaction
        (AccountNo, TransactionType, Amount, Channel, Status, RequestID)
    VALUES
        (p_AccountNo, 'WITHDRAWAL', p_Amount, 'BRANCH', 'PENDING', p_RequestID);
    SET v_TransactionID = LAST_INSERT_ID();

    UPDATE BankTransaction SET Status = 'SUCCESS'
    WHERE TransactionID = v_TransactionID;

    COMMIT;

    SELECT v_TransactionID       AS TransactionID,
           v_Balance             AS BalanceReadBySession,
           v_Balance - p_Amount  AS BalanceWrittenBySession;
END$$

-- Opens the demonstration account if it does not exist (Current account,
-- branch 1, customer 1, opening deposit 10000.00, minimum balance 0), or
-- restores an existing one: demonstration withdrawals are removed and the
-- balance returns to 10000.00, so the account again matches its ledger.
CREATE PROCEDURE ConcurrencyDemoReset (IN p_AccountNo BIGINT)
BEGIN
    IF p_AccountNo NOT IN (9100000001, 9100000002) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Use one of the demonstration accounts 9100000001 to 9100000002';
    END IF;

    IF EXISTS (SELECT 1 FROM Account WHERE AccountNo = p_AccountNo) THEN
        START TRANSACTION;
        DELETE FROM BankTransaction
        WHERE AccountNo = p_AccountNo
          AND TransactionType = 'WITHDRAWAL'
          AND RequestID LIKE 'cdemo-%';
        UPDATE Account SET Balance = 10000.00 WHERE AccountNo = p_AccountNo;
        COMMIT;
    ELSE
        CALL OpenCurrentAccount(p_AccountNo, 1, 1, CURDATE(), 0.00, 10000.00,
                                CONCAT('cdemo-open-', p_AccountNo));
    END IF;
END$$

DELIMITER ;

CALL ConcurrencyDemoReset(9100000001);
CALL ConcurrencyDemoReset(9100000002);

SELECT AccountNo, Balance FROM Account
WHERE AccountNo BETWEEN 9100000001 AND 9100000002 ORDER BY AccountNo;
