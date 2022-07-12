function Test-Property {
    Param(
        [HashTable] $json,
        [string] $key,
        [switch] $must,
        [switch] $should,
        [switch] $maynot,
        [switch] $shouldnot
    )

    $exists = $json.ContainsKey($key)
    if ($exists) {
        if ($maynot) {
            Write-Host "::Error::Property '$key' may not exist in $settingsFile"
        }
        elseif ($shouldnot) {
            Write-Host "::Warning::Property '$key' should not exist in $settingsFile"
        }
    }
    else {
        if ($must) {
            Write-Host "::Error::Property '$key' must exist in $settingsFile"
        }
        elseif ($should) {
            Write-Host "::Warning::Property '$key' should exist in $settingsFile"
        }
    }
}

function Test-Json {
    Param(
        [string] $jsonFile,
        [string] $baseFolder,
        [switch] $repo
    )

    $settingsFile = $jsonFile.Substring($baseFolder.Length)
    if ($repo) {
        Write-Host "Checking AL-Go Repo Settings file $settingsFile"
    }
    else {
        Write-Host "Checking AL-Go Settings file $settingsFile"
    }

    try {
        $json = Get-Content -Path $jsonFile -Raw -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable
        if ($repo) {
            Test-Property -settingsFile $settingsFile -json $json -key 'templateUrl' -should
        }
        else {
            Test-Property -settingsFile $settingsFile -json $json -key 'templateUrl' -maynot
            'nextMajorSchedule', 'nextMinorSchedule', 'currentSchedule', 'githubRunner', 'runs-on' | ForEach-Object {
                Test-Property -settingsFile $settingsFile -json $json -key $_ -shouldnot
            }
        }
    }
    catch {
        Write-Host "::Error::$($_.Exception.Message.Replace("`r",'').Replace("`n",' '))"
    }
}

function Test-ALGoRepository {
    Param(
        [string] $baseFolder
    )

    # Test .json files are formatted correctly
    Get-ChildItem -Path $baseFolder -Filter '*.json' -Recurse | ForEach-Object {
        if ($_.FullName -like '*\.AL-Go\Settings.json') {
            Test-Json -jsonFile $_.FullName -baseFolder $baseFolder
        }
        elseif ($_.FullName -like '*\.github\*Settings.json') {
            Test-Json -jsonFile $_.FullName -baseFolder $baseFolder -repo:($_.BaseName -eq "AL-Go-Settings")
        }
    }
}

function Write-Big {
    Param(
        [string] $str
    )
    $chars = @{
        "0" = @'
   ___
  / _ \
 | | | |
 | | | |
 | |_| |
  \___/
'@.Split("`n")
        "1" = @'
  __
 /_ |
  | |
  | |
  | |
  |_|
'@.Split("`n")
        "2" = @'
  ___
 |__ \
    ) |
   / /
  / /_
 |____|
'@.Split("`n")
        "3" = @'
  ____
 |___ \
   __) |
  |__ <
  ___) |
 |____/
'@.Split("`n")
        "4" = @'
  _  _
 | || |
 | || |_
 |__   _|
    | |
    |_|
'@.Split("`n")
        "5" = @'
  _____
 | ____|
 | |__
 |___ \
  ___) |
 |____/
'@.Split("`n")
        "6" = @'
    __
   / /
  / /_
 | '_ \
 | (_) |
  \___/
'@.Split("`n")
        "7" = @'
  ______
 |____  |
     / /
    / /
   / /
  /_/
'@.Split("`n")
        "8" = @'
   ___
  / _ \
 | (_) |
  > _ <
 | (_) |
  \___/
'@.Split("`n")
        "9" = @'
   ___
  / _ \
 | (_) |
  \__, |
    / /
   /_/
'@.Split("`n")
        "." = @'




  _
 (_)
'@.Split("`n")
        "v" = @'


 __   __
 \ \ / /
  \ V /
   \_(_)
'@.Split("`n")
        "p" = @'
  _____                _
 |  __ \              (_)
 | |__) | __ _____   ___  _____      __
 |  ___/ '__/ _ \ \ / / |/ _ \ \ /\ / /
 | |   | | |  __/\ V /| |  __/\ V  V /
 |_|   |_|  \___| \_/ |_|\___| \_/\_/
'@.Split("`n")
        "d" = @'
  _____
 |  __ \
 | |  | | _____   __
 | |  | |/ _ \ \ / /
 | |__| |  __/\ V /
 |_____/ \___| \_(_)
'@.Split("`n")
        "a" = @'
           _           _____          __              _____ _ _   _    _       _
     /\   | |         / ____|        / _|            / ____(_) | | |  | |     | |
    /  \  | |  ______| |  __  ___   | |_ ___  _ __  | |  __ _| |_| |__| |_   _| |__
   / /\ \ | | |______| | |_ |/ _ \  |  _/ _ \| '__| | | |_ | | __|  __  | | | | '_ \
  / ____ \| |____    | |__| | (_) | | || (_) | |    | |__| | | |_| |  | | |_| | |_) |
 /_/    \_\______|    \_____|\___/  |_| \___/|_|     \_____|_|\__|_|  |_|\__,_|_.__/
'@.Split("`n")
    }


    0..5 | ForEach-Object {
        $line = $_
        $str.ToCharArray() | ForEach-Object {
            $ch = $chars."$_"
            if ($ch) {
                Write-Host -NoNewline $ch[$line]
            }
        }
        Write-Host
    }
}
# SIG # Begin signature block
# MIIFYQYJKoZIhvcNAQcCoIIFUjCCBU4CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU+T5s4O/FaZl6Fk43b3x5cNWh
# 8dOgggMAMIIC/DCCAeSgAwIBAgIQWIq0Hnul0rVA6V3CGFkRiTANBgkqhkiG9w0B
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
# DAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUsZlcV+yk3inDYlfmbjDLpBXf
# LWAwDQYJKoZIhvcNAQEBBQAEggEAEQVxYAAsksJYIOqyxiyrneEb3yyJER7/+RoD
# BNTF7oav9NkbPRZVTEl9sHtFEGEEv4sXbvqQZt+YoaX3jC0RAYB39K9j+TqNsvtZ
# AgkEE8q+kS8JR7/U5Oy4SgzkZZzejqYHLs9c44YtiPaTBDuVXOMz/5Y3Im+sIMhp
# dlhrejO9qg9oiMziATGFC0DyNQP9tP0kV3WTN7ZDPfdcdtGzWwsLEWc91ilByPES
# pUyAk7fFkbRMygfQmcfFRf91YqoEOOVaLI9wl2iW7O//4p/eRf+fTwKc0RySDC0R
# WyKPlj3NBlSyObJMykqfGKGuzucBFoyzPBdayFEdEJfaBUAMow==
# SIG # End signature block
