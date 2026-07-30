:setvar DatabaseName "TransferDemo"

IF DB_ID(N'$(DatabaseName)') IS NULL
BEGIN
    DECLARE @createDatabaseSql nvarchar(max) = N'CREATE DATABASE ' + QUOTENAME(N'$(DatabaseName)');
    EXEC sys.sp_executesql @createDatabaseSql;
END;
GO