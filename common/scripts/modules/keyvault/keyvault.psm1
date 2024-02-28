Set-StrictMode -Version 3.0

Function Get-KeyVaultSecret {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string]$KeyVaultName,
        [Parameter(Mandatory)]
        [string]$SecretName
    )

    begin {
        [string]$functionName = $MyInvocation.MyCommand
        Write-Debug "${functionName}:begin:start"
        Write-Debug "${functionName}:begin:KeyVaultName=$KeyVaultName"
        Write-Debug "${functionName}:begin:SecretName=$SecretName"
        Write-Debug "${functionName}:begin:end"
    }

    process {
        Write-Debug "${functionName}:process:start"
        $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -AsPlainText
        return $secret
        Write-Debug "${functionName}:process:end"
    }

    end {
        Write-Debug "${functionName}:end"
    }
}