Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "Projects to deploy (default is all)", Mandatory = $false)]
    [string] $projects = "*",
    [Parameter(HelpMessage = "Name of environment to deploy to", Mandatory = $true)]
    [string] $environmentName,
    [Parameter(HelpMessage = "Artifacts to deploy", Mandatory = $true)]
    [string] $artifacts,
    [Parameter(HelpMessage = "Type of deployment (CD or Publish)", Mandatory = $false)]
    [ValidateSet('CD', 'Publish')]
    [string] $type = "CD"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0075' -parentTelemetryScopeJson $parentTelemetryScopeJson

    $EnvironmentName = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($environmentName))

    if ($projects -eq '') { $projects = "*" }

    $apps = @()
    $baseFolder = Join-Path $ENV:GITHUB_WORKSPACE "artifacts"

    if ($artifacts -like "$($baseFolder)*") {
        $apps
        if (Test-Path $artifacts -PathType Container) {
            $apps = @((Get-ChildItem -Path $artifacts -Filter "*-Apps-*") | ForEach-Object { $_.FullName })
            if (!($apps)) {
                throw "There is no artifacts present in $artifacts."
            }
        }
        elseif (Test-Path $artifacts) {
            $apps = $artifacts
        }
        else {
            throw "Artifact $artifacts was not found. Make sure that the artifact files exist and files are not corrupted."
        }
    }
    elseif ($artifacts -eq "current" -or $artifacts -eq "prerelease" -or $artifacts -eq "draft") {
        # latest released version
        $releases = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY
        if ($artifacts -eq "current") {
            $release = $releases | Where-Object { -not ($_.prerelease -or $_.draft) } | Select-Object -First 1
        }
        elseif ($artifacts -eq "prerelease") {
            $release = $releases | Where-Object { -not ($_.draft) } | Select-Object -First 1
        }
        elseif ($artifacts -eq "draft") {
            $release = $releases | Select-Object -First 1
        }
        if (!($release)) {
            throw "Unable to locate $artifacts release"
        }
        New-Item $baseFolder -ItemType Directory | Out-Null
        DownloadRelease -token $token -projects $projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $baseFolder
        $apps = @((Get-ChildItem -Path $baseFolder) | ForEach-Object { $_.FullName })
        if (!$apps) {
            throw "Artifact $artifacts was not found on any release. Make sure that the artifact files exist and files are not corrupted."
        }
    }
    else {
        New-Item $baseFolder -ItemType Directory | Out-Null
        $allArtifacts = GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask "Apps" -projects $projects -Version $artifacts -branch "main"
        if ($allArtifacts) {
            $allArtifacts | ForEach-Object {
                $appFile = DownloadArtifact -token $token -artifact $_ -path $baseFolder
                if (!(Test-Path $appFile)) {
                    throw "Unable to download artifact $($_.name)"
                }
            }
        }
        else {
            throw "Could not find any Apps artifacts for projects $projects, version $artifacts"
        }
    }

    Set-Location $baseFolder
    if (-not ($ENV:AUTHCONTEXT)) {
        throw "An environment secret for environment($environmentName) called AUTHCONTEXT containing authentication information for the environment was not found.You must create an environment secret."
    }
    $authContext = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ENV:AUTHCONTEXT))

    try {
        $authContextParams = $authContext | ConvertFrom-Json | ConvertTo-HashTable
        $bcAuthContext = New-BcAuthContext @authContextParams
    }
    catch {
        throw "Authentication failed. $([environment]::Newline) $($_.exception.message)"
    }

    $envName = $environmentName.Split(' ')[0]
    Write-Host "$($bcContainerHelperConfig.baseUrl.TrimEnd('/'))/$($bcAuthContext.tenantId)/$envName/deployment/url"
    $response = Invoke-RestMethod -UseBasicParsing -Method Get -Uri "$($bcContainerHelperConfig.baseUrl.TrimEnd('/'))/$($bcAuthContext.tenantId)/$envName/deployment/url"
    if ($response.Status -eq "DoesNotExist") {
        OutputError -message "Environment with name $envName does not exist in the current authorization context."
        exit
    }
    if ($response.Status -ne "Ready") {
        OutputError -message "Environment with name $envName is not ready (Status is $($response.Status))."
        exit
    }

    $apps | ForEach-Object {
        try {
            if ($response.environmentType -eq 1) {
                if ($bcAuthContext.ClientSecret) {
                    Write-Host "Using S2S, publishing apps using automation API"
                    Publish-PerTenantExtensionApps -bcAuthContext $bcAuthContext -environment $envName -appFiles $_
                }
                else {
                    Write-Host "Publishing apps using development endpoint"
                    Publish-BcContainerApp -bcAuthContext $bcAuthContext -environment $envName -appFile $_ -useDevEndpoint
                }
            }
            else {
                if ($type -eq 'CD') {
                    Write-Host "Ignoring environment $environmentName, which is a production environment"
                }
                else {

                    # Check for AppSource App - cannot be deployed

                    Write-Host "Publishing apps using automation API"
                    Publish-PerTenantExtensionApps -bcAuthContext $bcAuthContext -environment $envName -appFiles $_
                }
            }
        }
        catch {
            OutputError -message "Deploying to $environmentName failed.$([environment]::Newline) $($_.Exception.Message)"
            exit
        }
    }

    TrackTrace -telemetryScope $telemetryScope

}
catch {
    OutputError -message "Deploy action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}

# SIG # Begin signature block
# MIIFYQYJKoZIhvcNAQcCoIIFUjCCBU4CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUJyLV1UcvYa2eXTDgmNdssRSy
# EgegggMAMIIC/DCCAeSgAwIBAgIQWIq0Hnul0rVA6V3CGFkRiTANBgkqhkiG9w0B
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
# DAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUWEVr9vgsWwIWKfcOM9Xyw62Z
# KyMwDQYJKoZIhvcNAQEBBQAEggEAJw1GEe73jMRdDfKh3+GnX5HDm8JpV5AeBJh8
# ATBMjnrbjg6ersqeXaApes6HBPk2yw6gXYbnCDrVqD6OU72FyGxmZg6F50RSBOCT
# yC76XI/724ZpJYnFn/rzHi+8DAO7TQ1wh0Vyi6vKE9igUewpbliRGnWQNs/TZ9hy
# KN+ucFgefxDvWXYbGqMs6MuKzezaXs+tksWVFt7jR8/LGbel3qz/VKXc7ZHNAyqR
# fmfYUpFFDblHR33anDeC6+plTn126+f2bdmemhXvwTGBEf6WKUB972oGYbjg508b
# e0bRDOv7zPGx4WlyfwGwXLmtgBI+V6ID4cTtS6qS0+jVBA7VLA==
# SIG # End signature block
