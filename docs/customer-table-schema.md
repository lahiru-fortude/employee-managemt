# Customer table schema

Table (Dataverse entity): `cmd_customer` — "Customer"
Publisher prefix: `cmd` (CustomerManagementDemo, set in `src/CustomerManagementSolution/src/Other/Solution.xml`)

| Column (logical name)   | Display name  | Type                          | Notes                                  |
|--------------------------|---------------|--------------------------------|-----------------------------------------|
| `cmd_name`               | Customer Name | Single line of text (primary)  | Created automatically as the primary name column |
| `cmd_emailaddress`       | Email         | Single line of text (Email)    | max length 100 |
| `cmd_phonenumber`        | Phone         | Single line of text (Phone)    | max length 50 |
| `cmd_company`            | Company       | Single line of text            | max length 200 |
| `cmd_address`            | Address       | Single line of text            | max length 250 |
| `cmd_status`             | Status        | Choice (option set)            | Prospect (1), Active (2), Inactive (3) — default Prospect |
| `cmd_tags`               | Tags          | Choices (multi-select option set) | VIP (1), New (2), High Value (3), At Risk (4), Referral (5) — for segmenting customers |
| `cmd_notes`              | Notes         | Multiple lines of text (memo)  | max length 2000 |

Plus the standard Dataverse system columns (`createdon`, `modifiedon`, `ownerid`, `statecode`, `statuscode`, etc.) that every table gets for free.

## View

`Active Customers` — a public saved query on `cmd_customer` filtering `statecode = 0` (Active), showing Customer Name, Email, Phone, Company, Status, Tags.

## App

`Customer Management` — a model-driven app exposing the `cmd_customer` table via the `Active Customers` view, with the default main form (Name, Email, Phone, Company, Address, Status, Notes).

This spec is the source of truth for `scripts/Deploy-CustomerTable.ps1`. If you change the schema (add/remove/rename a column, change an option set, etc.), update every one of these in lockstep:

1. The column table above (this file).
2. The primary name column definition in the `Attributes` array of the entity-create block — `scripts/Deploy-CustomerTable.ps1:135`.
3. The `$stringColumns` array (for simple single-line-of-text columns) — `scripts/Deploy-CustomerTable.ps1:175`. Columns with a different type (memo, choice, multi-select choice) are defined individually further down in the same section.
4. The `<attribute>` list in `$fetchXml` and the `<cell>` list in `$layoutXml` for the "Active Customers" view — `scripts/Deploy-CustomerTable.ps1:252` and `:268`.
