Param(
    [Parameter(HelpMessage = "The event id of the initiating workflow", Mandatory = $true)]
    [string] $eventId
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$BcContainerHelperPath = ""

# IMPORTANT: No code that can fail should be outside the try/catch
try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-TestRepoHelper.ps1" -Resolve)

    $ap = "$ENV:GITHUB_ACTION_PATH".Split('\')
    $branch = $ap[$ap.Count - 2]
    $owner = $ap[$ap.Count - 4]

    if ($owner -ne "microsoft") {
        $verstr = "d"
    }
    elseif ($branch -eq "preview") {
        $verstr = "p"
    }
    else {
        $verstr = $branch
    }

    Write-Big -str "a$verstr"

    Test-ALGoRepository -baseFolder $ENV:GITHUB_WORKSPACE

    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId $eventId
    if ($telemetryScope) {
        AddTelemetryProperty -telemetryScope $telemetryScope -key "repository" -value (GetHash -str $ENV:GITHUB_REPOSITORY)
        AddTelemetryProperty -telemetryScope $telemetryScope -key "runAttempt" -value $ENV:GITHUB_RUN_ATTEMPT
        AddTelemetryProperty -telemetryScope $telemetryScope -key "runNumber" -value $ENV:GITHUB_RUN_NUMBER
        AddTelemetryProperty -telemetryScope $telemetryScope -key "runId" -value $ENV:GITHUB_RUN_ID

        $scopeJson = $telemetryScope | ConvertTo-Json -Compress
        $correlationId = ($telemetryScope.CorrelationId).ToString()
    }
    else {
        $scopeJson = "{}"
        $correlationId = [guid]::Empty.ToString()
    }

    Write-Host "::set-output name=telemetryScopeJson::$scopeJson"
    Write-Host "set-output name=telemetryScopeJson::$scopeJson"

    Write-Host "::set-output name=correlationId::$correlationId"
    Write-Host "set-output name=correlationId::$correlationId"

}
catch {
    OutputError -message "WorkflowInitialize action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}

# SIG # Begin signature block
# MIIFYQYJKoZIhvcNAQcCoIIFUjCCBU4CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUCEToHnVxIW+fc4yJSrE9sSGy
# 95+gggMAMIIC/DCCAeSgAwIBAgIQWIq0Hnul0rVA6V3CGFkRiTANBgkqhkiG9w0B
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
# DAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUjqn0RzgMgLlwwpcQrwob9CU1
# /OIwDQYJKoZIhvcNAQEBBQAEggEADht0xWb97b+w0hGsx4kRPbmfII4dQs/KXQxJ
# o2fuBHKrpaOTwgCVis94LHn68fyjIVWJVqsAtFrKLsIYGOXR1aeR70wFsFGGV7Sw
# HKF2yae7bFHADhaIRKkg8TdfMBg6RNpa1PDnx/Rb6um/0LQO0CMC6zzxwIvS7BnU
# E7a1pqqqI06VptrcQJxwPhV0vVhLhbct1uzERsw37JCV+RNjDylwDz/oNNjMNrWK
# hkqeDH8dtbPAcFfi/ug9BsQmQJfZA3vwNmWuEhmJzHjcFbmCut72VQc1hgf6/IDe
# yeoPuBj2Gkl76x57cL6IYkAvuF2wQiAYQ1HxSXDo5Ppr7KIgyQ==
# SIG # End signature block
