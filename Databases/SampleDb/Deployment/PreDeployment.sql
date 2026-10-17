/*
--------------------------------------------------------------------------------------
 Pre-Deployment Script
--------------------------------------------------------------------------------------
 This script executes before the DACPAC schema publish operation.
 Non-destructive data preparation, column rename mappings, or safety gates go here.
--------------------------------------------------------------------------------------
*/

PRINT N'Starting Pre-Deployment Script for ' + DB_NAME() + N'...';
GO
