CREATE DATABASE IF NOT EXISTS CooperativeBank;
USE CooperativeBank;

CREATE TABLE Bank (
    BankID INT AUTO_INCREMENT PRIMARY KEY,
    BankName VARCHAR(100) NOT NULL
);

CREATE TABLE Branch (
    BranchID INT AUTO_INCREMENT PRIMARY KEY,
    BankID INT NOT NULL,
    IFSC VARCHAR(11) NOT NULL UNIQUE,
    BranchName VARCHAR(100) NOT NULL,
    Address VARCHAR(255),

    FOREIGN KEY (BankID) REFERENCES Bank(BankID)
);

CREATE TABLE Employee (
    EmployeeID INT AUTO_INCREMENT PRIMARY KEY,
    BranchID INT NOT NULL,
    EmployeeName VARCHAR(100) NOT NULL,
    EmployeeRole ENUM('MANAGER', 'CLERK') DEFAULT NULL,
    Phone VARCHAR(15),
    Email VARCHAR(100) UNIQUE,

    UNIQUE (EmployeeID, EmployeeRole),
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID)
);

CREATE TABLE Manager (
    EmployeeID INT PRIMARY KEY,
    EmployeeRole ENUM('MANAGER', 'CLERK') NOT NULL DEFAULT 'MANAGER',

    FOREIGN KEY (EmployeeID, EmployeeRole) REFERENCES Employee(EmployeeID, EmployeeRole),
    CHECK (EmployeeRole = 'MANAGER')
);

CREATE TABLE Clerk (
    EmployeeID INT PRIMARY KEY,
    EmployeeRole ENUM('MANAGER', 'CLERK') NOT NULL DEFAULT 'CLERK',

    FOREIGN KEY (EmployeeID, EmployeeRole) REFERENCES Employee(EmployeeID, EmployeeRole),
    CHECK (EmployeeRole = 'CLERK')
);

CREATE TABLE Customer (
    CustomerID INT AUTO_INCREMENT PRIMARY KEY,
    CustomerName VARCHAR(100) NOT NULL,
    Phone VARCHAR(15),
    Email VARCHAR(100),
    PAN VARCHAR(10) NOT NULL UNIQUE,
    Address VARCHAR(255)
);

CREATE TABLE Account (
    AccountNo BIGINT PRIMARY KEY,
    BranchID INT NOT NULL,
    AccountType ENUM('SAVINGS', 'CURRENT', 'FD') NOT NULL,
    Balance DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    Status ENUM('ACTIVE', 'FROZEN', 'CLOSED') NOT NULL DEFAULT 'ACTIVE',
    OpenedOn DATE NOT NULL,

    UNIQUE (AccountNo, AccountType),
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID),
    CHECK (Balance >= 0)
);

CREATE TABLE AccountHolder (
    CustomerID INT,
    AccountNo BIGINT,

    PRIMARY KEY (CustomerID, AccountNo),
    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    FOREIGN KEY (AccountNo) REFERENCES Account(AccountNo)
);

CREATE TABLE Nominee (
    AccountNo BIGINT,
    NomineeNo INT,
    NomineeName VARCHAR(100) NOT NULL,
    Relationship VARCHAR(50) NOT NULL,
    DateOfBirth DATE NOT NULL,
    Phone VARCHAR(15),
    Address VARCHAR(255),

    PRIMARY KEY (AccountNo, NomineeNo),
    FOREIGN KEY (AccountNo) REFERENCES Account(AccountNo)
);

CREATE TABLE SavingsAccount (
    AccountNo BIGINT PRIMARY KEY,
    AccountType ENUM('SAVINGS', 'CURRENT', 'FD') NOT NULL DEFAULT 'SAVINGS',
    InterestRate DECIMAL(5,2) NOT NULL,
    MinimumBalance DECIMAL(15,2) NOT NULL DEFAULT 0.00,

    FOREIGN KEY (AccountNo, AccountType) REFERENCES Account(AccountNo, AccountType),
    CHECK (AccountType = 'SAVINGS'),
    CHECK (InterestRate >= 0),
    CHECK (MinimumBalance >= 0)
);

CREATE TABLE CurrentAccount (
    AccountNo BIGINT PRIMARY KEY,
    AccountType ENUM('SAVINGS', 'CURRENT', 'FD') NOT NULL DEFAULT 'CURRENT',
    MinimumBalance DECIMAL(15,2) NOT NULL DEFAULT 0.00,

    FOREIGN KEY (AccountNo, AccountType) REFERENCES Account(AccountNo, AccountType),
    CHECK (AccountType = 'CURRENT'),
    CHECK (MinimumBalance >= 0)
);

