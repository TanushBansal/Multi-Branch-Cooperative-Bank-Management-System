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
    Phone VARCHAR(15),
    Email VARCHAR(100) UNIQUE,

    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID)
);

CREATE TABLE Manager (
    EmployeeID INT PRIMARY KEY,

    FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID)
);

CREATE TABLE Clerk (
    EmployeeID INT PRIMARY KEY,

    FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID)
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
    Status ENUM('ACTIVE', 'FROZEN', 'CLOSED')
        NOT NULL DEFAULT 'ACTIVE',
    OpenedOn DATE NOT NULL,

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

CREATE TABLE SavingsAccount (
    AccountNo BIGINT PRIMARY KEY,
    InterestRate DECIMAL(5,2) NOT NULL,
    MinimumBalance DECIMAL(15,2) NOT NULL DEFAULT 0.00,

    FOREIGN KEY (AccountNo) REFERENCES Account(AccountNo),
    CHECK (InterestRate >= 0),
    CHECK (MinimumBalance >= 0)
);

CREATE TABLE CurrentAccount (
    AccountNo BIGINT PRIMARY KEY,
    MinimumBalance DECIMAL(15,2) NOT NULL DEFAULT 0.00,

    FOREIGN KEY (AccountNo) REFERENCES Account(AccountNo),
    CHECK (MinimumBalance >= 0)
);

CREATE TABLE FixedDeposit (
    AccountNo BIGINT PRIMARY KEY,
    Principal DECIMAL(15,2) NOT NULL,
    InterestRate DECIMAL(5,2) NOT NULL,
    StartDate DATE NOT NULL,
    MaturityDate DATE NOT NULL,

    FOREIGN KEY (AccountNo) REFERENCES Account(AccountNo),
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
    FromAccountNo BIGINT NOT NULL,
    ToAccountNo BIGINT NOT NULL,

    FOREIGN KEY (TransactionID)
        REFERENCES BankTransaction(TransactionID),
    FOREIGN KEY (FromAccountNo) REFERENCES Account(AccountNo),
    FOREIGN KEY (ToAccountNo) REFERENCES Account(AccountNo),
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

    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    FOREIGN KEY (BranchID) REFERENCES Branch(BranchID),
    FOREIGN KEY (ReviewedBy) REFERENCES Manager(EmployeeID),
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

CREATE TABLE Loan (
    LoanID INT AUTO_INCREMENT PRIMARY KEY,
    ApplicationID INT NOT NULL UNIQUE,
    PayoutAccountNo BIGINT NOT NULL,
    SanctionDate DATE NOT NULL,
    SanctionAmount DECIMAL(15,2) NOT NULL,
    InterestRate DECIMAL(5,2) NOT NULL,
    TenureMonths INT NOT NULL,
    Status ENUM('SANCTIONED', 'ACTIVE', 'CLOSED', 'DEFAULTED')
        NOT NULL DEFAULT 'SANCTIONED',
    DisbursementTransactionID BIGINT UNIQUE,

    FOREIGN KEY (ApplicationID)
        REFERENCES LoanApplication(ApplicationID),
    FOREIGN KEY (PayoutAccountNo) REFERENCES Account(AccountNo),
    FOREIGN KEY (DisbursementTransactionID)
        REFERENCES BankTransaction(TransactionID),
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

    FOREIGN KEY (LoanID) REFERENCES Loan(LoanID),
    FOREIGN KEY (TransactionID)
        REFERENCES BankTransaction(TransactionID),
    CHECK (Amount > 0)
);

CREATE TABLE PaymentAllocation (
    PaymentID BIGINT,
    InstallmentID INT,
    AllocatedAmount DECIMAL(15,2) NOT NULL,

    PRIMARY KEY (PaymentID, InstallmentID),
    FOREIGN KEY (PaymentID) REFERENCES Repayment(PaymentID),
    FOREIGN KEY (InstallmentID)
        REFERENCES LoanInstallment(InstallmentID),
    CHECK (AllocatedAmount > 0)
);
