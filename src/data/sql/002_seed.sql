:setvar DatabaseName "TransferDemo"

USE [$(DatabaseName)];
GO

MERGE dbo.Client AS target
USING (VALUES
    (1, N'CLIENT-001', N'Contoso Demo Client 001', N'Private Wealth', '2026-07-01T12:00:00', '2026-07-28T12:00:00'),
    (2, N'CLIENT-002', N'Fabrikam Demo Family', N'Private Wealth', '2026-07-02T12:00:00', '2026-07-28T12:00:00'),
    (3, N'CLIENT-003', N'Northwind Demo Trust', N'Trust Services', '2026-07-03T12:00:00', '2026-07-29T12:00:00'),
    (4, N'CLIENT-004', N'Adventure Works Demo Executive', N'Executive Services', '2026-07-04T12:00:00', '2026-07-29T12:00:00')
) AS source (ClientId, ClientCode, DisplayName, Segment, CreatedAt, UpdatedAt)
ON target.ClientId = source.ClientId
WHEN MATCHED THEN UPDATE SET ClientCode = source.ClientCode, DisplayName = source.DisplayName, Segment = source.Segment, UpdatedAt = source.UpdatedAt
WHEN NOT MATCHED THEN INSERT (ClientId, ClientCode, DisplayName, Segment, CreatedAt, UpdatedAt) VALUES (source.ClientId, source.ClientCode, source.DisplayName, source.Segment, source.CreatedAt, source.UpdatedAt);
GO

MERGE dbo.Household AS target
USING (VALUES
    (1, N'HH-001', N'Contoso Demo Household', 1, '2026-07-28T12:00:00'),
    (2, N'HH-002', N'Fabrikam Demo Household', 2, '2026-07-28T12:00:00'),
    (3, N'HH-003', N'Northwind Demo Trust Household', 3, '2026-07-29T12:00:00'),
    (4, N'HH-004', N'Adventure Works Demo Household', 4, '2026-07-29T12:00:00')
) AS source (HouseholdId, HouseholdCode, HouseholdName, PrimaryClientId, UpdatedAt)
ON target.HouseholdId = source.HouseholdId
WHEN MATCHED THEN UPDATE SET HouseholdCode = source.HouseholdCode, HouseholdName = source.HouseholdName, PrimaryClientId = source.PrimaryClientId, UpdatedAt = source.UpdatedAt
WHEN NOT MATCHED THEN INSERT (HouseholdId, HouseholdCode, HouseholdName, PrimaryClientId, UpdatedAt) VALUES (source.HouseholdId, source.HouseholdCode, source.HouseholdName, source.PrimaryClientId, source.UpdatedAt);
GO

MERGE dbo.Advisor AS target
USING (VALUES
    (1, N'ADV-CHI-01', N'Morgan Lee', N'Chicago', '2026-07-28T12:00:00'),
    (2, N'ADV-MIL-01', N'Riley Patel', N'Milwaukee', '2026-07-28T12:00:00'),
    (3, N'ADV-GLA-01', N'Jordan Smith', N'Great Lakes', '2026-07-29T12:00:00')
) AS source (AdvisorId, AdvisorCode, DisplayName, Region, UpdatedAt)
ON target.AdvisorId = source.AdvisorId
WHEN MATCHED THEN UPDATE SET AdvisorCode = source.AdvisorCode, DisplayName = source.DisplayName, Region = source.Region, UpdatedAt = source.UpdatedAt
WHEN NOT MATCHED THEN INSERT (AdvisorId, AdvisorCode, DisplayName, Region, UpdatedAt) VALUES (source.AdvisorId, source.AdvisorCode, source.DisplayName, source.Region, source.UpdatedAt);
GO

