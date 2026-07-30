:setvar DatabaseName "TransferDemo"

USE [$(DatabaseName)];
GO

CREATE OR ALTER VIEW dbo.vw_transfer_summary
AS
SELECT
    transfer.TransferId,
    transfer.TransferCode,
    client.ClientCode,
    client.DisplayName AS ClientName,
    account.AccountCode,
    account.AccountType,
    advisor.AdvisorCode,
    advisor.DisplayName AS AdvisorName,
    transfer.SourceInstitution,
    transfer.TransferType,
    transfer.RequestedAmount,
    transfer.RequestedDate,
    transfer.ExpectedCompletionDate,
    transfer.CompletedDate,
    transfer.CurrentStatus,
    transfer.CurrentStage,
    transfer.Priority,
    transfer.Summary,
    DATEDIFF(day, transfer.RequestedDate, COALESCE(transfer.CompletedDate, CAST(SYSUTCDATETIME() AS date))) AS AgeDays,
    transfer.UpdatedAt AS DataUpdatedAt
FROM dbo.AssetTransfer AS transfer
INNER JOIN dbo.Account AS account ON account.AccountId = transfer.AccountId
INNER JOIN dbo.Client AS client ON client.ClientId = account.ClientId
INNER JOIN dbo.Advisor AS advisor ON advisor.AdvisorId = account.AdvisorId
WHERE transfer.IsDeleted = 0;
GO

CREATE OR ALTER VIEW dbo.vw_client_account_overview
AS
SELECT
    account.AccountId,
    account.AccountCode,
    client.ClientCode,
    client.DisplayName AS ClientName,
    client.Segment,
    household.HouseholdCode,
    household.HouseholdName,
    advisor.AdvisorCode,
    advisor.DisplayName AS AdvisorName,
    advisor.Region AS AdvisorRegion,
    account.AccountType,
    account.Custodian,
    account.MarketValue,
    account.Status AS AccountStatus,
    account.UpdatedAt AS DataUpdatedAt
FROM dbo.Account AS account
INNER JOIN dbo.Client AS client ON client.ClientId = account.ClientId
INNER JOIN dbo.Household AS household ON household.HouseholdId = account.HouseholdId
INNER JOIN dbo.Advisor AS advisor ON advisor.AdvisorId = account.AdvisorId;
GO

CREATE OR ALTER VIEW dbo.vw_transfer_risk_dashboard
AS
SELECT
    alert.RiskAlertId,
    alert.AlertCode,
    transfer.TransferId,
    transfer.TransferCode,
    client.ClientCode,
    client.DisplayName AS ClientName,
    advisor.AdvisorCode,
    advisor.DisplayName AS AdvisorName,
    transfer.CurrentStatus AS TransferStatus,
    transfer.CurrentStage,
    alert.Severity,
    alert.Category,
    alert.Reason,
    alert.AlertStatus,
    alert.OpenedAt,
    alert.ResolvedAt,
    alert.UpdatedAt AS DataUpdatedAt
FROM dbo.RiskAlert AS alert
INNER JOIN dbo.AssetTransfer AS transfer ON transfer.TransferId = alert.TransferId
INNER JOIN dbo.Account AS account ON account.AccountId = transfer.AccountId
INNER JOIN dbo.Client AS client ON client.ClientId = account.ClientId
INNER JOIN dbo.Advisor AS advisor ON advisor.AdvisorId = account.AdvisorId
WHERE transfer.IsDeleted = 0;
GO

CREATE OR ALTER VIEW dbo.vw_advisor_pipeline
AS
SELECT
    transfer.TransferId,
    transfer.TransferCode,
    advisor.AdvisorId,
    advisor.AdvisorCode,
    advisor.DisplayName AS AdvisorName,
    advisor.Region,
    client.ClientCode,
    client.DisplayName AS ClientName,
    transfer.CurrentStatus,
    transfer.CurrentStage,
    transfer.Priority,
    transfer.RequestedAmount,
    transfer.RequestedDate,
    transfer.ExpectedCompletionDate,
    DATEDIFF(day, transfer.RequestedDate, COALESCE(transfer.CompletedDate, CAST(SYSUTCDATETIME() AS date))) AS AgeDays,
    transfer.UpdatedAt AS DataUpdatedAt
FROM dbo.AssetTransfer AS transfer
INNER JOIN dbo.Account AS account ON account.AccountId = transfer.AccountId
INNER JOIN dbo.Client AS client ON client.ClientId = account.ClientId
INNER JOIN dbo.Advisor AS advisor ON advisor.AdvisorId = account.AdvisorId
WHERE transfer.IsDeleted = 0;
GO

CREATE OR ALTER PROCEDURE dbo.usp_GetTransferSummaryByClient
    @ClientCode nvarchar(32)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT *
    FROM dbo.vw_transfer_summary
    WHERE ClientCode = @ClientCode
    ORDER BY RequestedDate DESC, TransferId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_GetOpenRiskAlerts
    @MinimumSeverity nvarchar(20) = N'Low'
AS
BEGIN
    SET NOCOUNT ON;
    SELECT *
    FROM dbo.vw_transfer_risk_dashboard
    WHERE AlertStatus = N'Open'
      AND CASE Severity WHEN N'High' THEN 3 WHEN N'Medium' THEN 2 ELSE 1 END >=
          CASE @MinimumSeverity WHEN N'High' THEN 3 WHEN N'Medium' THEN 2 ELSE 1 END
    ORDER BY CASE Severity WHEN N'High' THEN 3 WHEN N'Medium' THEN 2 ELSE 1 END DESC, OpenedAt;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_GetAdvisorPipeline
    @AdvisorCode nvarchar(32) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT *
    FROM dbo.vw_advisor_pipeline
    WHERE @AdvisorCode IS NULL OR AdvisorCode = @AdvisorCode
    ORDER BY AdvisorName, Priority DESC, ExpectedCompletionDate;
END;
GO