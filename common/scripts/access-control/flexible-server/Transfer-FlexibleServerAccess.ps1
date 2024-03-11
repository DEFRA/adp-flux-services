<#
.SYNOPSIS
Transfer access from Team MI to Postgres Writer AD group

.DESCRIPTION
Transfer access from Team MI to Postgres Writer AD group

.EXAMPLE
.\Transfer-FlexibleServerAccess.ps1 
#>

Set-StrictMode -Version 3.0

[string]$PostgresHost = $env:POSTGRES_HOST 
[string]$PostgresDatabase = $env:POSTGRES_DATABASE
[string]$MIName = $env:MI_NAME
[string]$PlatformMIName = $env:PLATFORM_MI_NAME
[string]$MIClientId = $env:AZURE_CLIENT_ID
[string]$MITenantid = $env:AZURE_TENANT_ID
[string]$MISubscriptionId = $env:MI_SUBSCRIPTION_ID 
[string]$MIFederatedTokenFile = $env:AZURE_FEDERATED_TOKEN_FILE
[string]$SubscriptionName = $env:SUBSCRIPTION_NAME
[string]$Mode = $env:MODE
[string]$WorkingDirectory = $PWD
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
Write-Debug "${functionName}:MIName:$MIName"
Write-Debug "${functionName}:PlatformMIName:$PlatformMIName"
Write-Debug "${functionName}:MIClientId:$MIClientId"
Write-Debug "${functionName}:MITenantid=$MITenantid"
Write-Debug "${functionName}:SubscriptionName=$SubscriptionName"
Write-Debug "${functionName}:Mode=$Mode"
Write-Debug "${functionName}:WorkingDirectory=$WorkingDirectory"
Write-Debug "${functionName}:PostgresWriterAdGroup=$PostgresWriterAdGroup"

[System.IO.DirectoryInfo]$scriptDir = $PSCommandPath | Split-Path -Parent
Write-Debug "${functionName}:scriptDir.FullName:$($scriptDir.FullName)"

function Get-SQLScriptToCreatePrincipal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PgDb
    )
    [string]$functionName = $MyInvocation.MyCommand
    Write-Debug "${functionName}:PgDb=$PgDb"

    [System.Text.StringBuilder]$builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append(' DO $$ ')
    [void]$builder.Append(' BEGIN ')
    [void]$builder.Append("     IF NOT EXISTS (SELECT 1 FROM pgaadauth_list_principals(false) WHERE rolname='$PostgresWriterAdGroup') THEN ")
    [void]$builder.Append("         RAISE NOTICE 'CREATING PRINCIPAL FOR MANAGED IDENTITY:$PostgresWriterAdGroup';")
    [void]$builder.Append("         PERFORM pgaadauth_create_principal('$PostgresWriterAdGroup', false, false); ");
    [void]$builder.Append("         RAISE NOTICE 'PRINCIPAL FOR MANAGED IDENTITY CREATED:$PostgresWriterAdGroup';")
    [void]$builder.Append('     ELSE ')
    [void]$builder.Append("         RAISE NOTICE 'PRINCIPAL FOR MANAGED IDENTITY ALREADY EXISTS:$PostgresWriterAdGroup';")
    [void]$builder.Append('     END IF; ')
    [void]$builder.Append("     EXECUTE ( 'GRANT CONNECT ON DATABASE `"$PgDb`" TO `"$PostgresWriterAdGroup`"' );")
    [void]$builder.Append("     RAISE NOTICE 'GRANTED CONNECT TO DATABASE';")
    [void]$builder.Append(" EXCEPTION ")
    [void]$builder.Append("     WHEN OTHERS THEN  ")
    [void]$builder.Append("         RAISE EXCEPTION 'ERROR DURING PRINCIPAL CREATION/GRANT CONNECT: %', SQLERRM; ")
    [void]$builder.Append(' END $$' )
    return $builder.ToString()
}

