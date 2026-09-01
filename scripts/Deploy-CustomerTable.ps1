<#
.SYNOPSIS
    Creates the Customer table (cmd_customer), its columns, and a default view
    in a Dataverse environment via the Web API, per docs/customer-table-schema.md.

.DESCRIPTION
    This is the schema-deployment half of the Customer Management app's ALM story.
    It is idempotent: re-running it skips anything that already exists.

    After running this script, finish the app in Power Apps Studio:
      1. Open make.powerapps.com in the target environment.
      2. App Designer > New model-driven app > name it "Customer Management".
      3. Add the cmd_customer table and the "Active Customers" view this script creates.
      4. Save & publish.
      5. Export the solution as unmanaged and unpack it into this repo:
           dotnet tool run pac solution export --path CustomerManagementSolution.zip --name CustomerManagementSolution
           dotnet tool run pac solution unpack --zipfile CustomerManagementSolution.zip --folder src/CustomerManagementSolution/src
    That checks the model-driven app, forms, and sitemap into source control alongside
    the solution project already scaffolded here.

.PARAMETER EnvironmentUrl
    The Dataverse environment URL, e.g. https://org12345.crm.dynamics.com

.NOTES
    Requires the Az.Accounts PowerShell module (Install-Module Az.Accounts -Scope CurrentUser)
    for interactive sign-in and Dataverse token acquisition.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentUrl
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    throw "Az.Accounts module not found. Install it first: Install-Module Az.Accounts -Scope CurrentUser"
}
Import-Module Az.Accounts -ErrorAction Stop

$EnvironmentUrl = $EnvironmentUrl.TrimEnd('/')

if (-not (Get-AzContext)) {
    Connect-AzAccount | Out-Null
}

function Get-DataverseToken {
    $token = (Get-AzAccessToken -ResourceUrl $EnvironmentUrl).Token
    # Az.Accounts 5.x returns Token as a SecureString; older versions return plain text.
    if ($token -is [System.Security.SecureString]) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token)
        try {
            return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
    return $token
}

function Invoke-Dataverse {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body,
        [switch]$IgnoreNotFound
    )
    $uri = "$EnvironmentUrl/api/data/v9.2/$Path"
    $headers = @{
        Authorization      = "Bearer $(Get-DataverseToken)"
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
        Accept             = 'application/json'
    }
    $params = @{
        Method  = $Method
        Uri     = $uri
        Headers = $headers
    }
    if ($Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 10)
        $params.ContentType = 'application/json; charset=utf-8'
    }
    try {
        return Invoke-RestMethod @params
    } catch {
        $resp = $_.Exception.Response
        if ($IgnoreNotFound -and $resp -and [int]$resp.StatusCode -eq 404) {
            return $null
        }
        $errorBody = $null
        if ($_.ErrorDetails) { $errorBody = $_.ErrorDetails.Message }
        throw "Dataverse request failed ($Method $Path): $($_.Exception.Message)`n$errorBody"
    }
}

function Test-TableExists {
    param([string]$LogicalName)
    $result = Invoke-Dataverse -Method GET -Path "EntityDefinitions(LogicalName='$LogicalName')?`$select=LogicalName" -IgnoreNotFound
    return $null -ne $result
}

function Test-AttributeExists {
    param([string]$EntityLogicalName, [string]$AttributeLogicalName)
    $result = Invoke-Dataverse -Method GET -Path "EntityDefinitions(LogicalName='$EntityLogicalName')/Attributes(LogicalName='$AttributeLogicalName')?`$select=LogicalName" -IgnoreNotFound
    return $null -ne $result
}

Write-Host "Target environment: $EnvironmentUrl" -ForegroundColor Cyan

