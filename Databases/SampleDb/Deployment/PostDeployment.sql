/*
--------------------------------------------------------------------------------------
 Post-Deployment Script
--------------------------------------------------------------------------------------
 This script executes after the DACPAC schema publish operation.
 Static lookup table seeding, default configurations, or post-migration tasks go here.
--------------------------------------------------------------------------------------
*/

PRINT N'Executing Post-Deployment Script for ' + DB_NAME() + N'...';
GO
