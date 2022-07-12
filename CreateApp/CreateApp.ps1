Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "Project name if the repository is setup for multiple projects", Mandatory = $false)]
    [string] $project = '.',
    [ValidateSet("PTE", "AppSource App" , "Test App", "Performance Test App")]
    [Parameter(HelpMessage = "Type of app to add (PTE, AppSource App, Test App)", Mandatory = $true)]
    [string] $type,
    [Parameter(HelpMessage = "App Name", Mandatory = $true)]
    [string] $name,
    [Parameter(HelpMessage = "Publisher", Mandatory = $true)]
    [string] $publisher,
    [Parameter(HelpMessage = "ID range", Mandatory = $true)]
    [string] $idrange,
    [Parameter(HelpMessage = "Include Sample Code (Y/N)", Mandatory = $false)]
    [bool] $sampleCode,
    [Parameter(HelpMessage = "Include Sample BCPT Suite (Y/N)", Mandatory = $false)]
    [bool] $sampleSuite,
    [Parameter(HelpMessage = "Direct Commit (Y/N)", Mandatory = $false)]
    [bool] $directCommit
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null
$tmpFolder = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $branch = "$(if (!$directCommit) { [System.IO.Path]::GetRandomFileName() })"
    $serverUrl = CloneIntoNewFolder -actor $actor -token $token -branch $branch
    $repoBaseFolder = (Get-Location).Path
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $repoBaseFolder

    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0072' -parentTelemetryScopeJson $parentTelemetryScopeJson

    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "AppHelper.psm1" -Resolve)
    Write-Host "Template type : $type"

    # Check parameters
    if (-not $publisher) {
        throw "A publisher must be specified."
    }

    if (-not $name) {
        throw "An extension name must be specified."
    }

    $ids = Confirm-IdRanges -templateType $type -idrange $idrange

    CheckAndCreateProjectFolder -project $project
    $baseFolder = (Get-Location).Path

    if ($type -eq "Performance Test App") {
        try {
            $settings = ReadSettings -baseFolder $baseFolder -repoName $env:GITHUB_REPOSITORY -workflowName $env:GITHUB_WORKFLOW
            $settings = AnalyzeRepo -settings $settings -token $token -baseFolder $repoBaseFolder -project $project -doNotIssueWarnings
            $folders = Download-Artifacts -artifactUrl $settings.artifact -includePlatform
            $sampleApp = Join-Path $folders[0] "Applications.*\Microsoft_Performance Toolkit Samples_*.app"
            if (Test-Path $sampleApp) {
                $sampleApp = (Get-Item -Path $sampleApp).FullName
            }
            else {
                $sampleApp = Join-Path $folders[1] "Applications\testframework\performancetoolkit\Microsoft_Performance Toolkit Samples.app"
            }
            if (!(Test-Path -Path $sampleApp)) {
                throw "Could not locate sample app for the Business Central version"
            }
            Extract-AppFileToFolder -appFilename $sampleApp -generateAppJson -appFolder $tmpFolder
        }
        catch {
            throw "Unable to create performance test app. Error was $($_.Exception.Message)"
        }
    }

    $orgfolderName = $name.Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
    $folderName = GetUniqueFolderName -baseFolder $baseFolder -folderName $orgfolderName
    if ($folderName -ne $orgfolderName) {
        OutputWarning -message "Folder $orgFolderName already exists in the repo, folder name $folderName will be used instead."
    }

    # Modify .AL-Go\settings.json
    try {
        $settingsJsonFile = Join-Path $baseFolder $ALGoSettingsFile
        $SettingsJson = Get-Content $settingsJsonFile -Encoding UTF8 | ConvertFrom-Json
        if (@($settingsJson.appFolders) + @($settingsJson.testFolders)) {
            if ($type -eq "Performance Test App") {
                if ($SettingsJson.bcptTestFolders -notcontains $foldername) {
                    $SettingsJson.bcptTestFolders += @($folderName)
                }
            }
            elseif ($type -eq "Test App") {
                if ($SettingsJson.testFolders -notcontains $foldername) {
                    $SettingsJson.testFolders += @($folderName)
                }
            }
            else {
                if ($SettingsJson.appFolders -notcontains $foldername) {
                    $SettingsJson.appFolders += @($folderName)
                }
            }
            $SettingsJson | ConvertTo-Json -Depth 99 | Set-Content -Path $settingsJsonFile -Encoding UTF8
        }
    }
    catch {
        throw "A malformed $ALGoSettingsFile is encountered.$([environment]::Newline) $($_.Exception.Message)"
    }

    $appVersion = "1.0.0.0"
    if ($settingsJson.PSObject.Properties.Name -eq "AppVersion") {
        $appVersion = "$($settingsJson.AppVersion).0.0"
    }

    if ($type -eq "Performance Test App") {
        New-SamplePerformanceTestApp -destinationPath (Join-Path $baseFolder $folderName) -name $name -publisher $publisher -version $appVersion -sampleCode $sampleCode -sampleSuite $sampleSuite -idrange $ids -appSourceFolder $tmpFolder
    }
    elseif ($type -eq "Test App") {
        New-SampleTestApp -destinationPath (Join-Path $baseFolder $folderName) -name $name -publisher $publisher -version $appVersion -sampleCode $sampleCode -idrange $ids
    }
    else {
        New-SampleApp -destinationPath (Join-Path $baseFolder $folderName) -name $name -publisher $publisher -version $appVersion -sampleCode $sampleCode -idrange $ids
    }

    Update-WorkSpaces -baseFolder $baseFolder -appName $folderName

    Set-Location $repoBaseFolder
    CommitFromNewFolder -serverUrl $serverUrl -commitMessage "New $type ($Name)" -branch $branch

    TrackTrace -telemetryScope $telemetryScope

}
catch {
    OutputError -message "CreateApp action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
    if (Test-Path $tmpFolder) {
        Remove-Item $tmpFolder -Recurse -Force
    }
}

# SIG # Begin signature block
# MIIFYQYJKoZIhvcNAQcCoIIFUjCCBU4CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUByUv1fai+2/1MBf+C7W2vmH1
# GcagggMAMIIC/DCCAeSgAwIBAgIQWIq0Hnul0rVA6V3CGFkRiTANBgkqhkiG9w0B
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
# DAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUOkrEw4J3ahtg9h3lNpLkHez5
# r4MwDQYJKoZIhvcNAQEBBQAEggEALabygSEYmXZezHiK+1wO3uS53D1osKKBGGaC
# wNvMYnyEhEhWJBdsXS46oFEvtFBp7EjPyRGPzQkDhzRjYhXLlBe+XpCNRfnA0Xh1
# v2hadDT2Upb8G4Nl0OZ4bH+pjizYgB5vuMauLwBqtnD6bGCFnuj5Oj8/p8lPp7Kq
# LU0fkfFU2CEd2nYk85rADQ6KRZ8k5J6FQhbmAunSnyL1Uu+qsyLBneBMPg+VxMVj
# 2P25rLb/SbQdVVdOz3FZSP71PMn6ZfWyaKXsRyOmn0WLKXOSFUebrmtje6TLZTaV
# Gr1R3uRcx86Y1SUO7/lBqK4QPkrb4dhbslsrEFTOgnGIwuE8OA==
# SIG # End signature block
