$signals = @{
    "DO0070" = "AL-Go action ran: AddExistingApp"
    "DO0071" = "AL-Go action ran: CheckForUpdates"
    "DO0072" = "AL-Go action ran: CreateApp"
    "DO0073" = "AL-Go action ran: CreateDevelopmentEnvironment"
    "DO0074" = "AL-Go action ran: CreateReleaseNotes"
    "DO0075" = "AL-Go action ran: Deploy"
    "DO0076" = "AL-Go action ran: IncrementVersionNumber"
    "DO0077" = "AL-Go action ran: PipelineCleanup"
    "DO0078" = "AL-Go action ran: ReadSecrets"
    "DO0079" = "AL-Go action ran: ReadSettings"
    "DO0080" = "AL-Go action ran: RunPipeline"

    "DO0090" = "AL-Go workflow ran: AddExistingAppOrTestApp"
    "DO0091" = "AL-Go workflow ran: CiCd"
    "DO0092" = "AL-Go workflow ran: CreateApp"
    "DO0093" = "AL-Go workflow ran: CreateOnlineDevelopmentEnvironment"
    "DO0094" = "AL-Go workflow ran: CreateRelease"
    "DO0095" = "AL-Go workflow ran: CreateTestApp"
    "DO0096" = "AL-Go workflow ran: IncrementVersionNumber"
    "DO0097" = "AL-Go workflow ran: PublishToEnvironment"
    "DO0098" = "AL-Go workflow ran: UpdateGitHubGoSystemFiles"
    "DO0099" = "AL-Go workflow ran: NextMajor"
    "DO0100" = "AL-Go workflow ran: NextMinor"
    "DO0101" = "AL-Go workflow ran: Current"
    "DO0102" = "AL-Go workflow ran: CreatePerformanceTestApp"
}

function CreateScope {
    param (
        [string] $eventId,
        [string] $parentTelemetryScopeJson = '{}'
    )

    $signalName = $signals[$eventId]
    if (-not $signalName) {
        throw "Invalid event id ($eventId) is enountered."
    }

    if ($parentTelemetryScopeJson -and $parentTelemetryScopeJson -ne "{}") {
        $telemetryScope = RegisterTelemetryScope $parentTelemetryScopeJson
    }

    $telemetryScope = InitTelemetryScope -name $signalName -eventId $eventId -parameterValues @() -includeParameters @()

    return $telemetryScope
}

function GetHash {
    param(
        [string] $str
    )

    $stream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($str))
    (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
}

# SIG # Begin signature block
# MIIFYQYJKoZIhvcNAQcCoIIFUjCCBU4CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUEylEygkjGgMu1Sf85ZhyPJUm
# MTygggMAMIIC/DCCAeSgAwIBAgIQWIq0Hnul0rVA6V3CGFkRiTANBgkqhkiG9w0B
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
# DAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUVkT9qogDgaSNwaoHHmgNn8tz
# 8w8wDQYJKoZIhvcNAQEBBQAEggEAO3RAVz3A7UPie9truawPQyb7vrUnCtS06yDG
# e/IXKpsvgrbwi+lxT8OUylhcVutB46T+f26beHZi8AQui8c/Cm4YJvGHt7aHwb71
# XPTx9RdL3u+YXIPyvie01a8ZobtI2Df5fqwjzYNdLYtLXwLCzX6sd+enV7ufv1p8
# LpO23SK/PDSygABo29jQRrUHF+LjKzqJ2ckchxbb2zkbsUnpWprNxNop66IPfdVy
# qHFxqEcryb0EtDaSXlQ49RopVqDfCThGiIUmnJq+aY1q9EpE39x9A5UGGjULeHfy
# SQEqXd0qeK/S23kPSjcbB1p/is9CGdtSsqew9G3/mnnNQEYwVQ==
# SIG # End signature block
