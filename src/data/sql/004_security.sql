:setvar DatabaseName "TransferDemo"

USE [$(DatabaseName)];
GO

IF N'$(McpIdentityName)' = N'REQUIRED'
    THROW 50001, 'McpIdentityName sqlcmd variable is required.', 1;
IF N'$(McpIdentityClientId)' = N'REQUIRED'
    THROW 50002, 'McpIdentityClientId sqlcmd variable is required.', 1;
GO

IF DATABASE_PRINCIPAL_ID(N'mcp_reader') IS NULL
    CREATE ROLE [mcp_reader] AUTHORIZATION [dbo];
GO

GRANT SELECT ON OBJECT::dbo.vw_transfer_summary TO [mcp_reader];
GRANT SELECT ON OBJECT::dbo.vw_client_account_overview TO [mcp_reader];
GRANT SELECT ON OBJECT::dbo.vw_transfer_risk_dashboard TO [mcp_reader];
GRANT SELECT ON OBJECT::dbo.vw_advisor_pipeline TO [mcp_reader];
GRANT EXECUTE ON OBJECT::dbo.usp_GetTransferSummaryByClient TO [mcp_reader];
GRANT EXECUTE ON OBJECT::dbo.usp_GetOpenRiskAlerts TO [mcp_reader];
GRANT EXECUTE ON OBJECT::dbo.usp_GetAdvisorPipeline TO [mcp_reader];
GO

IF DATABASE_PRINCIPAL_ID(N'$(McpIdentityName)') IS NULL
BEGIN
    DECLARE @identitySid varbinary(16) = CONVERT(varbinary(16), CONVERT(uniqueidentifier, N'$(McpIdentityClientId)'));
    DECLARE @createUserSql nvarchar(max) = N'CREATE USER ' + QUOTENAME(N'$(McpIdentityName)') + N' WITH SID = ' + CONVERT(nvarchar(34), @identitySid, 1) + N', TYPE = E;';
    EXEC sys.sp_executesql @createUserSql;
END;
GO

DECLARE @addMemberSql nvarchar(max) = N'ALTER ROLE [mcp_reader] ADD MEMBER ' + QUOTENAME(N'$(McpIdentityName)') + N';';
IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members AS membership
    INNER JOIN sys.database_principals AS rolePrincipal ON rolePrincipal.principal_id = membership.role_principal_id
    INNER JOIN sys.database_principals AS memberPrincipal ON memberPrincipal.principal_id = membership.member_principal_id
    WHERE rolePrincipal.name = N'mcp_reader'
      AND memberPrincipal.name = N'$(McpIdentityName)'
)
    EXEC sys.sp_executesql @addMemberSql;
GO