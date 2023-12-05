Set-StrictMode -Version 3.0

function Invoke-PSQLScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PostgresHost,
        [Parameter(Mandatory)]
        [string]$PostgresUsername,
        [Parameter(Mandatory)]
        [string]$PostgresDatabase,
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$WorkingDirectory = $PWD
    )
    
    begin {
        [string]$functionName = $MyInvocation.MyCommand
        Write-Debug "${functionName}:begin:start"
        Write-Debug "${functionName}:begin:PostgresHost=$PostgresHost"
        Write-Debug "${functionName}:begin:PostgresUsername=$PostgresUsername"
        Write-Debug "${functionName}:begin:PostgresDatabase=$PostgresDatabase"
        Write-Debug "${functionName}:begin:end"
    }

    process {
        Write-Debug "${functionName}:process:start"
        Write-Debug "${functionName}:begin:Path=$Path"
        Write-Debug "${functionName}:begin:WorkingDirectory=$WorkingDirectory"

        [System.IO.DirectoryInfo]$moduleDir = Join-Path -Path $WorkingDirectory -ChildPath "scripts/modules/ps-helpers"
    Write-Debug "${functionName}:moduleDir.FullName=$($moduleDir.FullName)"
    Import-Module $moduleDir.FullName -Force

        [System.Text.StringBuilder]$builder = [System.Text.StringBuilder]::new('psql -A -q ')
        [void]$builder.Append(" -h " + $PostgresHost)
        [void]$builder.Append(" -U " + $PostgresUsername)
        [void]$builder.Append(" " + $PostgresDatabase)
        [void]$builder.Append(" -f '")
        [void]$builder.Append($Path)
        [void]$builder.Append("'")

        $expression = $builder.ToString()
        Write-Debug "${functionName}:process:expression=$expression"
        Write-Host $expression

        Invoke-CommandLine -Command $expression -NoOutput
        
        Write-Debug "${functionName}:process:end"
    }

    end {
        Write-Debug "${functionName}:end:start"
        Write-Debug "${functionName}:end:end"
    }
}