# 1. Create the cmd_customer table (with its primary name column, cmd_name) if missing.
if (Test-TableExists -LogicalName 'cmd_customer') {
    Write-Host "Table cmd_customer already exists, skipping creation." -ForegroundColor Yellow
} else {
    Write-Host "Creating table cmd_customer..." -ForegroundColor Cyan
    $entityMetadata = @{
        '@odata.type'          = 'Microsoft.Dynamics.CRM.EntityMetadata'
        SchemaName             = 'cmd_Customer'
        DisplayName            = @{
            '@odata.type'     = 'Microsoft.Dynamics.CRM.Label'
            LocalizedLabels   = @(@{ '@odata.type' = 'Microsoft.Dynamics.CRM.LocalizedLabel'; Label = 'Customer'; LanguageCode = 1033 })
        }
        DisplayCollectionName   = @{
            '@odata.type'     = 'Microsoft.Dynamics.CRM.Label'
            LocalizedLabels   = @(@{ '@odata.type' = 'Microsoft.Dynamics.CRM.LocalizedLabel'; Label = 'Customers'; LanguageCode = 1033 })
        }
        Description             = @{
            '@odata.type'     = 'Microsoft.Dynamics.CRM.Label'
            LocalizedLabels   = @(@{ '@odata.type' = 'Microsoft.Dynamics.CRM.LocalizedLabel'; Label = 'A customer managed by the Customer Management app.'; LanguageCode = 1033 })
        }
        OwnershipType            = 'UserOwned'
        IsActivity               = $false
        HasNotes                 = $true
        HasActivities            = $false
        Attributes               = @(
            @{
                '@odata.type'  = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
                SchemaName     = 'cmd_Name'
                IsPrimaryName  = $true
                RequiredLevel  = @{ Value = 'ApplicationRequired' }
                MaxLength      = 200
                FormatName     = @{ Value = 'Text' }
                DisplayName    = @{
                    '@odata.type'   = 'Microsoft.Dynamics.CRM.Label'
                    LocalizedLabels = @(@{ '@odata.type' = 'Microsoft.Dynamics.CRM.LocalizedLabel'; Label = 'Customer Name'; LanguageCode = 1033 })
                }
            }
        )
    }
    Invoke-Dataverse -Method POST -Path 'EntityDefinitions' -Body $entityMetadata | Out-Null
    Write-Host "Table cmd_customer created." -ForegroundColor Green
}

# 2. Add the remaining columns, one at a time, skipping any that already exist.
function New-StringLabel([string]$Text) {
    @{
        '@odata.type'     = 'Microsoft.Dynamics.CRM.Label'
        LocalizedLabels   = @(@{ '@odata.type' = 'Microsoft.Dynamics.CRM.LocalizedLabel'; Label = $Text; LanguageCode = 1033 })
    }
}

$stringColumns = @(
    @{ Logical = 'cmd_emailaddress'; Schema = 'cmd_EmailAddress'; Display = 'Email';   MaxLength = 100; Format = 'Email' }
    @{ Logical = 'cmd_phonenumber';  Schema = 'cmd_PhoneNumber';  Display = 'Phone';    MaxLength = 50;  Format = 'Phone' }
    @{ Logical = 'cmd_company';      Schema = 'cmd_Company';      Display = 'Company';  MaxLength = 200; Format = 'Text' }
    @{ Logical = 'cmd_address';      Schema = 'cmd_Address';      Display = 'Address';  MaxLength = 250; Format = 'Text' }
)

foreach ($col in $stringColumns) {
    if (Test-AttributeExists -EntityLogicalName 'cmd_customer' -AttributeLogicalName $col.Logical) {
        Write-Host "Column $($col.Logical) already exists, skipping." -ForegroundColor Yellow
        continue
    }
    Write-Host "Creating column $($col.Logical)..." -ForegroundColor Cyan
    $attr = @{
        '@odata.type'  = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
        SchemaName     = $col.Schema
        RequiredLevel  = @{ Value = 'None' }
        MaxLength      = $col.MaxLength
        FormatName     = @{ Value = $col.Format }
        DisplayName    = New-StringLabel $col.Display
    }
    Invoke-Dataverse -Method POST -Path "EntityDefinitions(LogicalName='cmd_customer')/Attributes" -Body $attr | Out-Null
}

if (Test-AttributeExists -EntityLogicalName 'cmd_customer' -AttributeLogicalName 'cmd_notes') {
    Write-Host "Column cmd_notes already exists, skipping." -ForegroundColor Yellow
} else {
    Write-Host "Creating column cmd_notes..." -ForegroundColor Cyan
    $memoAttr = @{
        '@odata.type'  = 'Microsoft.Dynamics.CRM.MemoAttributeMetadata'
        SchemaName     = 'cmd_Notes'
        RequiredLevel  = @{ Value = 'None' }
        MaxLength      = 2000
        DisplayName    = New-StringLabel 'Notes'
    }
    Invoke-Dataverse -Method POST -Path "EntityDefinitions(LogicalName='cmd_customer')/Attributes" -Body $memoAttr | Out-Null
}

