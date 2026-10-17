# Troubleshooting

Find the message or code you see, then apply the fix.

## Error codes

| Code / message | Where | Cause | Fix |
|---|---|---|---|
| `E_DATABASE_NOT_FOUND: no Databases/<Name>/<Name>.sqlproj` | Any script | `-Database` names no managed database (typo, or the project file is named differently from its folder) | Use one of the names listed in the message; folder and `.sqlproj` must have the same name |
| `E_DATABASE_MISMATCH: ConnectionString targets database '<X>'` | Deploy, ScriptRunner, drift, extract | The connection string's `Initial Catalog` is another database | Use the connection string for that database |
| `No ConnectionString provided (found) for database <Name>` | Deploy, ScriptRunner | No `-ConnectionString`, no `DEV_CONNECTION_STRING_<NAME>`, nothing in `appsettings.local.json` | Locally: add it to `appsettings.local.json`. In CI: create the variable ([CI/CD](CI-CD.md#3-connection-string-variables)). Protected variables reach only protected branches. |
| `... need a single -Database, not All.` | Deploy, ScriptRunner | `-Database All` with one connection string | Drop `-ConnectionString`, or deploy one database at a time |
| `Expected artifact not found ... Is the project in Databases.sln?` | Build | A database folder is not in the solution | `dotnet sln Databases.sln add --in-root Databases/<Name>/<Name>.sqlproj` |
| `DACPAC for <Name> not found ... Run Scripts/BuildDatabase.ps1 first.` | Deploy, drift | Nothing built yet | `.\Scripts\BuildDatabase.ps1` |
| `E_STALE_BASE` | `check_concurrent_edits` | A `.sql` file you modified changed on the target branch after you branched | Rebase and review the whole object ([Git Workflow](Git-Workflow.md#3-when-someone-changed-the-same-object-e_stale_base)) |
| `E_GIT_FAILED: no merge base` | `check_concurrent_edits` | Shallow clone | The job sets `GIT_DEPTH: "0"`; keep it |
| `E_PARSER_UNAVAILABLE` | `Test-SqlSafety.ps1` | ScriptDom DLL not found | Install SqlPackage (`dotnet tool install -g microsoft.sqlpackage`) or build `Databases.sln` once |
| `E_SYNTAX_PARSE_ERROR` | `Test-SqlSafety.ps1` | T-SQL that does not parse | Fix the syntax; this cannot be approved |
| `E_VALIDATION_FAILED: ... contains 'USE <X>'` | ScriptRunner | A one-off script uses another database | Move the script to `ScriptRunner/<X>/` |
| `E_SCRIPT_FAILED` | ScriptRunner | SQL error while running a script; it was rolled back | Read `ErrorMessage` in `dbo.DeploymentLog`; ship the fix as a **new** script |

## Build

**`SQL71501: ... has an unresolved reference to object [dbo].[X]`**
The object references something not in the project. Add the missing object's file under `Databases/<Database>/`, fix the name, or for another database or `master` add a database reference.

**`SQL70001: This statement is not recognized in this context`**
A file contains more than one object, or statements that are not object definitions (`INSERT`, `EXEC`). Split it, or move data statements to `Deployment/PostDeployment.sql` or a ScriptRunner script.

**`NETSDK1004` in Visual Studio**
Run `dotnet restore Databases.sln` once.

## Validation

**`Contains 'USE <db>' statement`**
Remove the `USE`. The word "use" in comments is fine; in a string literal (`N'use this'`) it still trips the check, so reword the string.

**`Schema name is mandatory for ...`**
Write `[dbo].[Name]` instead of `Name`, for the object definition and for `UPDATE`/`DELETE`/`INSERT`/`TRUNCATE`/`ALTER TABLE`/`DROP TABLE` targets.

**`Unconditional UPDATE detected without manual approval comment`**
Add a `WHERE`, or, if every row really must change, put `-- @manual-approve: <reason>` on the line before the `UPDATE`.

## Deployment

**`Rows were detected. The schema update is terminating because data loss might occur.`**
A change would drop data (a column with values, a smaller type). See [Development: Changes that could lose data](Development.md#4-changes-that-could-lose-data).

**`A project which specifies SQL Server <newer> as the target platform cannot be published to SQL Server <older>`**
Set `<DSP>` in the `.sqlproj` to the oldest server version you deploy to ([Getting Started](Getting-Started.md#target-sql-server-version)).

**Login failed / cannot connect in `deploy_dev`**
The password changed, the encoded variable kept surrounding quotes, or the runner cannot reach the server (firewall, port 1433). Re-encode the current connection string ([CI/CD](CI-CD.md#create-or-update-a-variable)) and check the runner's network.

**GitLab refuses to save a variable with *Mask variable* checked**
The value is not Base64, or is shorter than 8 characters. Encode it.

**A deleted object is still in the database**
Expected: deploys never drop objects. Drop it with a [ScriptRunner](ScriptRunner.md) script.

**No row in `dbo.DeploymentLog` after a deploy**
DACPAC deploys log one row per `.sql` file under `Databases/<Database>/` that the **deployed commit** changed compared with its first parent. For a merge commit, that is everything the merge request brought in. A commit that changed no such file logs nothing. If several commits are pushed straight to `main` at once, only the last one's files are logged; all changes still deploy.

## Drift

**`DetectDrift.ps1` exits 2**
Someone changed the live database. Review `artifacts/<Database>-DriftReport.xml`, then either commit the change to Git through a merge request or let the next deploy restore Git's version.

## Pipeline

**`deploy_dev` was skipped and `approval_required` ran**
A new one-off script contains a risky statement. Read the `approval_required` log and run `deploy_dev_approved` if it is intended ([CI/CD](CI-CD.md#4-approving-risky-one-off-scripts)).

**`approval_required` failed with `cat: ... No such file or directory`**
`check_scripts` failed for a reason that cannot be approved (syntax error, `USE` of another database, credentials, unreachable database or missing variable). Read the `check_scripts` log.

**Jobs stay *pending***
No runner matches. Check that a runner is online, and that the `tags:` in `.gitlab-ci.yml` (if any) match it.