MERGE dbo.Account AS target
USING (VALUES
    (101, N'ACCT-001-A', 1, 1, 1, N'Brokerage', N'Legacy Custodian A', 825000.00, N'Open', '2026-07-28T12:00:00'),
    (102, N'ACCT-001-B', 1, 1, 1, N'Traditional IRA', N'Legacy Custodian B', 410000.00, N'Open', '2026-07-28T12:00:00'),
    (201, N'ACCT-002-A', 2, 2, 2, N'Joint Brokerage', N'Legacy Custodian C', 1260000.00, N'Open', '2026-07-28T12:00:00'),
    (301, N'ACCT-003-A', 3, 3, 3, N'Trust', N'Legacy Custodian A', 2150000.00, N'Open', '2026-07-29T12:00:00'),
    (401, N'ACCT-004-A', 4, 4, 2, N'Executive Brokerage', N'Legacy Custodian D', 675000.00, N'Open', '2026-07-29T12:00:00')
) AS source (AccountId, AccountCode, ClientId, HouseholdId, AdvisorId, AccountType, Custodian, MarketValue, Status, UpdatedAt)
ON target.AccountId = source.AccountId
WHEN MATCHED THEN UPDATE SET AccountCode = source.AccountCode, ClientId = source.ClientId, HouseholdId = source.HouseholdId, AdvisorId = source.AdvisorId, AccountType = source.AccountType, Custodian = source.Custodian, MarketValue = source.MarketValue, Status = source.Status, UpdatedAt = source.UpdatedAt
WHEN NOT MATCHED THEN INSERT (AccountId, AccountCode, ClientId, HouseholdId, AdvisorId, AccountType, Custodian, MarketValue, Status, UpdatedAt) VALUES (source.AccountId, source.AccountCode, source.ClientId, source.HouseholdId, source.AdvisorId, source.AccountType, source.Custodian, source.MarketValue, source.Status, source.UpdatedAt);
GO

MERGE dbo.AssetTransfer AS target
USING (VALUES
    (1001, N'TRF-2026-001', 101, N'Legacy Custodian A', N'ACATS', 825000.00, '2026-07-08', '2026-07-22', NULL, N'Blocked', N'Document Review', N'High', N'Transfer is blocked because the signed transfer form and cost-basis statement are missing.', 0, '2026-07-29T14:00:00'),
    (1002, N'TRF-2026-002', 102, N'Legacy Custodian B', N'IRA Trustee Transfer', 410000.00, '2026-07-10', '2026-07-24', NULL, N'In Progress', N'Custodian Review', N'Medium', N'Custodian acknowledged the request and is validating beneficiary information.', 0, '2026-07-29T14:00:00'),
    (2001, N'TRF-2026-003', 201, N'Legacy Custodian C', N'ACATS', 1260000.00, '2026-07-03', '2026-07-17', NULL, N'Delayed', N'Exception Management', N'High', N'Position mismatch and an unsettled trade have delayed the transfer.', 0, '2026-07-30T09:00:00'),
    (3001, N'TRF-2026-004', 301, N'Legacy Custodian A', N'Trust Transfer', 2150000.00, '2026-07-14', '2026-07-30', NULL, N'In Progress', N'Legal Review', N'High', N'Trust certification is under legal review before assets can be released.', 0, '2026-07-30T09:00:00'),
    (4001, N'TRF-2026-005', 401, N'Legacy Custodian D', N'ACATS', 675000.00, '2026-07-01', '2026-07-15', '2026-07-14', N'Completed', N'Completed', N'Low', N'Assets and cost basis were received and reconciled.', 0, '2026-07-28T16:00:00'),
    (4002, N'TRF-2026-006', 401, N'Legacy Custodian D', N'Partial ACATS', 125000.00, '2026-07-20', '2026-08-03', NULL, N'In Progress', N'Initiated', N'Low', N'Partial transfer request was submitted and accepted by the delivering firm.', 0, '2026-07-30T09:00:00')
) AS source (TransferId, TransferCode, AccountId, SourceInstitution, TransferType, RequestedAmount, RequestedDate, ExpectedCompletionDate, CompletedDate, CurrentStatus, CurrentStage, Priority, Summary, IsDeleted, UpdatedAt)
ON target.TransferId = source.TransferId
WHEN MATCHED THEN UPDATE SET TransferCode = source.TransferCode, AccountId = source.AccountId, SourceInstitution = source.SourceInstitution, TransferType = source.TransferType, RequestedAmount = source.RequestedAmount, RequestedDate = source.RequestedDate, ExpectedCompletionDate = source.ExpectedCompletionDate, CompletedDate = source.CompletedDate, CurrentStatus = source.CurrentStatus, CurrentStage = source.CurrentStage, Priority = source.Priority, Summary = source.Summary, IsDeleted = source.IsDeleted, UpdatedAt = source.UpdatedAt
WHEN NOT MATCHED THEN INSERT (TransferId, TransferCode, AccountId, SourceInstitution, TransferType, RequestedAmount, RequestedDate, ExpectedCompletionDate, CompletedDate, CurrentStatus, CurrentStage, Priority, Summary, IsDeleted, UpdatedAt) VALUES (source.TransferId, source.TransferCode, source.AccountId, source.SourceInstitution, source.TransferType, source.RequestedAmount, source.RequestedDate, source.ExpectedCompletionDate, source.CompletedDate, source.CurrentStatus, source.CurrentStage, source.Priority, source.Summary, source.IsDeleted, source.UpdatedAt);
GO

