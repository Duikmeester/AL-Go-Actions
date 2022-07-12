Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "URL of the template repository (default is the template repository used to create the repository)", Mandatory = $false)]
    [string] $templateUrl = "",
    [Parameter(HelpMessage = "Branch in template repository to use for the update (default is the default branch)", Mandatory = $false)]
    [string] $templateBranch = "",
    [Parameter(HelpMessage = "Set this input to Y in order to update AL-Go System Files if needed", Mandatory = $false)]
    [bool] $update,
    [Parameter(HelpMessage = "Direct Commit (Y/N)", Mandatory = $false)]
    [bool] $directCommit
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $baseFolder = $ENV:GITHUB_WORKSPACE
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $baseFolder

    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0071' -parentTelemetryScopeJson $parentTelemetryScopeJson

    if ($update) {
        if (-not $token) {
            throw "A personal access token with permissions to modify Workflows is needed. You must add a secret called GhTokenWorkflow containing a personal access token. You can Generate a new token from https://github.com/settings/tokens. Make sure that the workflow scope is checked."
        }
        else {
            $token = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($token))
        }
    }

    # Support old calling convention
    if (-not $templateUrl.Contains('@')) {
        if ($templateBranch) {
            $templateUrl += "@$templateBranch"
        }
        else {
            $templateUrl += "@main"
        }
    }
    if ($templateUrl -notlike "https://*") {
        $templateUrl = "https://github.com/$templateUrl"
    }

    $RepoSettingsFile = ".github\AL-Go-Settings.json"
    if (Test-Path $RepoSettingsFile) {
        $repoSettings = Get-Content $repoSettingsFile -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable
    }
    else {
        $repoSettings = @{}
    }

    $updateSettings = $true
    if ($repoSettings.ContainsKey("TemplateUrl")) {
        if ($templateUrl.StartsWith('@')) {
            $templateUrl = "$($repoSettings.TemplateUrl.Split('@')[0])$templateUrl"
        }
        if ($repoSettings.TemplateUrl -eq $templateUrl) {
            $updateSettings = $false
        }
    }

    AddTelemetryProperty -telemetryScope $telemetryScope -key "templateUrl" -value $templateUrl

    $templateBranch = $templateUrl.Split('@')[1]
    $templateUrl = $templateUrl.Split('@')[0]

    $headers = @{
        "Accept" = "application/vnd.github.baptiste-preview+json"
    }

    if ($templateUrl -ne "") {
        try {
            $templateUrl = $templateUrl -replace "https://www.github.com/", "$ENV:GITHUB_API_URL/repos/" -replace "https://github.com/", "$ENV:GITHUB_API_URL/repos/"
            Write-Host "Api url $templateUrl"
            $templateInfo = InvokeWebRequest -Headers $headers -Uri $templateUrl | ConvertFrom-Json
        }
        catch {
            throw "Could not retrieve the template repository. Error: $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "Api url $($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)"
        $repoInfo = InvokeWebRequest -Headers $headers -Uri "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)" | ConvertFrom-Json
        if (!($repoInfo.PSObject.Properties.Name -eq "template_repository")) {
            OutputWarning -message "This repository wasn't built on a template repository, or the template repository is deleted. You must specify a template repository in the AL-Go settings file."
            exit
        }

        $templateInfo = $repoInfo.template_repository
    }

    $templateUrl = $templateInfo.html_url
    Write-Host "Using template from $templateUrl@$templateBranch"

    $headers = @{
        "Accept" = "application/vnd.github.baptiste-preview+json"
    }
    $archiveUrl = $templateInfo.archive_url.Replace('{archive_format}', 'zipball').replace('{/ref}', "/$templateBranch")
    $tempName = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
    InvokeWebRequest -Headers $headers -Uri $archiveUrl -OutFile "$tempName.zip"
    Expand-7zipArchive -Path "$tempName.zip" -DestinationPath $tempName
    Remove-Item -Path "$tempName.zip"

    $checkfiles = @(
        @{ "dstPath" = ".github\workflows"; "srcPath" = ".github\workflows"; "pattern" = "*"; "type" = "workflow" },
        @{ "dstPath" = ".github"; "srcPath" = ".github"; "pattern" = "*.copy.md"; "type" = "releasenotes" }
    )
    if (Test-Path (Join-Path $baseFolder ".AL-Go")) {
        $checkfiles += @(@{ "dstPath" = ".AL-Go"; "srcPath" = ".AL-Go"; "pattern" = "*.ps1"; "type" = "script" })
    }
    else {
        Get-ChildItem -Path $baseFolder -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".AL-Go") -PathType Container } | ForEach-Object {
            $checkfiles += @(@{ "dstPath" = Join-Path $_.Name ".AL-Go"; "srcPath" = ".AL-Go"; "pattern" = "*.ps1"; "type" = "script" })
        }
    }
    $updateFiles = @()

    $checkfiles | ForEach-Object {
        $type = $_.type
        $srcPath = $_.srcPath
        $dstPath = $_.dstPath
        $dstFolder = Join-Path $baseFolder $dstPath
        $srcFolder = (Get-Item (Join-Path $tempName "*\$($srcPath)")).FullName
        Get-ChildItem -Path $srcFolder -Filter $_.pattern | ForEach-Object {
            $srcFile = $_.FullName
            $fileName = $_.Name
            $baseName = $_.BaseName
            $srcContent = (Get-Content -Path $srcFile -Encoding UTF8 -Raw).Replace("`r", "").TrimEnd("`n").Replace("`n", "`r`n")
            $name = $type
            if ($type -eq "workflow") {
                $srcContent.Split("`n") | Where-Object { $_ -like "name:*" } | Select-Object -First 1 | ForEach-Object {
                    if ($_ -match '^name:([^#]*)(#.*$|$)') { $name = "workflow '$($Matches[1].Trim())'" }
                }
            }

            $workflowScheduleKey = "$($baseName)Schedule"
            if ($repoSettings.ContainsKey($workflowScheduleKey)) {
                $srcPattern = "on:`r`n  workflow_dispatch:`r`n"
                $replacePattern = "on:`r`n  schedule:`r`n  - cron: '$($repoSettings."$workflowScheduleKey")'`r`n  workflow_dispatch:`r`n"
                $srcContent = $srcContent.Replace($srcPattern, $replacePattern)
            }

            if ($baseName -eq "CICD") {
                $srcPattern = "  push:`r`n    paths-ignore:`r`n      - 'README.md'`r`n      - '.github/**'`r`n    branches: [ '$($defaultCICDPushBranches -join ''', ''')' ]`r`n  pull_request:`r`n    paths-ignore:`r`n      - 'README.md'`r`n      - '.github/**'`r`n    branches: [ '$($defaultCICDPullRequestBranches -join ''', ''')' ]`r`n"
                $replacePattern = ''
                if ($repoSettings.ContainsKey('CICDPushBranches')) {
                    $CICDPushBranches = $repoSettings.CICDPushBranches
                }
                elseif ($repoSettings.ContainsKey($workflowScheduleKey)) {
                    $CICDPushBranches = ''
                }
                else {
                    $CICDPushBranches = $defaultCICDPushBranches
                }
                if ($CICDPushBranches) {
                    $replacePattern += "  push:`r`n    paths-ignore:`r`n      - 'README.md'`r`n      - '.github/**'`r`n    branches: [ '$($CICDPushBranches -join ''', ''')' ]`r`n"
                }
                if ($repoSettings.ContainsKey('CICDPullRequestBranches')) {
                    $CICDPullRequestBranches = $repoSettings.CICDPullRequestBranches
                }
                elseif ($repoSettings.ContainsKey($workflowScheduleKey)) {
                    $CICDPullRequestBranches = ''
                }
                else {
                    $CICDPullRequestBranches = $defaultCICDPullRequestBranches
                }
                if ($CICDPullRequestBranches) {
                    $replacePattern += "  pull_request:`r`n    paths-ignore:`r`n      - 'README.md'`r`n      - '.github/**'`r`n    branches: [ '$($CICDPullRequestBranches -join ''', ''')' ]`r`n"
                }
                $srcContent = $srcContent.Replace($srcPattern, $replacePattern)
            }

            if ($baseName -ne "UpdateGitHubGoSystemFiles") {
                if ($repoSettings.ContainsKey("runs-on")) {
                    $srcPattern = "runs-on: [ windows-latest ]`r`n"
                    $replacePattern = "runs-on: [ $($repoSettings."runs-on") ]`r`n"
                    $srcContent = $srcContent.Replace($srcPattern, $replacePattern)
                }
            }

            $dstFile = Join-Path $dstFolder $fileName
            if (Test-Path -Path $dstFile -PathType Leaf) {
                # file exists, compare
                $dstContent = (Get-Content -Path $dstFile -Encoding UTF8 -Raw).Replace("`r", "").TrimEnd("`n").Replace("`n", "`r`n")
                if ($dstContent -ne $srcContent) {
                    Write-Host "Updated $name ($(Join-Path $dstPath $filename)) available"
                    $updateFiles += @{ "DstFile" = Join-Path $dstPath $filename; "content" = $srcContent }
                }
            }
            else {
                # new file
                Write-Host "New $name ($(Join-Path $dstPath $filename)) available"
                $updateFiles += @{ "DstFile" = Join-Path $dstPath $filename; "content" = $srcContent }
            }
        }
    }
    $removeFiles = @()

    if (-not $update) {
        if (($updateFiles) -or ($removeFiles)) {
            OutputWarning -message "There are updates for your AL-Go system, run 'Update AL-Go System Files' workflow to download the latest version of AL-Go."
            AddTelemetryProperty -telemetryScope $telemetryScope -key "updatesExists" -value $true
        }
        else {
            Write-Host "Your repository runs on the latest version of AL-Go System."
            AddTelemetryProperty -telemetryScope $telemetryScope -key "updatesExists" -value $false
        }
    }
    else {
        if ($updateSettings -or ($updateFiles) -or ($removeFiles)) {
            try {
                # URL for git commands
                $tempRepo = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
                New-Item $tempRepo -ItemType Directory | Out-Null
                Set-Location $tempRepo
                $serverUri = [Uri]::new($env:GITHUB_SERVER_URL)
                $url = "$($serverUri.Scheme)://$($actor):$($token)@$($serverUri.Host)/$($env:GITHUB_REPOSITORY)"

                # Environment variables for hub commands
                $env:GITHUB_USER = $actor
                $env:GITHUB_TOKEN = $token

                # Configure git username and email
                invoke-git config --global user.email "$actor@users.noreply.github.com"
                invoke-git config --global user.name "$actor"

                # Configure hub to use https
                invoke-git config --global hub.protocol https

                # Clone URL
                invoke-git clone $url

                Set-Location -Path *

                if (!$directcommit) {
                    $branch = [System.IO.Path]::GetRandomFileName()
                    invoke-git checkout -b $branch
                }

                invoke-git status

                $templateUrl = "$templateUrl@$templateBranch"
                $RepoSettingsFile = ".github\AL-Go-Settings.json"
                if (Test-Path $RepoSettingsFile) {
                    $repoSettings = Get-Content $repoSettingsFile -Encoding UTF8 | ConvertFrom-Json
                }
                else {
                    $repoSettings = [PSCustomObject]@{}
                }
                if ($repoSettings.PSObject.Properties.Name -eq "templateUrl") {
                    $repoSettings.templateUrl = $templateUrl
                }
                else {
                    $repoSettings | Add-Member -MemberType NoteProperty -Name "templateUrl" -Value $templateUrl
                }
                $repoSettings | ConvertTo-Json -Depth 99 | Set-Content $repoSettingsFile -Encoding UTF8

                $releaseNotes = ""
                try {
                    $updateFiles | ForEach-Object {
                        $path = [System.IO.Path]::GetDirectoryName($_.DstFile)
                        if (-not (Test-Path -Path $path -PathType Container)) {
                            New-Item -Path $path -ItemType Directory | Out-Null
                        }
                        if (([System.IO.Path]::GetFileName($_.DstFile) -eq "RELEASENOTES.copy.md") -and (Test-Path $_.DstFile)) {
                            $oldReleaseNotes = (Get-Content -Path $_.DstFile -Encoding UTF8 -Raw).Replace("`r", "").TrimEnd("`n").Replace("`n", "`r`n")
                            while ($oldReleaseNotes) {
                                $releaseNotes = $_.Content
                                if ($releaseNotes.indexOf($oldReleaseNotes) -gt 0) {
                                    $releaseNotes = $releaseNotes.SubString(0, $releaseNotes.indexOf($oldReleaseNotes))
                                    $oldReleaseNotes = ""
                                }
                                else {
                                    $idx = $oldReleaseNotes.IndexOf("`r`n## ")
                                    if ($idx -gt 0) {
                                        $oldReleaseNotes = $oldReleaseNotes.Substring($idx)
                                    }
                                    else {
                                        $oldReleaseNotes = ""
                                    }
                                }
                            }
                        }
                        Write-Host "Update $($_.DstFile)"
                        Set-Content -Path $_.DstFile -Encoding UTF8 -Value $_.Content
                    }
                }
                catch {}
                if ($releaseNotes -eq "") {
                    $releaseNotes = "No release notes available!"
                }
                $removeFiles | ForEach-Object {
                    Write-Host "Remove $_"
                    Remove-Item (Join-Path (Get-Location).Path $_) -Force
                }

                invoke-git add *

                Write-Host "ReleaseNotes:"
                Write-Host $releaseNotes

                $status = invoke-git -returnValue status --porcelain=v1
                if ($status) {
                    $message = "Updated AL-Go System Files"

                    invoke-git commit --allow-empty -m "'$message'"

                    if ($directcommit) {
                        invoke-git push $url
                    }
                    else {
                        invoke-git push -u $url $branch
                        invoke-gh pr create --fill --head $branch --repo $env:GITHUB_REPOSITORY --body "$releaseNotes"
                    }
                }
                else {
                    Write-Host "No changes detected in files"
                }
            }
            catch {
                if ($directCommit) {
                    throw "Failed to update AL-Go System Files. Make sure that the personal access token, defined in the secret called GhTokenWorkflow, is not expired and it has permission to update workflows. (Error was $($_.Exception.Message))"
                }
                else {
                    throw "Failed to create a pull-request to AL-Go System Files. Make sure that the personal access token, defined in the secret called GhTokenWorkflow, is not expired and it has permission to update workflows. (Error was $($_.Exception.Message))"
                }
            }
        }
        else {
            OutputWarning "Your repository runs on the latest version of AL-Go System."
        }
    }

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message "CheckForUpdates action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}

