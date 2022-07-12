Param(

    [Parameter(HelpMessage = "Settings from template repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '{"keyVaultName": ""}',
    [Parameter(HelpMessage = "Comma separated list of Secrets to get", Mandatory = $true)]
    [string] $secrets = "",
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}'
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch
$buildMutexName = "AL-Go-ReadSecrets"
$buildMutex = New-Object System.Threading.Mutex($false, $buildMutexName)
try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0078' -parentTelemetryScopeJson $parentTelemetryScopeJson

    try {
        if (!$buildMutex.WaitOne(1000)) {
            Write-Host "Waiting for other process executing ReadSecrets"
            $buildMutex.WaitOne() | Out-Null
            Write-Host "Other process completed ReadSecrets"
        }
    }
    catch [System.Threading.AbandonedMutexException] {
        Write-Host "Other process terminated abnormally"
    }

    Import-Module (Join-Path $PSScriptRoot ".\ReadSecretsHelper.psm1")

    $outSecrets = [ordered]@{}
    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable
    $outSettings = $settings
    $keyVaultName = $settings.KeyVaultName
    if ([string]::IsNullOrEmpty($keyVaultName) -and (IsKeyVaultSet)) {
        $credentialsJson = Get-KeyVaultCredentials | ConvertTo-HashTable
        $credentialsJson.Keys | ForEach-Object { MaskValueInLog -value $credentialsJson."$_" }
        if ($credentialsJson.ContainsKey("KeyVaultName")) {
            $keyVaultName = $credentialsJson.KeyVaultName
        }
    }
    [System.Collections.ArrayList]$secretsCollection = @()
    $secrets.Split(',') | ForEach-Object {
        $secret = $_
        $secretNameProperty = "$($secret)SecretName"
        if ($settings.containsKey($secretNameProperty)) {
            $secret = "$($secret)=$($settings."$secretNameProperty")"
        }
        $secretsCollection += $secret
    }

    @($secretsCollection) | ForEach-Object {
        $secretSplit = $_.Split('=')
        $envVar = $secretSplit[0]
        $secret = $envVar
        if ($secretSplit.Count -gt 1) {
            $secret = $secretSplit[1]
        }

        if ($secret) {
            $value = GetSecret -secret $secret -keyVaultName $keyVaultName
            if ($value) {
                $base64value = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($value))
                Add-Content -Path $env:GITHUB_ENV -Value "$envVar=$base64value"
                $outSecrets += @{ "$envVar" = $base64value }
                Write-Host "$envVar successfully read from secret $secret"
                $secretsCollection.Remove($_)
            }
        }
    }

    if ($outSettings.ContainsKey('appDependencyProbingPaths')) {
        $outSettings.appDependencyProbingPaths | ForEach-Object {
            if ($_.PsObject.Properties.name -eq "AuthTokenSecret") {
                $_.authTokenSecret = GetSecret -secret $_.authTokenSecret -keyVaultName $keyVaultName
            }
        }
    }

    if ($secretsCollection) {
        Write-Host "The following secrets was not found: $(($secretsCollection | ForEach-Object {
            $secretSplit = @($_.Split('='))
            if ($secretSplit.Count -eq 1) {
                $secretSplit[0]
            }
            else {
                "$($secretSplit[0]) (Secret $($secretSplit[1]))"
            }
            $outSecrets += @{ ""$($secretSplit[0])"" = """" }
        }) -join ', ')"
    }

    $outSecretsJson = $outSecrets | ConvertTo-Json -Compress
    Add-Content -Path $env:GITHUB_ENV -Value "RepoSecrets=$outSecretsJson"

    $outSettingsJson = $outSettings | ConvertTo-Json -Compress
    Add-Content -Path $env:GITHUB_ENV -Value "Settings=$OutSettingsJson"

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message "ReadSecrets action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    exit
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
    $buildMutex.ReleaseMutex()
}

# SIG # Begin signature block
# MIIFYQYJKoZIhvcNAQcCoIIFUjCCBU4CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUEOqzn9wJsIn9xgGXBD/GGy+v
# IWCgggMAMIIC/DCCAeSgAwIBAgIQWIq0Hnul0rVA6V3CGFkRiTANBgkqhkiG9w0B
# AQsFADAWMRQwEgYDVQQDDAtEdWlrbWVlc3RlcjAeFw0yMjA3MTIwOTM4MjVaFw0y
# MzA3MTIwOTU4MjVaMBYxFDASBgNVBAMMC0R1aWttZWVzdGVyMIIBIjANBgkqhkiG
# 9w0BAQEFAAOCAQ8AMIIBCgKCAQEA+rpjbZpCADD9OlTHYX+y0NSVcRHYm9R5ELki
# 1QVeVs2D6vZ1LVjce+0ose1ZCi9202xNgdmoMGKfljvtr1AYtXuROtttk0Sv4r8N
# CZeWmFfqczBAjTu+V5tF9k/bRjr4Ca1Os5JlSY2/JrkykAjI67Ax35JJ9RVuFLYm
# UeYMZyNNvHQAC64Mm2K+lArBl4C82W7s0aHrI8zRVZbC2oibKj/Jq2jKsbO99UUD
# NAyNNkwZBJoQeKc1srf4x+bzxf/AYPJVTJTqZe0NWFSgqqAzr5278ThVo2Gl55vC
# uEr5Xvrh1TCS0ZFym28JBmzFlylv2AP1XNde0aQDTc4F5C41PQIDAQABo0YwRDAO
# BgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwMwHQYDVR0OBBYEFLXl
# e2EG0yTguM4BJCGBenHLbY8ZMA0GCSqGSIb3DQEBCwUAA4IBAQCOmRQTFgw+7tRh
# GsBLNz2KDUCuPI5/nNpbI6fU2Q8ZMvAEyM+CawDW0XqHABYJ6KBN+Rm65x2B//f2
# jdcKbLSRvsY8BSiBMMeov1gaWxyK9aB7lXSU+TLGCtMZYZzF5+/Ib9uKmLEUlqcM
# d2RVZVE7e8mstBf8ImH7qDKABkYECP6jGG9dD0Ol9+aiLQE7rIHLhktynZ+Z1Paj
# VvXSk93eBH89xVOUivo9SrNN1pl9b4GEY2oO32ycCNU+zrpPZ47o5T1fhorOhLhR
# s1rGNMzU7CHH0n6aEppbx5SurEkYlJaZ92CuxMr0q63Xp/f5GYT4hQvUa5dJf8Le
# ZCyvw85PMYIByzCCAccCAQEwKjAWMRQwEgYDVQQDDAtEdWlrbWVlc3RlcgIQWIq0
# Hnul0rVA6V3CGFkRiTAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAigAoAA
# oQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4w
# DAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQU58qjf0IAGAEh8yanVIEsAhor
# RrEwDQYJKoZIhvcNAQEBBQAEggEADmVZGw0t/ihIplJsPShH2AsbUVV8ihRSN4QC
# eMv0ijQNFThsZRP1FuyZR+GUWKezIJfQwEtZgy2DyFw3MZT6baNy/obEkzloKoUU
# 10CtNAB4Kqt/Gi+yHJCY7e1r7T3mCfOESBQY0cb/JWgeksn9y3BlDtbVBridfozH
# DcSOLiDU2AvosKkeddT84YJzSexa18TabQjMLU1TMuRhrpVwjdBMDC+15KmkESHR
# nT4ZrBV8whAiXi7Mm1Agsm0s7dDx62HF43FOPug3kdJu+usseA4F2y02jqec1wPa
# Wa3J8fol0yMlviqfAH1dTkbxsiP6vFR84r/DGHe9jbol06dfoA==
# SIG # End signature block