CREATE TABLE FixedDeposit (
    AccountNo BIGINT PRIMARY KEY,
    AccountType ENUM('SAVINGS', 'CURRENT', 'FD') NOT NULL DEFAULT 'FD',
    Principal DECIMAL(15,2) NOT NULL,
    InterestRate DECIMAL(5,2) NOT NULL,
    StartDate DATE NOT NULL,
    MaturityDate DATE NOT NULL,

    FOREIGN KEY (AccountNo, AccountType) REFERENCES Account(AccountNo, AccountType),
    CHECK (AccountType = 'FD'),
    CHECK (Principal > 0),
    CHECK (InterestRate >= 0),
    CHECK (MaturityDate > StartDate)
);

CREATE TABLE BankTransaction (
    TransactionID BIGINT AUTO_INCREMENT PRIMARY KEY,
    AccountNo BIGINT,
    TransactionDate DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    TransactionType ENUM(
        'DEPOSIT',
        'WITHDRAWAL',
        'TRANSFER',
        'LOAN_DISBURSEMENT',
        'LOAN_REPAYMENT'
    ) NOT NULL,
    Amount DECIMAL(15,2) NOT NULL,
    Channel VARCHAR(30),
    Status ENUM('PENDING', 'SUCCESS', 'FAILED')
        NOT NULL DEFAULT 'PENDING',
    RequestID VARCHAR(100) NOT NULL UNIQUE,

    UNIQUE (TransactionID, TransactionType),
    UNIQUE (TransactionID, AccountNo, Amount, TransactionType, Status),
    UNIQUE (TransactionID, Amount, TransactionType, Status),
    FOREIGN KEY (AccountNo) REFERENCES Account(AccountNo),
    CHECK (Amount > 0),
    CHECK (
        (TransactionType = 'TRANSFER' AND AccountNo IS NULL)
        OR
        (TransactionType <> 'TRANSFER' AND AccountNo IS NOT NULL)
    )
);

CREATE TABLE TransferDetails (
    TransactionID BIGINT PRIMARY KEY,
    TransactionType ENUM(
        'DEPOSIT',
        'WITHDRAWAL',
        'TRANSFER',
        'LOAN_DISBURSEMENT',
        'LOAN_REPAYMENT'
    ) NOT NULL DEFAULT 'TRANSFER',
    FromAccountNo BIGINT NOT NULL,
    ToAccountNo BIGINT NOT NULL,

    FOREIGN KEY (TransactionID, TransactionType)
        REFERENCES BankTransaction(TransactionID, TransactionType),
    FOREIGN KEY (FromAccountNo) REFERENCES Account(AccountNo),
    FOREIGN KEY (ToAccountNo) REFERENCES Account(AccountNo),
    CHECK (TransactionType = 'TRANSFER'),
    CHECK (FromAccountNo <> ToAccountNo)
);

CREATE TABLE LoanApplication (
    ApplicationID INT AUTO_INCREMENT PRIMARY KEY,
    CustomerID INT NOT NULL,
    BranchID INT NOT NULL,
    ApplicationDate DATE NOT NULL,
    LoanType VARCHAR(50) NOT NULL,
    RequestedAmount DECIMAL(15,2) NOT NULL,
    Purpose VARCHAR(255),
    Status ENUM('PENDING', 'APPROVED', 'REJECTED')
        NOT NULL DEFAULT 'PENDING',
    ReviewedBy INT,
    DecisionDate DATETIME,
    ApprovalGuarantorID INT,

    UNIQUE (ApplicationID, Status),
    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID),
    FOREIGN KEY (ReviewedBy) REFERENCES Manager(EmployeeID),
    CHECK (DecisionDate IS NULL OR DATE(DecisionDate) >= ApplicationDate),
    CHECK (RequestedAmount > 0)
);

CREATE TABLE Guarantor (
    GuarantorID INT AUTO_INCREMENT PRIMARY KEY,
    GuarantorName VARCHAR(100) NOT NULL,
    Phone VARCHAR(15),
    PAN VARCHAR(10) NOT NULL UNIQUE,
    Address VARCHAR(255)
);

CREATE TABLE ApplicationGuarantor (
    ApplicationID INT,
    GuarantorID INT,

    PRIMARY KEY (ApplicationID, GuarantorID),
    FOREIGN KEY (ApplicationID)
        REFERENCES LoanApplication(ApplicationID),
    FOREIGN KEY (GuarantorID) REFERENCES Guarantor(GuarantorID)
);

ALTER TABLE LoanApplication
    ADD FOREIGN KEY (ApplicationID, ApprovalGuarantorID)
        REFERENCES ApplicationGuarantor(ApplicationID, GuarantorID),
    ADD CHECK (
        (Status = 'APPROVED' AND ApprovalGuarantorID IS NOT NULL)
        OR (Status <> 'APPROVED' AND ApprovalGuarantorID IS NULL)
    );

