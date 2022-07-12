Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "A GitHub token with permissions to modify workflows", Mandatory = $false)]
    [string] $workflowToken,
    [Parameter(HelpMessage = "Tag name", Mandatory = $true)]
    [string] $tag_name
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1")
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0074' -parentTelemetryScopeJson $parentTelemetryScopeJson

    $releaseNotes = ""

    Import-Module (Join-Path $PSScriptRoot '..\Github-Helper.psm1' -Resolve)

    SemVerStrToSemVerObj -semVerStr $tag_name | Out-Null

    $latestRelease = GetLatestRelease -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY

    $latestReleaseTag = ""
    if ($latestRelease -and ([bool]($latestRelease.PSobject.Properties.name -match "tag_name"))) {
        $latestReleaseTag = $latestRelease.tag_name
    }

    $releaseNotes = GetReleaseNotes -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -tag_name $tag_name -previous_tag_name $latestReleaseTag | ConvertFrom-Json
    $releaseNotes = $releaseNotes.body -replace '%', '%25' -replace '\n', '%0A' -replace '\r', '%0D' # supports a multiline text

    Write-Host "::set-output name=releaseNotes::$releaseNotes"
    Write-Host "set-output name=releaseNotes::$releaseNotes"

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputWarning -message "Couldn't create release notes.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    OutputWarning -message "You can modify the release note from the release page later."
    $releaseNotes = ""
    Write-Host "::set-output name=releaseNotes::$releaseNotes"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}

return $releaseNotes

# SIG # Begin signature block
# MIIFYQYJKoZIhvcNAQcCoIIFUjCCBU4CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUnPdFZCYtWyAZuH2FOJ4AwhyR
# sGWgggMAMIIC/DCCAeSgAwIBAgIQWIq0Hnul0rVA6V3CGFkRiTANBgkqhkiG9w0B
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
# DAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUTMik38ta3Xz+z7NlNOtyOjpk
# ZfAwDQYJKoZIhvcNAQEBBQAEggEAhza/dngR9iu4PZFLZtXJBSZYpW+cTDKwBP80
# d78jTf2Ep1+ASSR4SB7X7IOFwRPoQA+l8J8siQENPJByyfvI6oABqhcm6ry3b28K
# RqpSfYBJXGzBzA4qzl9ScmTghd/FqeXb+cCZP0MklXB5wObS5oDAkCu3hna5NhI0
# MreJuYCqnL3trg6cAk7d+7Mxi6QUPoGLXalrE17dw73jZgL6TPD4cl6s6MyGcyNK
# /g84zY3jJDBQo1UME+FIQMNDFpPT1voZszhUmnvjB7Ae0YbNfSG0NDnkK/SmG3kO
# S7YUtyGATEHkWPrHxkbkGoWHoYFVsHRoY0Huz8jcM1+4cHf/kw==
# SIG # End signature block