# SIG # Begin signature block
# MIIFYQYJKoZIhvcNAQcCoIIFUjCCBU4CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUB2/G1gVWtM/OMoGSmK0Z/b+s
# qGugggMAMIIC/DCCAeSgAwIBAgIQWIq0Hnul0rVA6V3CGFkRiTANBgkqhkiG9w0B
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
# DAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUTfROF58pmCQXiI8FTJaorHoU
# 4g8wDQYJKoZIhvcNAQEBBQAEggEAmmeelJyE3He5YetybqSjPlT5n2V+KuumVjZ5
# 4jp+eIU3OZILvwAASM8dk48vrsc5e7iFC/iZu8mioCshLjXTXBpNg/dnkGN0LZ3R
# +QsshOHRDRgUPsvOqX8IHztIvoKy8WKqZhZizYGWN7WkCvbw8vDpjr9B+EAEGzb3
# ZQr5RwzZTj8ZN2w08y/tmaYzENOeVShX8xS+AXsXGgxkNyv6DI3abA7PCAQRRFMV
# T9XD34cfptZRaMq5ki0QHFLxewdeg8uYrfYYkmGI7SlX7x5Kac4SskvLLeAjHCZD
# jrjjW/ARXWD+HnDl0TsBfmtaazSXdfPHsZf8JjScEeKrHi54Pg==
# SIG # End signature block
