# Customer Management App (Power Platform)

A simple model-driven Power Apps app for managing customers, backed by a Dataverse
`cmd_customer` table. Built for source control from day one using the standard
Power Platform ALM pattern (solution project + Web API schema deployment).

## What's here

- `src/CustomerManagementSolution/` — the Dataverse solution project, scaffolded with
  `pac solution init` (publisher `CustomerManagementDemo`, prefix `cmd`). This is where
  the exported/unpacked solution (table, forms, views, app module) will live once the
  app is built in Studio.
- `docs/customer-table-schema.md` — the Customer table schema (source of truth).
- `scripts/Deploy-CustomerTable.ps1` — idempotent script that creates the table, its
  columns, and a default view in a Dataverse environment via the Web API.
- `dotnet-tools.json` — pins the Power Platform CLI (`pac`) as a local dotnet tool.

## Prerequisites

- .NET SDK (already used to install `pac` below)
- A Power Platform environment with a Dataverse database, and permission to create tables
- PowerShell `Az.Accounts` module for the deployment script:
  ```powershell
  Install-Module Az.Accounts -Scope CurrentUser
  ```

## Setup

The Power Platform CLI is already installed as a local dotnet tool (`dotnet-tools.json`).
Restore it and sign in to your environment:

```powershell
dotnet tool restore
dotnet tool run pac auth create --url https://<your-org>.crm.dynamics.com
```

## 1. Create the table

```powershell
./scripts/Deploy-CustomerTable.ps1 -EnvironmentUrl https://<your-org>.crm.dynamics.com
```

This creates `cmd_customer` with the columns listed in `docs/customer-table-schema.md`
and an "Active Customers" view. Re-running it is safe — it skips anything that already exists.

## 2. Build the app in Studio

1. Go to [make.powerapps.com](https://make.powerapps.com) in the target environment.
2. **Apps > New app > Model-driven** and name it "Customer Management".
3. Add the `Customer` table and the `Active Customers` view.
4. Save and publish.

## 3. Bring the app into source control

```powershell
dotnet tool run pac solution export --path CustomerManagementSolution.zip --name CustomerManagementSolution
dotnet tool run pac solution unpack --zipfile CustomerManagementSolution.zip --folder src/CustomerManagementSolution/src
```

Commit the result. From here on, treat `src/CustomerManagementSolution` as the source
of truth: change forms/views/sitemap in Studio against a dev environment, then export +
unpack to bring the change back into the repo (or pack + import to push a source change
out to an environment).

## Moving to another environment (test/prod)

```powershell
dotnet tool run pac solution pack --zipfile CustomerManagementSolution.zip --folder src/CustomerManagementSolution/src
dotnet tool run pac auth create --url https://<target-org>.crm.dynamics.com
dotnet tool run pac solution import --path CustomerManagementSolution.zip
```
