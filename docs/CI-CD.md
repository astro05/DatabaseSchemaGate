# CI/CD Guide

`.gitlab-ci.yml` validates every merge request and deploys every database to **Development** when `main` changes. It finds the databases itself (`Databases/<Name>/<Name>.sqlproj`), so adding a database needs no pipeline edit, only its [connection-string variable](#3-connection-string-variables).

## 1. The pipeline

```text
Merge request:  validate_sql + check_concurrent_edits ─► build_dacpac ─► test_database ─► (merge)

main:           validate_sql ─► build_dacpac ─► test_database + check_scripts
                                                                 │
                    no risky statement in new one-off scripts ───┴─► deploy_dev
                    risky statement ─► approval_required ─► deploy_dev_approved (manual)
```

| Stage | Job | Runs on | What it does | Can a person override a failure? |
|---|---|---|---|---|
| validate | `validate_sql` | MR, `main` | `ValidateDatabase.ps1`, then `Test-SqlSafety.ps1` on `Databases/` (Production rules) | No |
| validate | `check_concurrent_edits` | MR | Fails with `E_STALE_BASE` if a `.sql` file you modified changed on the target branch after you branched ([Git Workflow](Git-Workflow.md#3-when-someone-changed-the-same-object-e_stale_base)) | No |
| build | `build_dacpac` | MR, `main` | Builds `Databases.sln`; keeps `bin/Release/*.dacpac` for 30 days | No |
| test | `test_database` | MR, `main` | Runs the four suites in `Tests/` | No |
| test | `check_scripts` | `main` | `Invoke-ScriptRunner.ps1 -Database All -CheckOnly`: checks the one-off scripts that have **not run yet** in Development | Only for risky statements (below) |
| manual_approval | `approval_required` | `main`, only when `check_scripts` failed | Prints the statements that need approval | |
| deploy_dev | `deploy_dev` | `main` | `DeployDatabase.ps1 -Database All`, then `Invoke-ScriptRunner.ps1 -Database All` | No |
| deploy_dev | `deploy_dev_approved` | `main`, manual | The same deploy, after a person approved | |

Deploys share `resource_group: deploy-dev`, so only one runs at a time; later pipelines wait.

Each deploy keeps `artifacts/<Database>-Development-DeployReport.xml` for 14 days: the list of objects it created, altered or dropped.

## 2. Runners

Jobs run in the `mcr.microsoft.com/dotnet/sdk:10.0` image and need:

- A **Docker executor with a Linux bash shell**. Jobs install PowerShell 7.4.6 and SqlPackage 162.5.57 into `~/.dotnet` when missing.
- **Network access** to your SQL Server (port 1433 by default), and to the internet for NuGet, PowerShell and SqlPackage downloads.

GitLab.com shared runners usually cannot reach a database inside your network. Register a [self-managed runner](https://docs.gitlab.com/runner/register/) in a network that can reach it, give it a tag, and pin the jobs to it in `.gitlab-ci.yml`:

```yaml
default:
  image: mcr.microsoft.com/dotnet/sdk:10.0
  tags: [sql-runner]
```

## 3. Connection-string variables

Each database needs one variable, named after the database:

| Database folder | Variable |
|---|---|
| `Databases/SampleDb` | `DEV_CONNECTION_STRING_SAMPLEDB` |
| `Databases/Sales` | `DEV_CONNECTION_STRING_SALES` |
| `Databases/Sales-EU` | `DEV_CONNECTION_STRING_SALES_EU` |

The rule: `DEV_CONNECTION_STRING_` + the folder name upper-cased, with every character other than `A-Z`, `0-9` and `_` replaced by `_`. (`STG_` / `PROD_` prefixes are for [more environments](#5-more-environments-staging-production).)

`deploy_dev` needs a variable for every database. `check_scripts` needs one only for databases that have scripts in `ScriptRunner/<Database>/`. A missing variable fails the job with `No ConnectionString provided for database <Name>`.

### Why Base64

GitLab can only **mask** a value made of Base64 characters (plus `@ : . ~`), on one line, at least 8 characters long. A connection string contains `;`, `=` and spaces, so store it Base64-encoded; the scripts decode it themselves.

### Create or update a variable

1. **Copy the connection string** to the clipboard. Its `Initial Catalog` must be the database itself (`Initial Catalog=Sales` for `DEV_CONNECTION_STRING_SALES`). One naming another database is rejected with `E_DATABASE_MISMATCH`.

2. **Encode it on your machine.** This replaces the clipboard with the Base64 value without showing either on screen (surrounding quotes are dropped):

   ```powershell
   [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Clipboard -Raw).Trim().Trim('"'))) | Set-Clipboard
   ```

   On Linux or macOS (input is not echoed):

   ```bash
   read -rs CS && printf '%s' "$CS" | base64 -w0 && echo    # macOS: base64 without -w0
   ```

3. **Add it in GitLab:** project → **Settings → CI/CD → Variables → Add variable**:

   | Field | Value |
   |---|---|
   | Type | Variable |
   | Environment scope | All (default) |
   | Protect variable | ✅ Only pipelines on protected branches (`main`) receive it |
   | Mask variable | ✅ Hidden in job logs |
   | Expand variable reference | ☐ Off |
   | Key | `DEV_CONNECTION_STRING_<DATABASE>` |
   | Value | The Base64 value |

4. **Repeat** for each database.

5. **Check the next `main` pipeline.** The `deploy_dev` log shows, for each database:

   ```text
   Loaded ConnectionString from environment variable (DEV_CONNECTION_STRING_SALES)
   Decoded Base64 ConnectionString for Development (Sales)
   ```

Because the variables are protected, merge request pipelines never receive them, so they cannot reach the database. When a password changes, update `appsettings.local.json` and the variable. If a password was ever exposed, change it on SQL Server first.

## 4. Approving risky one-off scripts

`check_scripts` reads `dbo.DeploymentLog` in each Development database and checks only the [ScriptRunner](ScriptRunner.md) scripts that have **not run there yet**:

| Finding in a new script | Result |
|---|---|
| Nothing risky | `deploy_dev` runs automatically |
| A risky statement: `UPDATE`/`DELETE` without `WHERE`, `DROP TABLE`, `DROP DATABASE`, `TRUNCATE TABLE`, `ALTER TABLE ... DROP COLUMN`, `DROP PROCEDURE`, `DROP VIEW` | `check_scripts` fails and writes `artifacts/approval-required-<Database>.txt`; `approval_required` prints it; `deploy_dev` is skipped; the manual `deploy_dev_approved` waits |
| `USE` of another database, credentials, a syntax error, an unreachable database | The pipeline fails. **Nothing can be approved**: in that case every approval list is removed, even other databases' lists. Fix the cause and push. |

To approve: open the pipeline, read the `approval_required` log, then press ▶ on `deploy_dev_approved`. Only people allowed to merge to `main` can run it. The pipeline still shows *failed* (because `check_scripts` failed), but the deploy ran.

- A `-- @manual-approve:` comment does **not** skip this: a one-off script always needs a person.
- A script asks once. After it has run (or failed), it is never checked again.
- If a later pipeline starts while one waits for approval, both ask; whichever deploy runs first applies the script, and the other skips it.

## 5. More environments (Staging, Production)

The scripts already support `-TargetEnvironment Staging|Production`, reading `STG_CONNECTION_STRING_<DATABASE>` / `PROD_CONNECTION_STRING_<DATABASE>`. The pipeline deploys only to Development, and `SPEC-001 AC-07` (checked by `Tests/VerificationTests.ps1`) forbids `deploy_test`/`deploy_prod` jobs. To add an environment, amend that spec and test first, then add for example:

```yaml
stages: [validate, build, test, manual_approval, deploy_dev, deploy_staging]

deploy_staging:
  stage: deploy_staging
  resource_group: deploy-staging
  dependencies: [build_dacpac]            # the same DACPACs that went to Development
  script:
    - pwsh Scripts/DeployDatabase.ps1 -Database All -TargetEnvironment Staging
    - pwsh Scripts/Invoke-ScriptRunner.ps1 -Database All -TargetEnvironment Staging
  environment:
    name: staging
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
      when: manual                        # a person promotes each release
```

Create `STG_CONNECTION_STRING_<DATABASE>` variables and scope them to the `staging` environment. Note that `check_scripts` reads the **Development** log: a one-off script approved for Development runs in Staging without asking again, so the manual promotion job is the gate there. Use a protected environment (GitLab Premium) to restrict who can run it.

## 6. Optional: scheduled drift detection

Drift detection is not part of the pipeline. To get an alert when someone changes Development by hand, add a job and a pipeline schedule (CI/CD → Schedules):

```yaml
detect_drift:
  stage: test
  needs: [build_dacpac]
  script:
    - pwsh -c 'foreach ($db in (Get-ChildItem Databases -Directory).Name) { pwsh Scripts/DetectDrift.ps1 -Database $db; if ($LASTEXITCODE) { $failed = 1 } }; exit [int]$failed'
  artifacts:
    when: always
    paths: [artifacts/*-DriftReport.xml]
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
```

The job fails (`DetectDrift.ps1` exits `2`) when any database differs from `main`. A scheduled pipeline on `main` also runs the other `main` jobs, including `deploy_dev` (redeploying the same commit changes nothing). To run only drift detection, add `- if: $CI_PIPELINE_SOURCE == "schedule"` with `when: never` as the first rule of those jobs.

## 7. Running outside GitLab

`.gitlab-ci.yml` runs only on GitLab. A GitHub repository can mirror to GitLab ([pull mirroring](https://docs.gitlab.com/ee/user/project/repository/mirror/pull.html)) and keep this pipeline unchanged.

To port the pipeline to another CI system (GitHub Actions, Azure DevOps, Jenkins), each job is a plain `pwsh` command, so only the gates need an equivalent:

| GitLab feature | Needed for |
|---|---|
| Protected, masked variables | Connection strings only on `main` |
| `when: manual` job runnable only by people allowed to merge | Approving risky scripts |
| `resource_group` | One deploy at a time |
| `CI_MERGE_REQUEST_TARGET_BRANCH_NAME`, `CI_COMMIT_*`, `CI_PIPELINE_*` | Concurrent-edit check and `dbo.DeploymentLog` columns (pass `-TargetBranch` to `Test-ConcurrentEdits.ps1`) |
