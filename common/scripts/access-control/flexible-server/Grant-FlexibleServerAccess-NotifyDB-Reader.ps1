<#
.SYNOPSIS
Grant access to postgres flexible server for service (tier-3) managed identity.

.DESCRIPTION
Grant access to postgres flexible server for service (tier-3) managed identity.

.EXAMPLE
.\Grant-FlexibleServerAccess.ps1 
#>

Set-StrictMode -Version 3.0

[string]$PostgresHost = $env:POSTGRES_HOST 
[string]$PostgresDatabase = $env:POSTGRES_DATABASE
[string]$NotificationApiMIClientId = $env:AZURE_CLIENT_ID
[string]$PlatformMITenantId = $env:AZURE_TENANT_ID
[string]$PlatformMISubscriptionId = $env:PLATFORM_MI_SUBSCRIPTION_ID 
[string]$SubscriptionName = $env:SUBSCRIPTION_NAME
[string]$WorkingDirectory = $PWD
[string]$PostgresReaderAdGroup = $env:PG_READER_AD_GROUP
[string]$PostgresWriterAdGroup = $env:PG_WRITER_AD_GROUP

[string]$functionName = $MyInvocation.MyCommand
[DateTime]$startTime = [DateTime]::UtcNow
[int]$exitCode = -1
[bool]$setHostExitCode = (Test-Path -Path ENV:TF_BUILD) -and ($ENV:TF_BUILD -eq "true")
[bool]$enableDebug = (Test-Path -Path ENV:SYSTEM_DEBUG) -and ($ENV:SYSTEM_DEBUG -eq "true")

Set-Variable -Name ErrorActionPreference -Value Continue -scope global
Set-Variable -Name VerbosePreference -Value Continue -Scope global

if ($enableDebug) {
    Set-Variable -Name DebugPreference -Value Continue -Scope global
    Set-Variable -Name InformationPreference -Value Continue -Scope global
}

Write-Host "${functionName} started at $($startTime.ToString('u'))"
Write-Debug "${functionName}:PostgresHost:$PostgresHost"
Write-Debug "${functionName}:PostgresDatabase:$PostgresDatabase"
Write-Debug "${functionName}:SubscriptionName=$SubscriptionName"
Write-Debug "${functionName}:WorkingDirectory=$WorkingDirectory"
Write-Debug "${functionName}:PostgresReaderAdGroup=$PostgresReaderAdGroup"
Write-Debug "${functionName}:PostgresWriterAdGroup=$PostgresWriterAdGroup"

[System.IO.DirectoryInfo]$scriptDir = $PSCommandPath | Split-Path -Parent
Write-Debug "${functionName}:scriptDir.FullName:$($scriptDir.FullName)"

function Get-SQLScriptToGrantReadPermissions {
    [System.Text.StringBuilder]$builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append("GRANT SELECT ON ALL TABLES IN SCHEMA public TO `"$PostgresReaderAdGroup`";")
    [void]$builder.Append("GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO `"$PostgresReaderAdGroup`";")
    [void]$builder.Append("REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM `"$PostgresReaderAdGroup`";")
    [void]$builder.Append("REVOKE EXECUTE ON ALL PROCEDURES IN SCHEMA public FROM `"$PostgresReaderAdGroup`";")
    [void]$builder.Append("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO `"$PostgresReaderAdGroup`";")
    [void]$builder.Append("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO `"$PostgresReaderAdGroup`";")
    return $builder.ToString()
}

[string]$tempFolder=[System.IO.Path]::GetTempPath()
[System.IO.FileInfo]$assignReadPermissionsTempFile = $tempFolder + $(New-Guid).ToString() + ".sql";

try {
    [System.IO.DirectoryInfo]$moduleDir = Join-Path -Path $WorkingDirectory -ChildPath "common/scripts/modules/psql"
    Write-Debug "${functionName}:moduleDir.FullName=$($moduleDir.FullName)"
    Import-Module $moduleDir.FullName -Force

    Write-Host "Connecting to Azure..."
    $azureContext = (Connect-AzAccount -Identity -AccountId $NotificationApiMIClientId -Tenant $PlatformMITenantId -Subscription $PlatformMISubscriptionId).context
    $null = Set-AzContext -Subscription $SubscriptionName -DefaultProfile $azureContext
    Write-Host "Connected to Azure and set context to '$SubscriptionName'"

    Write-Host "Acquiring Access Token..."
    $accessToken = Get-AzAccessToken -ResourceUrl "https://ossrdbms-aad.database.windows.net"
    $ENV:PGPASSWORD = $accessToken.Token
    Write-Host "Access Token Acquired"

    [string]$command = Get-SQLScriptToGrantReadPermissions
    Write-Debug "${functionName}:command=$command"
    
    [string]$content = Set-Content -Path $assignReadPermissionsTempFile.FullName -Value $command -PassThru -Force
    Write-Debug "${functionName}:$($assignReadPermissionsTempFile.FullName)=$content"

    Write-Host "Granting permissions to ${PostgresReaderAdGroup}"
    $null = Invoke-PSQLScript -PostgresHost $PostgresHost -PostgresDatabase $PostgresDatabase -PostgresUsername $PostgresWriterAdGroup -Path $assignReadPermissionsTempFile.FullName
    Write-Host "Granted Access to ${PostgresReaderAdGroup}"

    # Successful exit
    $exitCode = 0
} 
catch {
    $exitCode = -2
    Write-Error $_.Exception.ToString()
    throw $_.Exception
}
finally {
    Remove-Item -Path $assignReadPermissionsTempFile.FullName -Force -ErrorAction SilentlyContinue

    [DateTime]$endTime = [DateTime]::UtcNow
    [Timespan]$duration = $endTime.Subtract($startTime)

    Write-Host "${functionName} finished at $($endTime.ToString('u')) (duration $($duration -f 'g')) with exit code $exitCode"

    if ($setHostExitCode) {
        Write-Debug "${functionName}:Setting host exit code"
        $host.SetShouldExit($exitCode)
    }
    exit $exitCode
}