if (Test-AttributeExists -EntityLogicalName 'cmd_customer' -AttributeLogicalName 'cmd_status') {
    Write-Host "Column cmd_status already exists, skipping." -ForegroundColor Yellow
} else {
    Write-Host "Creating column cmd_status..." -ForegroundColor Cyan
    $choiceAttr = @{
        '@odata.type'  = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
        SchemaName     = 'cmd_Status'
        RequiredLevel  = @{ Value = 'None' }
        DisplayName    = New-StringLabel 'Status'
        OptionSet      = @{
            '@odata.type'   = 'Microsoft.Dynamics.CRM.OptionSetMetadata'
            IsGlobal        = $false
            OptionSetType   = 'Picklist'
            Options         = @(
                @{ Value = 1; Label = New-StringLabel 'Prospect' }
                @{ Value = 2; Label = New-StringLabel 'Active' }
                @{ Value = 3; Label = New-StringLabel 'Inactive' }
            )
        }
        DefaultFormValue = 1
    }
    Invoke-Dataverse -Method POST -Path "EntityDefinitions(LogicalName='cmd_customer')/Attributes" -Body $choiceAttr | Out-Null
}

if (Test-AttributeExists -EntityLogicalName 'cmd_customer' -AttributeLogicalName 'cmd_tags') {
    Write-Host "Column cmd_tags already exists, skipping." -ForegroundColor Yellow
} else {
    Write-Host "Creating column cmd_tags..." -ForegroundColor Cyan
    $tagsAttr = @{
        '@odata.type'  = 'Microsoft.Dynamics.CRM.MultiSelectPicklistAttributeMetadata'
        SchemaName     = 'cmd_Tags'
        RequiredLevel  = @{ Value = 'None' }
        DisplayName    = New-StringLabel 'Tags'
        OptionSet      = @{
            '@odata.type'   = 'Microsoft.Dynamics.CRM.OptionSetMetadata'
            IsGlobal        = $false
            OptionSetType   = 'Picklist'
            Options         = @(
                @{ Value = 1; Label = New-StringLabel 'VIP' }
                @{ Value = 2; Label = New-StringLabel 'New' }
                @{ Value = 3; Label = New-StringLabel 'High Value' }
                @{ Value = 4; Label = New-StringLabel 'At Risk' }
                @{ Value = 5; Label = New-StringLabel 'Referral' }
            )
        }
    }
    Invoke-Dataverse -Method POST -Path "EntityDefinitions(LogicalName='cmd_customer')/Attributes" -Body $tagsAttr | Out-Null
}

# 3. Publish all customizations so the new table/columns are usable.
Write-Host "Publishing customizations..." -ForegroundColor Cyan
Invoke-Dataverse -Method POST -Path 'PublishAllXml' -Body @{} | Out-Null

# 4. Create the "Active Customers" view if missing.
$existingView = Invoke-Dataverse -Method GET -Path "savedqueries?`$filter=returnedtypecode eq 'cmd_customer' and name eq 'Active Customers'&`$select=savedqueryid" -IgnoreNotFound
if ($existingView -and $existingView.value.Count -gt 0) {
    Write-Host "View 'Active Customers' already exists, skipping." -ForegroundColor Yellow
} else {
    Write-Host "Creating view 'Active Customers'..." -ForegroundColor Cyan
    $fetchXml = @"
<fetch version="1.0" output-format="xml-platform" mapping="logical" distinct="false">
  <entity name="cmd_customer">
    <attribute name="cmd_name" />
    <attribute name="cmd_emailaddress" />
    <attribute name="cmd_phonenumber" />
    <attribute name="cmd_company" />
    <attribute name="cmd_status" />
    <attribute name="cmd_tags" />
    <order attribute="cmd_name" descending="false" />
    <filter type="and">
      <condition attribute="statecode" operator="eq" value="0" />
    </filter>
  </entity>
</fetch>
"@
    $layoutXml = @'
<grid name="resultset" object="10000" jump="cmd_name" select="1" icon="1" preview="1">
  <row name="result" id="cmd_customerid">
    <cell name="cmd_name" width="200" />
    <cell name="cmd_emailaddress" width="200" />
    <cell name="cmd_phonenumber" width="150" />
    <cell name="cmd_company" width="200" />
    <cell name="cmd_status" width="120" />
    <cell name="cmd_tags" width="180" />
  </row>
</grid>
'@
    $view = @{
        name              = 'Active Customers'
        returnedtypecode  = 'cmd_customer'
        querytype         = 0
        isquickfindquery  = $false
        isdefault         = $true
        fetchxml          = $fetchXml
        layoutxml         = $layoutXml
    }
    Invoke-Dataverse -Method POST -Path 'savedqueries' -Body $view | Out-Null
}

Write-Host "Done. Table cmd_customer, its columns, and the Active Customers view are deployed." -ForegroundColor Green
Write-Host "Next: build the model-driven app in Studio and export it back into source control (see script header)." -ForegroundColor Green
