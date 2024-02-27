Set-StrictMode -Version 3.0

[string]$ManagedIdentityName = $env:TEAM_MI_NAME
[string]$ADGroupName = $env:PG_WRITER_AD_GROUP
[string]$ServicePrincipalClientId = $env:SP_CLIENT_ID_KV
[string]$ServicePrincipalClientSecret = $env:SP_CLIENT_SECRET_KV
[string]$KeyVaultName = $env:KEY_VAULT_NAME
[string]$TenantId = $env:AZURE_TENANT_ID
[string]$PlatformMIClientId = $env:AZURE_CLIENT_ID
[string]$PlatformMIFederatedTokenFile = $env:AZURE_FEDERATED_TOKEN_FILE
[string]$SubscriptionId = $env:SSV_SHARED_SUBSCRIPTION_ID
[string]$WorkingDirectory = $PWD

[string]$functionName = $MyInvocation.MyCommand
[DateTime]$startTime = [DateTime]::UtcNow
[int]$exitCode = -1
[bool]$setHostExitCode = (Test-Path -Path ENV:TF_BUILD) -and ($ENV:TF_BUILD -eq "true")
[bool]$enableDebug = (Test-Path -Path ENV:SYSTEM_DEBUG) -and ($ENV:SYSTEM_DEBUG -eq "true")

Set-Variable -Name ErrorActionPreference -Value Continue -Scope global
Set-Variable -Name VerbosePreference -Value Continue -Scope global

if ($enableDebug) {
    Set-Variable -Name DebugPreference -Value Continue -Scope global
    Set-Variable -Name InformationPreference -Value Continue -Scope global
}

Write-Host "${functionName} started at $($startTime.ToString('u'))"
Write-Debug "${functionName}:ManagedIdentityName=$ManagedIdentityName"
Write-Debug "${functionName}:ADGroupName=$ADGroupName"
Write-Debug "${functionName}:ServicePrincipalClientId=$ServicePrincipalClientId"
Write-Debug "${functionName}:ServicePrincipalClientSecret=$ServicePrincipalClientSecret"
Write-Debug "${functionName}:KeyVaultName=$KeyVaultName"
Write-Debug "${functionName}:TenantId=$TenantId"
Write-Debug "${functionName}:PlatformMIClientId=$PlatformMIClientId"
Write-Debug "${functionName}:PlatformMIFederatedTokenFile=$PlatformMIFederatedTokenFile"
Write-Debug "${functionName}:SubscriptionId=$SubscriptionId"
Write-Debug "${functionName}:WorkingDirectory=$WorkingDirectory"

try {
    [System.IO.DirectoryInfo]$scriptDir = $PSCommandPath | Split-Path -Parent
    Write-Debug "${functionName}:scriptDir.FullName=$($scriptDir.FullName)"

    [System.IO.DirectoryInfo]$moduleDir = Join-Path -Path $WorkingDirectory -ChildPath "common/scripts/modules/keyvault"
    Write-Debug "${functionName}:moduleDir.FullName=$($moduleDir.FullName)"
    Import-Module $moduleDir.FullName -Force -Verbose:$false

    Write-Host "Connecting to Azure with Platform MI"
    $null = Connect-AzAccount -ServicePrincipal -ApplicationId $PlatformMIClientId -FederatedToken $(Get-Content $PlatformMIFederatedTokenFile -raw) -Tenant $TenantId -Subscription $SubscriptionId

    Write-Host "Connected to Azure and set context to '$SubscriptionId'"

    $SPClientId = Get-KeyVaultSecret -KeyVaultName $KeyVaultName -SecretName $ServicePrincipalClientId
    $SPClientSecret = Get-KeyVaultSecret -KeyVaultName $KeyVaultName -SecretName $ServicePrincipalClientSecret

    Disconnect-AzAccount | Out-Null
    Write-Host "Disconnected from Azure with Platform MI"

    $SecureClientSecret = ConvertTo-SecureString -String $SPClientSecret -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $SPClientId, $SecureClientSecret

    Write-Host "Connecting to Azure with Service Principal..."
    $null = Connect-AzAccount -ServicePrincipal -TenantId $TenantId -Credential $Credential
    Write-Host "Connected to Azure with Service Principal"

    if (-not (Get-Module -ListAvailable -Name 'Microsoft.Graph')) {
        Write-Host "Microsoft.Graph doesn't exist. Installing module..."
        Install-Module Microsoft.Graph -Force -ErrorAction Stop
        Write-Host "Microsoft.Graph module installed"
    }
    $accessToken = (Get-AzAccessToken -Resource https://graph.microsoft.com).Token
    $null = Connect-MgGraph -AccessToken ($accessToken | ConvertTo-SecureString -AsPlainText -Force)
    Write-Host "Connected to Microsoft Graph"

    $adGroup = Get-MgGroup -Filter "DisplayName eq '$ADGroupName'"
    if ($adGroup) {
        Write-Host "Identified AD group '$($adGroup.DisplayName)'"
        $managedId = Get-MgServicePrincipal -Filter "displayName eq '$ManagedIdentityName'" -ErrorAction Stop
        Write-Host "Identified Managed Id '$($managedId.DisplayName)'"
        $null = New-MgGroupMember -GroupId $adGroup.Id -DirectoryObjectId $managedId.Id -ErrorAction Stop
        Write-Host "Added Managed Identity '${ManagedIdentityName}' to AD group '${ADGroupName}'"
    }
    
    $exitCode = 0
}
catch {
    if ($_.Exception.Message.Contains("One or more added object references already exist")) {
        Write-Host "Managed Identity already exists in AD group"
        $exitCode = 0
    }
    else {
        $exitCode = -2
        Write-Error "Failed to add managed identity to AD group with exception: $($_.Exception.ToString())"
        throw $_.Exception
    }
}
finally {
    Disconnect-MgGraph | Out-Null
    [DateTime]$endTime = [DateTime]::UtcNow
    Write-Host "${functionName} finished at $($endTime.ToString('u')) with exit code $exitCode"
    if ($setHostExitCode) {
        Write-Debug "${functionName}:Setting host exit code"
        $host.SetShouldExit($exitCode)
    }
    exit $exitCode
}