MERGE dbo.TransferStatusHistory AS target
USING (VALUES
    (1, 1001, N'Initiated', N'Initiated', '2026-07-08T09:00:00', N'Request submitted.'),
    (2, 1001, N'Blocked', N'Document Review', '2026-07-12T15:00:00', N'Missing signed transfer form and cost-basis statement.'),
    (3, 1002, N'In Progress', N'Custodian Review', '2026-07-14T11:00:00', N'Delivering custodian validating beneficiary details.'),
    (4, 2001, N'Delayed', N'Exception Management', '2026-07-18T10:00:00', N'Position mismatch and unsettled trade identified.'),
    (5, 3001, N'In Progress', N'Legal Review', '2026-07-22T13:00:00', N'Trust certification sent to legal review.'),
    (6, 4001, N'Completed', N'Completed', '2026-07-14T16:00:00', N'Assets and cost basis reconciled.'),
    (7, 4002, N'In Progress', N'Initiated', '2026-07-20T10:00:00', N'Partial transfer accepted.')
) AS source (TransferStatusHistoryId, TransferId, Status, Stage, StatusDate, Detail)
ON target.TransferStatusHistoryId = source.TransferStatusHistoryId
WHEN MATCHED THEN UPDATE SET TransferId = source.TransferId, Status = source.Status, Stage = source.Stage, StatusDate = source.StatusDate, Detail = source.Detail
WHEN NOT MATCHED THEN INSERT (TransferStatusHistoryId, TransferId, Status, Stage, StatusDate, Detail) VALUES (source.TransferStatusHistoryId, source.TransferId, source.Status, source.Stage, source.StatusDate, source.Detail);
GO

MERGE dbo.DocumentChecklist AS target
USING (VALUES
    (1, 1001, N'Signed Transfer Form', 1, 0, NULL, '2026-07-29T14:00:00'),
    (2, 1001, N'Cost Basis Statement', 1, 0, NULL, '2026-07-29T14:00:00'),
    (3, 1002, N'IRA Acceptance Letter', 1, 1, '2026-07-13', '2026-07-29T14:00:00'),
    (4, 2001, N'Latest Account Statement', 1, 1, '2026-07-04', '2026-07-30T09:00:00'),
    (5, 3001, N'Trust Certification', 1, 1, '2026-07-21', '2026-07-30T09:00:00'),
    (6, 4001, N'Cost Basis Statement', 1, 1, '2026-07-14', '2026-07-28T16:00:00')
) AS source (DocumentChecklistId, TransferId, DocumentType, IsRequired, IsReceived, ReceivedDate, UpdatedAt)
ON target.DocumentChecklistId = source.DocumentChecklistId
WHEN MATCHED THEN UPDATE SET TransferId = source.TransferId, DocumentType = source.DocumentType, IsRequired = source.IsRequired, IsReceived = source.IsReceived, ReceivedDate = source.ReceivedDate, UpdatedAt = source.UpdatedAt
WHEN NOT MATCHED THEN INSERT (DocumentChecklistId, TransferId, DocumentType, IsRequired, IsReceived, ReceivedDate, UpdatedAt) VALUES (source.DocumentChecklistId, source.TransferId, source.DocumentType, source.IsRequired, source.IsReceived, source.ReceivedDate, source.UpdatedAt);
GO

