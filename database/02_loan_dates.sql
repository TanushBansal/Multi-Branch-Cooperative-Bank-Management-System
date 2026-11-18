USE CooperativeBank;

DELIMITER $$

CREATE PROCEDURE CheckLoanDates (
    IN p_LoanID INT, IN p_ApplicationID INT, IN p_SanctionDate DATE,
    IN p_DisbursementID BIGINT
)
BEGIN
    DECLARE v_DecisionDate DATETIME;
    DECLARE v_DisbursementDate DATETIME;
    DECLARE v_FirstDue DATE;
    DECLARE v_FirstPayment DATETIME;
    DECLARE v_FirstPaymentTransaction DATETIME;

    SELECT DecisionDate INTO v_DecisionDate FROM LoanApplication
    WHERE ApplicationID = p_ApplicationID FOR SHARE;
    IF p_SanctionDate < DATE(v_DecisionDate) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sanction cannot precede the approval date';
    END IF;

    IF p_DisbursementID IS NOT NULL THEN
        SELECT TransactionDate INTO v_DisbursementDate FROM BankTransaction
        WHERE TransactionID = p_DisbursementID FOR SHARE;
        IF DATE(v_DisbursementDate) < p_SanctionDate THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Disbursement cannot precede sanction';
        END IF;
    END IF;

    IF p_LoanID IS NOT NULL THEN
        SELECT MIN(DueDate) INTO v_FirstDue FROM LoanInstallment
        WHERE LoanID = p_LoanID FOR SHARE;
        SELECT MIN(PaidAt) INTO v_FirstPayment FROM Repayment
        WHERE LoanID = p_LoanID FOR SHARE;
        SELECT MIN(t.TransactionDate) INTO v_FirstPaymentTransaction
        FROM Repayment r JOIN BankTransaction t ON t.TransactionID = r.TransactionID
        WHERE r.LoanID = p_LoanID FOR SHARE;
        IF v_FirstDue <= COALESCE(DATE(v_DisbursementDate), p_SanctionDate) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Funding or sanction cannot reach or follow an installment due date';
        END IF;
        IF v_FirstPayment < COALESCE(v_DisbursementDate, TIMESTAMP(p_SanctionDate))
           OR v_FirstPaymentTransaction < COALESCE(v_DisbursementDate, TIMESTAMP(p_SanctionDate)) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Funding or sanction cannot follow an existing repayment';
        END IF;
    END IF;
END$$

CREATE PROCEDURE CheckInstallmentDate (IN p_LoanID INT, IN p_DueDate DATE)
BEGIN
    DECLARE v_SanctionDate DATE;
    DECLARE v_DisbursementID BIGINT;
    DECLARE v_DisbursementDate DATETIME;
    SELECT SanctionDate, DisbursementTransactionID INTO v_SanctionDate, v_DisbursementID
    FROM Loan WHERE LoanID = p_LoanID FOR SHARE;
    IF v_DisbursementID IS NOT NULL THEN
        SELECT TransactionDate INTO v_DisbursementDate FROM BankTransaction
        WHERE TransactionID = v_DisbursementID FOR SHARE;
    END IF;
    IF p_DueDate <= COALESCE(DATE(v_DisbursementDate), v_SanctionDate) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Installment must be due after the funding or sanction day';
    END IF;
END$$

CREATE PROCEDURE CheckRepaymentDates (
    IN p_LoanID INT, IN p_TransactionID BIGINT, IN p_PaidAt DATETIME
)
BEGIN
    DECLARE v_SanctionDate DATE;
    DECLARE v_DisbursementID BIGINT;
    DECLARE v_DisbursementDate DATETIME;
    DECLARE v_PaymentTransactionDate DATETIME;
    SELECT SanctionDate, DisbursementTransactionID INTO v_SanctionDate, v_DisbursementID
    FROM Loan WHERE LoanID = p_LoanID FOR SHARE;
    IF v_DisbursementID IS NOT NULL THEN
        SELECT TransactionDate INTO v_DisbursementDate FROM BankTransaction
        WHERE TransactionID = v_DisbursementID FOR SHARE;
    END IF;
    SELECT TransactionDate INTO v_PaymentTransactionDate FROM BankTransaction
    WHERE TransactionID = p_TransactionID FOR SHARE;
    IF p_PaidAt < COALESCE(v_DisbursementDate, TIMESTAMP(v_SanctionDate))
       OR v_PaymentTransactionDate < COALESCE(v_DisbursementDate, TIMESTAMP(v_SanctionDate)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Repayment cannot precede funding or sanction';
    END IF;
END$$

CREATE TRIGGER trg_loan_dates_insert
BEFORE INSERT ON Loan
FOR EACH ROW
BEGIN
    CALL CheckLoanDates(NULL, NEW.ApplicationID,
                        NEW.SanctionDate, NEW.DisbursementTransactionID);
END$$

CREATE TRIGGER trg_installment_dates_insert
BEFORE INSERT ON LoanInstallment
FOR EACH ROW
BEGIN
    CALL CheckInstallmentDate(NEW.LoanID, NEW.DueDate);
END$$

CREATE TRIGGER trg_repayment_dates_insert
BEFORE INSERT ON Repayment
FOR EACH ROW
BEGIN
    CALL CheckRepaymentDates(NEW.LoanID, NEW.TransactionID, NEW.PaidAt);
END$$

CREATE TRIGGER trg_loan_dates_update
BEFORE UPDATE ON Loan
FOR EACH ROW
BEGIN
    CALL CheckLoanDates(OLD.LoanID, NEW.ApplicationID,
                        NEW.SanctionDate, NEW.DisbursementTransactionID);
END$$

CREATE TRIGGER trg_installment_dates_update
BEFORE UPDATE ON LoanInstallment
FOR EACH ROW
BEGIN
    CALL CheckInstallmentDate(NEW.LoanID, NEW.DueDate);
END$$

CREATE TRIGGER trg_repayment_dates_update
BEFORE UPDATE ON Repayment
FOR EACH ROW
BEGIN
    CALL CheckRepaymentDates(NEW.LoanID, NEW.TransactionID, NEW.PaidAt);
END$$
CREATE TRIGGER trg_application_dates_update
BEFORE UPDATE ON LoanApplication
FOR EACH ROW
BEGIN
    DECLARE v_FirstSanction DATE;
    IF NOT (NEW.DecisionDate <=> OLD.DecisionDate) THEN
        SELECT MIN(SanctionDate) INTO v_FirstSanction FROM Loan
        WHERE ApplicationID = OLD.ApplicationID FOR SHARE;
        IF DATE(NEW.DecisionDate) > v_FirstSanction THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Decision cannot follow an existing loan sanction';
        END IF;
    END IF;
END$$

CREATE TRIGGER trg_loan_transaction_date_immutable
BEFORE UPDATE ON BankTransaction
FOR EACH ROW
BEGIN
    DECLARE v_LoanID INT DEFAULT NULL;
    DECLARE v_PaymentID BIGINT DEFAULT NULL;
    IF NEW.TransactionDate <> OLD.TransactionDate THEN
        SELECT LoanID INTO v_LoanID FROM Loan
        WHERE DisbursementTransactionID = OLD.TransactionID LIMIT 1 FOR SHARE;
        SELECT PaymentID INTO v_PaymentID FROM Repayment
        WHERE TransactionID = OLD.TransactionID LIMIT 1 FOR SHARE;
        IF v_LoanID IS NOT NULL OR v_PaymentID IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Linked loan transaction timestamps cannot change';
        END IF;
    END IF;
END$$

DELIMITER ;
