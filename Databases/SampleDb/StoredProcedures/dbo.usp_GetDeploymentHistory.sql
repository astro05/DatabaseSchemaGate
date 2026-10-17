CREATE PROCEDURE [dbo].[usp_GetDeploymentHistory]
    @Top INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@Top)
        [DeploymentId], [TargetEnvironment], [Status], [ScriptName], [CommitShortSha],
        [CommitAuthor], [DeployedAtUtc], [DurationSeconds], [ErrorMessage]
    FROM [dbo].[DeploymentLog]
    ORDER BY [DeploymentId] DESC;
END;
GO