CREATE TABLE Loan (
    LoanID INT AUTO_INCREMENT PRIMARY KEY,
    ApplicationID INT NOT NULL UNIQUE,
    ApplicationStatus ENUM('PENDING', 'APPROVED', 'REJECTED') NOT NULL DEFAULT 'APPROVED',
    PayoutAccountNo BIGINT NOT NULL,
    SanctionDate DATE NOT NULL,
    SanctionAmount DECIMAL(15,2) NOT NULL,
    InterestRate DECIMAL(5,2) NOT NULL,
    TenureMonths INT NOT NULL,
    Status ENUM('SANCTIONED', 'ACTIVE', 'CLOSED', 'DEFAULTED')
        NOT NULL DEFAULT 'SANCTIONED',
    DisbursementTransactionID BIGINT UNIQUE,
    DisbursementTransactionType ENUM(
        'DEPOSIT', 'WITHDRAWAL', 'TRANSFER', 'LOAN_DISBURSEMENT', 'LOAN_REPAYMENT'
    ) DEFAULT NULL,
    DisbursementTransactionStatus ENUM('PENDING', 'SUCCESS', 'FAILED') DEFAULT NULL,

    FOREIGN KEY (ApplicationID, ApplicationStatus)
        REFERENCES LoanApplication(ApplicationID, Status),
    FOREIGN KEY (PayoutAccountNo) REFERENCES Account(AccountNo),
    FOREIGN KEY (DisbursementTransactionID, PayoutAccountNo, SanctionAmount,
                 DisbursementTransactionType, DisbursementTransactionStatus)
        REFERENCES BankTransaction(TransactionID, AccountNo, Amount, TransactionType, Status),
    CHECK (ApplicationStatus = 'APPROVED'),
    CHECK (
        (DisbursementTransactionID IS NULL AND DisbursementTransactionType IS NULL
         AND DisbursementTransactionStatus IS NULL)
        OR
        (DisbursementTransactionID IS NOT NULL AND DisbursementTransactionType IS NOT NULL
         AND DisbursementTransactionStatus IS NOT NULL
         AND DisbursementTransactionType = 'LOAN_DISBURSEMENT'
         AND DisbursementTransactionStatus = 'SUCCESS')
    ),
    CHECK (
        (Status = 'SANCTIONED' AND DisbursementTransactionID IS NULL)
        OR (Status <> 'SANCTIONED' AND DisbursementTransactionID IS NOT NULL)
    ),
    CHECK (SanctionAmount > 0),
    CHECK (InterestRate >= 0),
    CHECK (TenureMonths > 0)
);

CREATE TABLE LoanInstallment (
    InstallmentID INT AUTO_INCREMENT PRIMARY KEY,
    LoanID INT NOT NULL,
    InstallmentNo INT NOT NULL,
    DueDate DATE NOT NULL,
    PrincipalDue DECIMAL(15,2) NOT NULL,
    InterestDue DECIMAL(15,2) NOT NULL,

    UNIQUE (LoanID, InstallmentNo),
    UNIQUE (InstallmentID, LoanID),
    FOREIGN KEY (LoanID) REFERENCES Loan(LoanID),
    CHECK (InstallmentNo > 0),
    CHECK (PrincipalDue >= 0),
    CHECK (InterestDue >= 0)
);

CREATE TABLE Repayment (
    PaymentID BIGINT AUTO_INCREMENT PRIMARY KEY,
    LoanID INT NOT NULL,
    TransactionID BIGINT NOT NULL UNIQUE,
    PaidAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Amount DECIMAL(15,2) NOT NULL,
    TransactionType ENUM(
        'DEPOSIT', 'WITHDRAWAL', 'TRANSFER', 'LOAN_DISBURSEMENT', 'LOAN_REPAYMENT'
    ) NOT NULL DEFAULT 'LOAN_REPAYMENT',
    TransactionStatus ENUM('PENDING', 'SUCCESS', 'FAILED') NOT NULL DEFAULT 'SUCCESS',

    UNIQUE (PaymentID, LoanID),
    FOREIGN KEY (LoanID) REFERENCES Loan(LoanID),
    FOREIGN KEY (TransactionID, Amount, TransactionType, TransactionStatus)
        REFERENCES BankTransaction(TransactionID, Amount, TransactionType, Status),
    CHECK (TransactionType = 'LOAN_REPAYMENT'),
    CHECK (TransactionStatus = 'SUCCESS'),
    CHECK (Amount > 0)
);

CREATE TABLE PaymentAllocation (
    PaymentID BIGINT,
    InstallmentID INT,
    LoanID INT NOT NULL,
    AllocatedAmount DECIMAL(15,2) NOT NULL,

    PRIMARY KEY (PaymentID, InstallmentID),
    FOREIGN KEY (PaymentID, LoanID) REFERENCES Repayment(PaymentID, LoanID),
    FOREIGN KEY (InstallmentID, LoanID)
        REFERENCES LoanInstallment(InstallmentID, LoanID),
    CHECK (AllocatedAmount > 0)
);
