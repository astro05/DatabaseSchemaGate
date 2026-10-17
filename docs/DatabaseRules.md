# Database Rules

The standards every database in this repository follows. Items marked ✔ are enforced by the pipeline; the rest are reviewed in merge requests.

## 1. Single source of truth

- Git is the sole authority for database definitions. If a table, view, function or procedure is not in Git, it does not officially exist.
- No manual schema changes on shared environments. An emergency fix made directly in a database is brought into Git the same day ([Git Workflow](Git-Workflow.md#4-hotfixes-made-directly-in-a-database)).
- ✔ No credentials or connection strings in the repository.

## 2. One object per file

- Exactly one object per file, in the folder for its type:

  | Object | Path |
  |---|---|
  | Table | `Databases/<Database>/Tables/<schema>.<Name>.sql` |
  | Stored procedure | `Databases/<Database>/StoredProcedures/<schema>.<Name>.sql` |
  | View | `Databases/<Database>/Views/<schema>.<Name>.sql` |
  | Function | `Databases/<Database>/Functions/<schema>.<Name>.sql` |
  | Index (if not in the table file), schema, type, sequence, synonym | `Indexes/`, `Schemas/`, `Types/`, `Sequences/`, `Synonyms/` |

- Suggested name prefixes: `usp_` for procedures, `vw_` for views, `fn_` for functions. Pick a convention per database and keep to it.

## 3. Coding standards

- ✔ Every stored procedure contains `SET NOCOUNT ON;`.
- ✔ Object definitions and the targets of `UPDATE`, `DELETE`, `INSERT`, `TRUNCATE`, `ALTER TABLE` and `DROP TABLE` are schema-qualified: `[dbo].[Customer]`, not `Customer`. Temp tables (`#t`) and table variables (`@t`) are exempt.
- ✔ No `USE <database>` in `Databases/` files: the deploy chooses the database.
- ✔ `UPDATE` without `WHERE` needs `-- @manual-approve: <reason>` on the line before it.
- Name constraints explicitly: `PK_<Table>`, `FK_<Table>_<Referenced>`, `DF_<Table>_<Column>`, `IX_<Table>_<Columns>`. Unnamed constraints get random names that differ per server and show up as drift.
- Prefer `DATETIME2` and UTC (`SYSUTCDATETIME()`) for timestamps.

## 4. Destructive changes

- ✔ Deploys never drop objects and never lose data silently. Data-losing changes follow [Development: Changes that could lose data](Development.md#4-changes-that-could-lose-data).
- ✔ Dropping objects, and `UPDATE`/`DELETE` without `WHERE`, in one-off scripts need a person's approval in CI ([ScriptRunner](ScriptRunner.md)).
- ✔ Production rules of the safety validator block `DROP DATABASE`, `DROP TABLE` and `TRUNCATE TABLE` in `Databases/`.

## 5. Every database

- ✔ Has its own `<Name>.sqlproj`, listed in `Databases.sln`.
- ✔ Has `Deployment/PreDeployment.sql`, `Deployment/PostDeployment.sql` and `Tables/dbo.DeploymentLog.sql`.
- ✔ Has its own connection string per environment, naming that database.
