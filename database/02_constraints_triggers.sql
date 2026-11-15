-- 02_constraints_triggers.sql
-- Additional constraints and triggers layered on top of 01_schema.sql.
-- Requires MySQL 8.0.16 or later.

USE CooperativeBank;

-- ---------------------------------------------------------------
-- A. Format checks on identifying information
-- ---------------------------------------------------------------

ALTER TABLE Customer
    ADD CONSTRAINT chk_customer_pan
    CHECK (REGEXP_LIKE(PAN, '^[A-Z]{5}[0-9]{4}[A-Z]$', 'c'));

ALTER TABLE Guarantor
    ADD CONSTRAINT chk_guarantor_pan
    CHECK (REGEXP_LIKE(PAN, '^[A-Z]{5}[0-9]{4}[A-Z]$', 'c'));

ALTER TABLE Branch
    ADD CONSTRAINT chk_branch_ifsc
    CHECK (REGEXP_LIKE(IFSC, '^[A-Z]{4}0[A-Z0-9]{6}$', 'c'));

-- A loan decision is recorded together or not at all: a pending
-- application has no reviewer and no decision date, a decided one has both.
ALTER TABLE LoanApplication
    ADD CONSTRAINT chk_application_decision
    CHECK (
        (Status = 'PENDING'  AND ReviewedBy IS NULL     AND DecisionDate IS NULL)
        OR
        (Status <> 'PENDING' AND ReviewedBy IS NOT NULL AND DecisionDate IS NOT NULL)
    );

DELIMITER $$

-- ---------------------------------------------------------------
-- B. Employee specialization is disjoint and partial.
-- Composite foreign keys and fixed EmployeeRole checks in 01_schema.sql
-- enforce role matching on inserts and updates. An employee with no role
-- has EmployeeRole NULL and cannot appear in either subtype.
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- C. Account type cannot change after account creation.
-- Subtype matching is enforced for inserts and updates by composite foreign
-- keys and fixed AccountType checks in 01_schema.sql.
-- ---------------------------------------------------------------

CREATE TRIGGER trg_account_type_immutable
BEFORE UPDATE ON Account
FOR EACH ROW
BEGIN
    IF NEW.AccountType <> OLD.AccountType THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'AccountType cannot be changed after account creation';
    END IF;
END$$

-- ---------------------------------------------------------------
-- D. A transfer detail row must belong to a TRANSFER transaction
-- ---------------------------------------------------------------

-- The composite foreign key and fixed TransactionType check in
-- 01_schema.sql enforce this on inserts, details updates, and parent updates.

-- ---------------------------------------------------------------
-- E. The reviewing manager must belong to the branch that received
--    the loan application
-- ---------------------------------------------------------------

CREATE TRIGGER trg_application_reviewer_ins
BEFORE INSERT ON LoanApplication
FOR EACH ROW
BEGIN
    IF NEW.ReviewedBy IS NOT NULL AND
       (SELECT BranchID FROM Employee WHERE EmployeeID = NEW.ReviewedBy) <> NEW.BranchID THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reviewer must be a manager of the receiving branch';
    END IF;
END$$

CREATE TRIGGER trg_application_reviewer_upd
BEFORE UPDATE ON LoanApplication
FOR EACH ROW
BEGIN
    IF NEW.ReviewedBy IS NOT NULL AND
       (SELECT BranchID FROM Employee WHERE EmployeeID = NEW.ReviewedBy) <> NEW.BranchID THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reviewer must be a manager of the receiving branch';
    END IF;
END$$

-- Preserve total specialization after an account has been opened.
-- Account-opening procedures and restricted grants prevent missing subtype
-- rows at creation; these triggers protect existing subtype rows.

CREATE TRIGGER trg_savingsaccount_keep_row
BEFORE DELETE ON SavingsAccount
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Account subtype cannot be deleted; close the account instead';
END$$

CREATE TRIGGER trg_savingsaccount_keep_owner
BEFORE UPDATE ON SavingsAccount
FOR EACH ROW
BEGIN
    IF NEW.AccountNo <> OLD.AccountNo THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Account subtype owner cannot change';
    END IF;
END$$

CREATE TRIGGER trg_currentaccount_keep_row
BEFORE DELETE ON CurrentAccount
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Account subtype cannot be deleted; close the account instead';
END$$

CREATE TRIGGER trg_currentaccount_keep_owner
BEFORE UPDATE ON CurrentAccount
FOR EACH ROW
BEGIN
    IF NEW.AccountNo <> OLD.AccountNo THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Account subtype owner cannot change';
    END IF;
END$$

CREATE TRIGGER trg_fixeddeposit_keep_row
BEFORE DELETE ON FixedDeposit
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Account subtype cannot be deleted; close the account instead';
END$$

CREATE TRIGGER trg_fixeddeposit_keep_owner
BEFORE UPDATE ON FixedDeposit
FOR EACH ROW
BEGIN
    IF NEW.AccountNo <> OLD.AccountNo THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Account subtype owner cannot change';
    END IF;
END$$

-- Approval requires a guarantor. New applications start pending because the
-- child FK requires an application to exist before its guarantors can be linked.
CREATE TRIGGER trg_application_guarantor_ins
BEFORE INSERT ON LoanApplication
FOR EACH ROW
BEGIN
    IF NEW.Status = 'APPROVED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Link a guarantor before approving the application';
    END IF;
END$$

