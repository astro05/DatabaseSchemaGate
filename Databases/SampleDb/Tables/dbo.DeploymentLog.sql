CREATE TABLE [dbo].[DeploymentLog]
(
    [DeploymentId]        BIGINT IDENTITY(1, 1) NOT NULL, -- Unique identifier for deployment record
    [DatabaseName]        VARCHAR(100)          NOT NULL, -- Target database name (e.g. SampleDb)
    [TargetEnvironment]   VARCHAR(50)           NOT NULL, -- Target environment (e.g. Development, Staging, Production)
    [Status]              VARCHAR(20)           NOT NULL, -- Deployment execution outcome (SUCCESS, FAILED, ROLLED_BACK)
    [DeployedAtUtc]       DATETIME2(7)          NOT NULL CONSTRAINT [DF_DeploymentLog_DeployedAtUtc] DEFAULT (SYSUTCDATETIME()), -- Timestamp when deployment initiated (UTC)
    [CompletedAtUtc]      DATETIME2(7)          NULL,     -- Timestamp when deployment completed (UTC)
    [DurationSeconds]     INT                   NULL,     -- Elapsed deployment duration in seconds
    [ScriptName]          NVARCHAR(260)         NULL,     -- Name of the deployed SQL script file
    [CommitSha]           VARCHAR(40)           NOT NULL, -- Full 40-character Git commit SHA
    [CommitShortSha]      VARCHAR(10)           NOT NULL, -- Short 7-10 character Git commit SHA
    [CommitBranch]        VARCHAR(100)          NOT NULL, -- Git source branch or tag name (e.g. main)
    [CommitTitle]         NVARCHAR(500)         NULL,     -- Git commit message title / summary
    [CommitAuthor]        NVARCHAR(150)         NULL,     -- Author who created the Git commit
    [PipelineId]          VARCHAR(50)           NULL,     -- GitLab CI pipeline ID
    [PipelineUrl]         VARCHAR(500)          NULL,     -- Full web URL to GitLab CI pipeline execution
    [JobId]               VARCHAR(50)           NULL,     -- GitLab CI job ID
    [TriggeredBy]         NVARCHAR(150)         NULL,     -- GitLab user who triggered or merged the pipeline
    [DacpacVersion]       VARCHAR(100)          NULL,     -- Compiled DACPAC artifact name or version tag
    [ErrorMessage]        NVARCHAR(MAX)         NULL,     -- Detailed error output or stack trace if deployment failed
    [DeployReportSummary] NVARCHAR(MAX)         NULL,     -- Summary of database objects created, altered, or dropped
    CONSTRAINT [PK_DeploymentLog] PRIMARY KEY CLUSTERED ([DeploymentId] ASC)
) WITH (DATA_COMPRESSION = PAGE);
GO

CREATE NONCLUSTERED INDEX [IX_DeploymentLog_Database_Environment_Date]
ON [dbo].[DeploymentLog] ([DatabaseName], [TargetEnvironment], [DeployedAtUtc] DESC)
INCLUDE ([Status], [CommitShortSha], [TriggeredBy]);
GO

-- =========================================================================
-- Extended Properties (MS_Description) for Table and Columns
-- =========================================================================

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Audit log tracking all automated and manual database DACPAC deployments, status, and GitLab CI/CD metadata.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Primary key identity for deployment log record.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'DeploymentId';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Name of target database deployed (e.g. SampleDb).', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'DatabaseName';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Target deployment environment (Development, Staging, Production).', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'TargetEnvironment';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Deployment execution result status: SUCCESS, FAILED, or ROLLED_BACK.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'Status';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'UTC timestamp when deployment execution started.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'DeployedAtUtc';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'UTC timestamp when deployment execution completed.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'CompletedAtUtc';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Total deployment run duration in seconds.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'DurationSeconds';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Full 40-character Git commit SHA deployed from repository.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'CommitSha';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Short 7-10 character Git commit SHA.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'CommitShortSha';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Git branch or ref deployed (e.g. main).', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'CommitBranch';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Git commit title / summary message.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'CommitTitle';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Author who committed the deployed changes.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'CommitAuthor';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'GitLab CI pipeline ID that executed the deployment.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'PipelineId';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Direct URL to GitLab CI pipeline execution.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'PipelineUrl';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'GitLab CI job ID that ran the deployment step.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'JobId';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'GitLab user who triggered or merged the pipeline.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'TriggeredBy';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Compiled DACPAC artifact package name or version.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'DacpacVersion';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Captured error message and stack trace if deployment failed.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'ErrorMessage';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Summary of DACPAC schema diff and objects modified during publish.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'DeployReportSummary';
GO

EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Name of the deployed SQL script file associated with this deployment record.', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'DeploymentLog', 
    @level2type = N'COLUMN', @level2name = N'ScriptName';
GO
