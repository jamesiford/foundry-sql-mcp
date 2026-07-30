:setvar DatabaseName "TransferDemo"

USE [$(DatabaseName)];
GO

IF OBJECT_ID(N'dbo.Client', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Client
    (
        ClientId int NOT NULL CONSTRAINT PK_Client PRIMARY KEY,
        ClientCode nvarchar(32) NOT NULL CONSTRAINT UQ_Client_ClientCode UNIQUE,
        DisplayName nvarchar(120) NOT NULL,
        Segment nvarchar(40) NOT NULL,
        CreatedAt datetime2(0) NOT NULL,
        UpdatedAt datetime2(0) NOT NULL
    );
END;
GO

IF OBJECT_ID(N'dbo.Household', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Household
    (
        HouseholdId int NOT NULL CONSTRAINT PK_Household PRIMARY KEY,
        HouseholdCode nvarchar(32) NOT NULL CONSTRAINT UQ_Household_HouseholdCode UNIQUE,
        HouseholdName nvarchar(120) NOT NULL,
        PrimaryClientId int NOT NULL,
        UpdatedAt datetime2(0) NOT NULL,
        CONSTRAINT FK_Household_Client FOREIGN KEY (PrimaryClientId) REFERENCES dbo.Client(ClientId)
    );
END;
GO

IF OBJECT_ID(N'dbo.Advisor', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Advisor
    (
        AdvisorId int NOT NULL CONSTRAINT PK_Advisor PRIMARY KEY,
        AdvisorCode nvarchar(32) NOT NULL CONSTRAINT UQ_Advisor_AdvisorCode UNIQUE,
        DisplayName nvarchar(120) NOT NULL,
        Region nvarchar(40) NOT NULL,
        UpdatedAt datetime2(0) NOT NULL
    );
END;
GO

IF OBJECT_ID(N'dbo.Account', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Account
    (
        AccountId int NOT NULL CONSTRAINT PK_Account PRIMARY KEY,
        AccountCode nvarchar(32) NOT NULL CONSTRAINT UQ_Account_AccountCode UNIQUE,
        ClientId int NOT NULL,
        HouseholdId int NOT NULL,
        AdvisorId int NOT NULL,
        AccountType nvarchar(40) NOT NULL,
        Custodian nvarchar(80) NOT NULL,
        MarketValue decimal(19, 2) NOT NULL,
        Status nvarchar(30) NOT NULL,
        UpdatedAt datetime2(0) NOT NULL,
        CONSTRAINT FK_Account_Client FOREIGN KEY (ClientId) REFERENCES dbo.Client(ClientId),
        CONSTRAINT FK_Account_Household FOREIGN KEY (HouseholdId) REFERENCES dbo.Household(HouseholdId),
        CONSTRAINT FK_Account_Advisor FOREIGN KEY (AdvisorId) REFERENCES dbo.Advisor(AdvisorId)
    );
END;
GO

IF OBJECT_ID(N'dbo.AssetTransfer', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AssetTransfer
    (
        TransferId int NOT NULL CONSTRAINT PK_AssetTransfer PRIMARY KEY,
        TransferCode nvarchar(32) NOT NULL CONSTRAINT UQ_AssetTransfer_TransferCode UNIQUE,
        AccountId int NOT NULL,
        SourceInstitution nvarchar(100) NOT NULL,
        TransferType nvarchar(40) NOT NULL,
        RequestedAmount decimal(19, 2) NOT NULL,
        RequestedDate date NOT NULL,
        ExpectedCompletionDate date NOT NULL,
        CompletedDate date NULL,
        CurrentStatus nvarchar(40) NOT NULL,
        CurrentStage nvarchar(40) NOT NULL,
        Priority nvarchar(20) NOT NULL,
        Summary nvarchar(500) NOT NULL,
        IsDeleted bit NOT NULL CONSTRAINT DF_AssetTransfer_IsDeleted DEFAULT (0),
        UpdatedAt datetime2(0) NOT NULL,
        CONSTRAINT FK_AssetTransfer_Account FOREIGN KEY (AccountId) REFERENCES dbo.Account(AccountId)
    );
END;
GO

IF OBJECT_ID(N'dbo.TransferStatusHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.TransferStatusHistory
    (
        TransferStatusHistoryId int NOT NULL CONSTRAINT PK_TransferStatusHistory PRIMARY KEY,
        TransferId int NOT NULL,
        Status nvarchar(40) NOT NULL,
        Stage nvarchar(40) NOT NULL,
        StatusDate datetime2(0) NOT NULL,
        Detail nvarchar(300) NOT NULL,
        CONSTRAINT FK_TransferStatusHistory_Transfer FOREIGN KEY (TransferId) REFERENCES dbo.AssetTransfer(TransferId)
    );
END;
GO

IF OBJECT_ID(N'dbo.DocumentChecklist', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DocumentChecklist
    (
        DocumentChecklistId int NOT NULL CONSTRAINT PK_DocumentChecklist PRIMARY KEY,
        TransferId int NOT NULL,
        DocumentType nvarchar(80) NOT NULL,
        IsRequired bit NOT NULL,
        IsReceived bit NOT NULL,
        ReceivedDate date NULL,
        UpdatedAt datetime2(0) NOT NULL,
        CONSTRAINT FK_DocumentChecklist_Transfer FOREIGN KEY (TransferId) REFERENCES dbo.AssetTransfer(TransferId),
        CONSTRAINT UQ_DocumentChecklist_TransferDocument UNIQUE (TransferId, DocumentType)
    );
END;
GO

IF OBJECT_ID(N'dbo.RiskAlert', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RiskAlert
    (
        RiskAlertId int NOT NULL CONSTRAINT PK_RiskAlert PRIMARY KEY,
        AlertCode nvarchar(32) NOT NULL CONSTRAINT UQ_RiskAlert_AlertCode UNIQUE,
        TransferId int NOT NULL,
        Severity nvarchar(20) NOT NULL,
        Category nvarchar(60) NOT NULL,
        Reason nvarchar(300) NOT NULL,
        AlertStatus nvarchar(30) NOT NULL,
        OpenedAt datetime2(0) NOT NULL,
        ResolvedAt datetime2(0) NULL,
        UpdatedAt datetime2(0) NOT NULL,
        CONSTRAINT FK_RiskAlert_Transfer FOREIGN KEY (TransferId) REFERENCES dbo.AssetTransfer(TransferId)
    );
END;
GO

IF OBJECT_ID(N'dbo.InteractionNote', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.InteractionNote
    (
        InteractionNoteId int NOT NULL CONSTRAINT PK_InteractionNote PRIMARY KEY,
        TransferId int NOT NULL,
        NoteDate datetime2(0) NOT NULL,
        Channel nvarchar(30) NOT NULL,
        AuthorRole nvarchar(40) NOT NULL,
        NoteText nvarchar(500) NOT NULL,
        CONSTRAINT FK_InteractionNote_Transfer FOREIGN KEY (TransferId) REFERENCES dbo.AssetTransfer(TransferId)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.AssetTransfer') AND name = N'IX_AssetTransfer_StatusStage')
    CREATE INDEX IX_AssetTransfer_StatusStage ON dbo.AssetTransfer(CurrentStatus, CurrentStage) INCLUDE (AccountId, RequestedAmount, ExpectedCompletionDate);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.RiskAlert') AND name = N'IX_RiskAlert_StatusSeverity')
    CREATE INDEX IX_RiskAlert_StatusSeverity ON dbo.RiskAlert(AlertStatus, Severity) INCLUDE (TransferId, Category, OpenedAt);
GO