CREATE TRIGGER trg_application_guarantor_upd
BEFORE UPDATE ON LoanApplication
FOR EACH ROW
BEGIN
    DECLARE v_GuarantorID INT DEFAULT NULL;
    IF NEW.Status = 'APPROVED' THEN
        IF NEW.ApprovalGuarantorID IS NULL THEN
            SELECT GuarantorID INTO v_GuarantorID FROM ApplicationGuarantor
            WHERE ApplicationID = NEW.ApplicationID ORDER BY GuarantorID LIMIT 1 FOR UPDATE;
            IF v_GuarantorID IS NULL THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'Approval requires at least one guarantor';
            END IF;
            SET NEW.ApprovalGuarantorID = v_GuarantorID;
        END IF;
        -- An explicit designation is validated by the composite FK, not by
        -- a snapshot read. It must identify a live link on this application.
    ELSE
        SET NEW.ApprovalGuarantorID = NULL;
    END IF;
END$$

CREATE TRIGGER trg_guarantor_keep_last_delete
BEFORE DELETE ON ApplicationGuarantor
FOR EACH ROW
BEGIN
    DECLARE v_Status VARCHAR(10);
    DECLARE v_DesignatedID INT;
    DECLARE v_OtherGuarantorID INT DEFAULT NULL;
    SELECT Status, ApprovalGuarantorID INTO v_Status, v_DesignatedID FROM LoanApplication
    WHERE ApplicationID = OLD.ApplicationID FOR UPDATE;
    IF v_Status = 'APPROVED' AND v_DesignatedID = OLD.GuarantorID THEN
        SELECT GuarantorID INTO v_OtherGuarantorID FROM ApplicationGuarantor
        WHERE ApplicationID = OLD.ApplicationID AND GuarantorID <> OLD.GuarantorID
        ORDER BY GuarantorID LIMIT 1;
        IF v_OtherGuarantorID IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Cannot remove the last guarantor of an approved application';
        END IF;
        -- This FK update validates and locks the alternative link. Even if a
        -- REPEATABLE READ snapshot selected a stale candidate, the FK rejects
        -- it; a stale read can never leave an approved application unprotected.
        UPDATE LoanApplication SET ApprovalGuarantorID = v_OtherGuarantorID
        WHERE ApplicationID = OLD.ApplicationID;
    END IF;
END$$

CREATE TRIGGER trg_guarantor_keep_last_update
BEFORE UPDATE ON ApplicationGuarantor
FOR EACH ROW
BEGIN
    DECLARE v_Status VARCHAR(10);
    DECLARE v_DesignatedID INT;
    DECLARE v_OtherGuarantorID INT DEFAULT NULL;
    IF NEW.ApplicationID <> OLD.ApplicationID OR NEW.GuarantorID <> OLD.GuarantorID THEN
        SELECT Status, ApprovalGuarantorID INTO v_Status, v_DesignatedID FROM LoanApplication
        WHERE ApplicationID = OLD.ApplicationID FOR UPDATE;
        IF v_Status = 'APPROVED' AND v_DesignatedID = OLD.GuarantorID THEN
            SELECT GuarantorID INTO v_OtherGuarantorID FROM ApplicationGuarantor
            WHERE ApplicationID = OLD.ApplicationID AND GuarantorID <> OLD.GuarantorID
            ORDER BY GuarantorID LIMIT 1;
            IF v_OtherGuarantorID IS NULL THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'Cannot move or replace the last guarantor; add its replacement first';
            END IF;
            UPDATE LoanApplication SET ApprovalGuarantorID = v_OtherGuarantorID
            WHERE ApplicationID = OLD.ApplicationID;
        END IF;
    END IF;
END$$

-- Keep transfer records and endpoints together after creation.
CREATE TRIGGER trg_transferdetails_keep_row
BEFORE DELETE ON TransferDetails
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Transfer details cannot be deleted';
END$$

CREATE TRIGGER trg_transferdetails_keep_identity
BEFORE UPDATE ON TransferDetails
FOR EACH ROW
BEGIN
    IF NEW.TransactionID <> OLD.TransactionID
       OR NEW.FromAccountNo <> OLD.FromAccountNo OR NEW.ToAccountNo <> OLD.ToAccountNo THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Transfer details cannot be reassigned';
    END IF;
END$$

-- A sanction cannot exceed the amount requested by its application.
-- Current locking reads coordinate loan changes with application changes;
-- a deadlock aborts one transaction and the caller can retry it.

CREATE TRIGGER trg_loan_requested_limit_insert
BEFORE INSERT ON Loan
FOR EACH ROW
BEGIN
    DECLARE v_RequestedAmount DECIMAL(15,2);
    SELECT RequestedAmount INTO v_RequestedAmount FROM LoanApplication
    WHERE ApplicationID = NEW.ApplicationID FOR SHARE;
    IF NEW.SanctionAmount > v_RequestedAmount THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Sanction amount cannot exceed the requested amount';
    END IF;
END$$

CREATE TRIGGER trg_loan_requested_limit_update
BEFORE UPDATE ON Loan
FOR EACH ROW
BEGIN
    DECLARE v_RequestedAmount DECIMAL(15,2);
    SELECT RequestedAmount INTO v_RequestedAmount FROM LoanApplication
    WHERE ApplicationID = NEW.ApplicationID FOR SHARE;
    IF NEW.SanctionAmount > v_RequestedAmount THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Sanction amount cannot exceed the requested amount';
    END IF;
END$$

CREATE TRIGGER trg_application_requested_limit_update
BEFORE UPDATE ON LoanApplication
FOR EACH ROW
BEGIN
    DECLARE v_SanctionAmount DECIMAL(15,2);
    IF NOT (NEW.RequestedAmount <=> OLD.RequestedAmount) THEN
        SELECT SanctionAmount INTO v_SanctionAmount FROM Loan
        WHERE ApplicationID = OLD.ApplicationID FOR SHARE;
        IF NEW.RequestedAmount < v_SanctionAmount THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Requested amount cannot fall below the existing sanction amount';
        END IF;
    END IF;
END$$

DELIMITER ;