MERGE dbo.RiskAlert AS target
USING (VALUES
    (1, N'RISK-001', 1001, N'High', N'Missing Documents', N'Two required documents are outstanding after the expected review window.', N'Open', '2026-07-15T10:00:00', NULL, '2026-07-29T14:00:00'),
    (2, N'RISK-002', 2001, N'High', N'Transfer Delay', N'Transfer is past its expected completion date due to a position mismatch.', N'Open', '2026-07-18T10:00:00', NULL, '2026-07-30T09:00:00'),
    (3, N'RISK-003', 3001, N'Medium', N'Legal Review', N'Trust certification requires legal approval before release.', N'Open', '2026-07-22T13:00:00', NULL, '2026-07-30T09:00:00'),
    (4, N'RISK-004', 4001, N'Low', N'Cost Basis', N'Cost-basis receipt was monitored through completion.', N'Resolved', '2026-07-10T09:00:00', '2026-07-14T16:00:00', '2026-07-28T16:00:00')
) AS source (RiskAlertId, AlertCode, TransferId, Severity, Category, Reason, AlertStatus, OpenedAt, ResolvedAt, UpdatedAt)
ON target.RiskAlertId = source.RiskAlertId
WHEN MATCHED THEN UPDATE SET AlertCode = source.AlertCode, TransferId = source.TransferId, Severity = source.Severity, Category = source.Category, Reason = source.Reason, AlertStatus = source.AlertStatus, OpenedAt = source.OpenedAt, ResolvedAt = source.ResolvedAt, UpdatedAt = source.UpdatedAt
WHEN NOT MATCHED THEN INSERT (RiskAlertId, AlertCode, TransferId, Severity, Category, Reason, AlertStatus, OpenedAt, ResolvedAt, UpdatedAt) VALUES (source.RiskAlertId, source.AlertCode, source.TransferId, source.Severity, source.Category, source.Reason, source.AlertStatus, source.OpenedAt, source.ResolvedAt, source.UpdatedAt);
GO

MERGE dbo.InteractionNote AS target
USING (VALUES
    (1, 1001, '2026-07-25T14:00:00', N'Phone', N'Operations Specialist', N'Client was contacted and asked to provide the two missing documents.'),
    (2, 2001, '2026-07-28T11:00:00', N'Email', N'Advisor', N'Advisor requested an escalation with the delivering custodian.'),
    (3, 3001, '2026-07-29T09:30:00', N'Workflow', N'Legal Reviewer', N'Certification language is being compared with trust account requirements.'),
    (4, 4001, '2026-07-14T16:15:00', N'Workflow', N'Operations Specialist', N'Transfer completion and reconciliation were confirmed.')
) AS source (InteractionNoteId, TransferId, NoteDate, Channel, AuthorRole, NoteText)
ON target.InteractionNoteId = source.InteractionNoteId
WHEN MATCHED THEN UPDATE SET TransferId = source.TransferId, NoteDate = source.NoteDate, Channel = source.Channel, AuthorRole = source.AuthorRole, NoteText = source.NoteText
WHEN NOT MATCHED THEN INSERT (InteractionNoteId, TransferId, NoteDate, Channel, AuthorRole, NoteText) VALUES (source.InteractionNoteId, source.TransferId, source.NoteDate, source.Channel, source.AuthorRole, source.NoteText);
GO