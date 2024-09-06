[bool]$enableDebug = $ENV:SYSTEM_DEBUG -eq "true"

if ($enableDebug) {
    Set-Variable -Name DebugPreference -Value Continue -Scope global
    Set-Variable -Name InformationPreference -Value Continue -Scope global
}
 
[string]$TeamMIClientId = $env:AZURE_CLIENT_ID
[string]$TeamMITenantId = $env:AZURE_TENANT_ID
[string]$TeamMISubscriptionId = $env:TEAM_MI_SUBSCRIPTION_ID
[string]$TeamMIFederatedTokenFile = $env:AZURE_FEDERATED_TOKEN_FILE
[string]$SubscriptionName = $env:SUBSCRIPTION_NAME
[string]$ServiceMIName = $env:SERVICE_MI_NAME
[string]$PostgresHost = $env:AZURE_CLIENT_ID
[string]$PostgresDatabase = $env:AZURE_CLIENT_ID

Write-Host "Running the powershell script with parameters $Params"

function Get-SQLCommands {
    [System.Text.StringBuilder]$builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append("SELECT * FROM public.packingList;")
    return $builder.ToString()
}

try {
    [System.IO.DirectoryInfo]$moduleDir = Join-Path -Path $WorkingDirectory -ChildPath "common/scripts/modules/psql"
    Write-Debug "${functionName}:moduleDir.FullName=$($moduleDir.FullName)"
    Import-Module $moduleDir.FullName -Force

    Write-Host "Connecting to Azure..."
    $null = Connect-AzAccount -ServicePrincipal -ApplicationId $TeamMIClientId -FederatedToken $(Get-Content $TeamMIFederatedTokenFile -raw) -Tenant $TeamMITenantId -Subscription $TeamMISubscriptionId
    $null = Set-AzContext -Subscription $SubscriptionName
    Write-Host "Connected to Azure and set context to '$SubscriptionName'"

    Write-Host "Acquiring Access Token..."
    $accessToken = Get-AzAccessToken -ResourceUrl "https://ossrdbms-aad.database.windows.net"
    $ENV:PGPASSWORD = $accessToken.Token
    Write-Host "Access Token Acquired"

    [string]$command = Get-SQLCommands
    Write-Debug "${functionName}:command=$command"
    
    [System.IO.FileInfo]$assignPermissionsTempFile = [System.IO.Path]::GetTempFileName()
    [string]$content = Set-Content -Path $assignPermissionsTempFile.FullName -Value $command -PassThru -Force
    Write-Debug "${functionName}:$($assignPermissionsTempFile.FullName)=$content"
    
    Write-Host "Selecting data from the table ${ServiceMIName}"
    $null = Invoke-PSQLScript -PostgresHost $PostgresHost -PostgresDatabase $PostgresDatabase -PostgresUsername $PostgresWriterAdGroup -Path $assignPermissionsTempFile.FullName
    Write-Host "Select data from ${PostgresHost} successfully"

    # Successful exit
    $exitCode = 0
} 
catch {
    $exitCode = -2
    Write-Error $_.Exception.ToString()
    throw $_.Exception
}
finally {
    Remove-Item -Path $assignPermissionsTempFile.FullName -Force -ErrorAction SilentlyContinue
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