function Get-SQLScriptToGrantAllPermissions {
    [System.Text.StringBuilder]$builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append("GRANT ALL ON SCHEMA public TO `"$PostgresWriterAdGroup`";")
    [void]$builder.Append("GRANT ALL ON ALL TABLES IN SCHEMA public TO `"$PostgresWriterAdGroup`";")
    [void]$builder.Append("GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO `"$PostgresWriterAdGroup`";")
    [void]$builder.Append("GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO `"$PostgresWriterAdGroup`";")
    [void]$builder.Append("GRANT ALL ON ALL PROCEDURES IN SCHEMA public TO `"$PostgresWriterAdGroup`";")
    return $builder.ToString()
}

function Get-SQLScriptToRevokeAllPermissions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PgDb
    )
    [string]$functionName = $MyInvocation.MyCommand
    Write-Debug "${functionName}:PgDb=$PgDb"

    [System.Text.StringBuilder]$builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append("REVOKE ALL PRIVILEGES ON DATABASE `"$PgDb`" FROM `"$MIName`";")
    [void]$builder.Append("REVOKE ALL ON ALL TABLES IN SCHEMA PUBLIC FROM `"$MIName`";")
    [void]$builder.Append("REVOKE ALL PRIVILEGES ON SCHEMA PUBLIC FROM `"$MIName`";")
    [void]$builder.Append("REVOKE ALL ON SCHEMA public FROM `"$MIName`";")
    return $builder.ToString()
}

function Get-SQLScriptToGrantRoleAdmin {
    [System.Text.StringBuilder]$builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append("GRANT `"$PostgresWriterAdGroup`" TO `"$MIName`" WITH ADMIN OPTION;")
    return $builder.ToString()
}

function Get-SQLScriptToReAssignOwner {
    [System.Text.StringBuilder]$builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append("REASSIGN OWNED BY `"$MIName`" TO `"$PostgresWriterAdGroup`";")
    return $builder.ToString()
}

try {
    [System.IO.DirectoryInfo]$moduleDir = Join-Path -Path $WorkingDirectory -ChildPath "common/scripts/modules/psql"
    Write-Debug "${functionName}:moduleDir.FullName=$($moduleDir.FullName)"
    Import-Module $moduleDir.FullName -Force

    Write-Host "Connecting to Azure..."
    $null = Connect-AzAccount -ServicePrincipal -ApplicationId $MIClientId -FederatedToken $(Get-Content $MIFederatedTokenFile -raw) -Tenant $MITenantid -Subscription $MISubscriptionId
    $null = Set-AzContext -Subscription $SubscriptionName
    Write-Host "Connected to Azure and set context to '$SubscriptionName'"

    Write-Host "Acquiring Access Token..."
    $accessToken = Get-AzAccessToken -ResourceUrl "https://ossrdbms-aad.database.windows.net"
    $ENV:PGPASSWORD = $accessToken.Token
    Write-Host "Access Token Acquired"

    $dbList = $PostgresDatabase.Split(",") | ForEach-Object { $_.Trim() }
    $dbList | ForEach-Object {
        # Run with db-aad-admin MI
        if ($Mode -eq 'setup') {
            [string]$command = Get-SQLScriptToCreatePrincipal -PgDb $_
            Write-Debug "${functionName}:command=$command"
    
            [System.IO.FileInfo]$createPrincipalTempFile = [System.IO.Path]::GetTempFileName()
            [string]$content = Set-Content -Path $createPrincipalTempFile.FullName -Value $command -PassThru -Force
            Write-Debug "${functionName}:$($createPrincipalTempFile.FullName)=$content"

            Write-Host "Creating Principal in ${PostgresHost}"
            $null = Invoke-PSQLScript -PostgresHost $PostgresHost -PostgresDatabase "postgres" -PostgresUsername $PlatformMIName -Path $createPrincipalTempFile.FullName
            Write-Host "Granted Access to ${PostgresHost}"

            [string]$command = Get-SQLScriptToGrantRoleAdmin
            Write-Debug "${functionName}:command=$command"
    
            [System.IO.FileInfo]$grantRoleAdminTempFile = [System.IO.Path]::GetTempFileName()
            [string]$content = Set-Content -Path $grantRoleAdminTempFile.FullName -Value $command -PassThru -Force
            Write-Debug "${functionName}:$($grantRoleAdminTempFile.FullName)=$content"

            Write-Host "Granting role admin"
            $null = Invoke-PSQLScript -PostgresHost $PostgresHost -PostgresDatabase 'postgres' -PostgresUsername $PlatformMIName -Path $grantRoleAdminTempFile.FullName
            Write-Host "Granted role admin"
        }

        # Run with team MI (existing owner)
        if ($Mode -eq 'revoke') {
            [string]$command = Get-SQLScriptToRevokeAllPermissions -PgDb $_
            Write-Debug "${functionName}:command=$command"
    
            [System.IO.FileInfo]$revokePermissionsTempFile = [System.IO.Path]::GetTempFileName()
            [string]$content = Set-Content -Path $revokePermissionsTempFile.FullName -Value $command -PassThru -Force
            Write-Debug "${functionName}:$($revokePermissionsTempFile.FullName)=$content"

            Write-Host "Revoking permissions from ${MIName}"
            $null = Invoke-PSQLScript -PostgresHost $PostgresHost -PostgresDatabase $_ -PostgresUsername $MIName -Path $revokePermissionsTempFile.FullName
            Write-Host "Revoked perms from ${MIName}"
        }

        # Run with postgres writer AD group
        if ($Mode -eq 'reassign') {
            [string]$command = Get-SQLScriptToReAssignOwner
            Write-Debug "${functionName}:command=$command"
    
            [System.IO.FileInfo]$reassignOwnerTempFile = [System.IO.Path]::GetTempFileName()
            [string]$content = Set-Content -Path $reassignOwnerTempFile.FullName -Value $command -PassThru -Force
            Write-Debug "${functionName}:$($reassignOwnerTempFile.FullName)=$content"

            Write-Host "Reassigning owner to ${PostgresWriterAdGroup}"
            $null = Invoke-PSQLScript -PostgresHost $PostgresHost -PostgresDatabase $_ -PostgresUsername $MIName -Path $reassignOwnerTempFile.FullName
            Write-Host "Reassigned owner to ${PostgresWriterAdGroup}"

            [string]$command = Get-SQLScriptToGrantAllPermissions
            Write-Debug "${functionName}:command=$command"
    
            [System.IO.FileInfo]$assignAllPermissionsTempFile = [System.IO.Path]::GetTempFileName()
            [string]$content = Set-Content -Path $assignAllPermissionsTempFile.FullName -Value $command -PassThru -Force
            Write-Debug "${functionName}:$($assignAllPermissionsTempFile.FullName)=$content"

            Write-Host "Granting permissions to ${PostgresWriterAdGroup}"
            $null = Invoke-PSQLScript -PostgresHost $PostgresHost -PostgresDatabase $_ -PostgresUsername $MIName -Path $assignAllPermissionsTempFile.FullName
            Write-Host "Granted Access to ${PostgresWriterAdGroup}"
        }
    }
    # Successful exit
    $exitCode = 0
} 
catch {
    $exitCode = -2
    Write-Error $_.Exception.ToString()
    throw $_.Exception
}
finally {
    if ($Mode -eq 'setup') {
        Remove-Item -Path $createPrincipalTempFile.FullName -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $grantRoleAdminTempFile.FullName -Force -ErrorAction SilentlyContinue
    }
    if ($Mode -eq 'revoke') {
        Remove-Item -Path $revokePermissionsTempFile.FullName -Force -ErrorAction SilentlyContinue
    }
    if ($Mode -eq 'reassign') {
        Remove-Item -Path $reassignOwnerTempFile.FullName -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $assignAllPermissionsTempFile.FullName -Force -ErrorAction SilentlyContinue
    }    

    [DateTime]$endTime = [DateTime]::UtcNow
    [Timespan]$duration = $endTime.Subtract($startTime)

    Write-Host "${functionName} finished at $($endTime.ToString('u')) (duration $($duration -f 'g')) with exit code $exitCode"

    if ($setHostExitCode) {
        Write-Debug "${functionName}:Setting host exit code"
        $host.SetShouldExit($exitCode)
    }
    exit $exitCode
}