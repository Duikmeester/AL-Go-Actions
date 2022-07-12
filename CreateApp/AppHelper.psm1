<#
This module contains some useful functions for working with app manifests.
#>

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$alTemplatePath = Join-Path -Path $here -ChildPath "AppTemplate"


$validRanges = @{
    "PTE"                  = "50000..99999";
    "AppSource App"        = "100000..$([int32]::MaxValue)";
    "Test App"             = "50000..$([int32]::MaxValue)" ;
    "Performance Test App" = "50000..$([int32]::MaxValue)" ;
};

function Confirm-IdRanges([string] $templateType, [string]$idrange ) {
    $validRange = $validRanges.$templateType.Replace('..', '-').Split("-")
    $validStart = [int] $validRange[0]
    $validEnd = [int] $validRange[1]

    $ids = $idrange.Replace('..', '-').Split("-")
    $idStart = [int] $ids[0]
    $idEnd = [int] $ids[1]

    if ($ids.Count -ne 2 -or ($idStart) -lt $validStart -or $idStart -gt $idEnd -or $idEnd -lt $validStart -or $idEnd -gt $validEnd -or $idStart -gt $idEnd) {
        throw "IdRange should be formatted as fromId..toId, and the Id range must be in $($validRange[0]) and $($validRange[1])"
    }

    return $ids
}

function UpdateManifest
(
    [string] $sourceFolder = $alTemplatePath,
    [string] $appJsonFile,
    [string] $name,
    [string] $publisher,
    [string] $version,
    [string[]] $idrange,
    [switch] $AddTestDependencies
) {
    #Modify app.json
    $appJson = Get-Content (Join-Path $sourceFolder "app.json") -Encoding UTF8 | ConvertFrom-Json

    $appJson.id = [Guid]::NewGuid().ToString()
    $appJson.Publisher = $publisher
    $appJson.Name = $name
    $appJson.Version = $version
    $appJson.Logo = ""
    $appJson.url = ""
    $appJson.EULA = ""
    $appJson.privacyStatement = ""
    $appJson.help = ""
    "contextSensitiveHelpUrl" | ForEach-Object {
        if ($appJson.PSObject.Properties.Name -eq $_) { $appJson.PSObject.Properties.Remove($_) }
    }
    $appJson.idRanges[0].from = [int]$idrange[0]
    $appJson.idRanges[0].to = [int]$idrange[1]
    if ($AddTestDependencies) {
        $appJson.dependencies += @(
            @{
                "id"        = "dd0be2ea-f733-4d65-bb34-a28f4624fb14"
                "publisher" = "Microsoft"
                "name"      = "Library Assert"
                "version"   = $appJson.Application
            },
            @{
                "id"        = "e7320ebb-08b3-4406-b1ec-b4927d3e280b"
                "publisher" = "Microsoft"
                "name"      = "Any"
                "version"   = $appJson.Application
            }
        )

    }
    $appJson | ConvertTo-Json -Depth 99 | Set-Content $appJsonFile -Encoding UTF8
}

function UpdateALFile
(
    [string] $sourceFolder = $alTemplatePath,
    [string] $destinationFolder,
    [string] $alFileName,
    [int] $fromId = 50100,
    [int] $toId = 50100,
    [int] $startId
) {
    $al = Get-Content -Encoding UTF8 -Raw -Path (Join-Path $sourceFolder $alFileName)
    $fromId..$toId | ForEach-Object {
        $al = $al.Replace("$_", $startId)
        $startId++
    }
    Set-Content -Path (Join-Path $destinationFolder $alFileName) -Value $al -Encoding UTF8
}

<#
.SYNOPSIS
Creates a simple app.
#>
function New-SampleApp
(
    [string] $destinationPath,
    [string] $name,
    [string] $publisher,
    [string] $version,
    [string[]] $idrange,
    [bool] $sampleCode
) {
    Write-Host "Creating a new sample app in: $destinationPath"
    New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
    New-Item -Path "$($destinationPath)\.vscode" -ItemType Directory -Force | Out-Null
    Copy-Item -Path "$($alTemplatePath)\.vscode\launch.json" -Destination "$($destinationPath)\.vscode\launch.json"

    UpdateManifest -appJsonFile "$($destinationPath)\app.json" -name $name -publisher $publisher -idrange $idrange -version $version
    if ($sampleCode) {
        UpdateALFile -destinationFolder $destinationPath -alFileName "HelloWorld.al" -startId $idrange[0]
    }
}


# <#
# .SYNOPSIS
# Creates a test app.
# #>
function New-SampleTestApp
(
    [string] $destinationPath,
    [string] $name,
    [string] $publisher,
    [string] $version,
    [string[]] $idrange,
    [bool] $sampleCode
) {
    Write-Host "Creating a new test app in: $destinationPath"
    New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
    New-Item -Path "$($destinationPath)\.vscode" -ItemType Directory -Force | Out-Null
    Copy-Item -Path "$($alTemplatePath)\.vscode\launch.json" -Destination "$($destinationPath)\.vscode\launch.json"

    UpdateManifest -appJsonFile "$($destinationPath)\app.json" -name $name -publisher $publisher -idrange $idrange -version $version -AddTestDependencies
    if ($sampleCode) {
        UpdateALFile -destinationFolder $destinationPath -alFileName "HelloWorld.Test.al" -startId $idrange[0]
    }
}

# <#
# .SYNOPSIS
# Creates a performance test app.
# #>
function New-SamplePerformanceTestApp
(
    [string] $destinationPath,
    [string] $name,
    [string] $publisher,
    [string] $version,
    [string[]] $idrange,
    [bool] $sampleCode,
    [bool] $sampleSuite,
    [string] $appSourceFolder
) {
    Write-Host "Creating a new performance test app in: $destinationPath"
    New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
    New-Item -Path "$($destinationPath)\.vscode" -ItemType Directory -Force | Out-Null
    New-Item -Path "$($destinationPath)\src" -ItemType Directory -Force | Out-Null
    Copy-Item -Path "$($alTemplatePath)\.vscode\launch.json" -Destination "$($destinationPath)\.vscode\launch.json"

    UpdateManifest -sourceFolder $appSourceFolder -appJsonFile "$($destinationPath)\app.json" -name $name -publisher $publisher -idrange $idrange -version $version

    if ($sampleCode) {
        Get-ChildItem -Path "$appSourceFolder\src" -Recurse -Filter "*.al" | ForEach-Object {
            Write-Host $_.Name
            UpdateALFile -sourceFolder $_.DirectoryName -destinationFolder "$($destinationPath)\src" -alFileName $_.name -fromId 149100 -toId 149200 -startId $idrange[0]
        }
    }
    if ($sampleSuite) {
        UpdateALFile -sourceFolder $alTemplatePath -destinationFolder $destinationPath -alFileName bcptSuite.json -fromId 149100 -toId 149200 -startId $idrange[0]
    }
}

function Update-WorkSpaces
(
    [string] $baseFolder,
    [string] $appName
) {
    Get-ChildItem -Path $baseFolder -Filter "*.code-workspace" |
    ForEach-Object {
        try {
            $workspaceFileName = $_.Name
            $workspaceFile = $_.FullName
            $workspace = Get-Content $workspaceFile -Encoding UTF8 | ConvertFrom-Json
            if (-not ($workspace.folders | Where-Object { $_.Path -eq $appName })) {
                $workspace.folders += @(@{ "path" = $appName })
            }
            $workspace | ConvertTo-Json -Depth 99 | Set-Content -Path $workspaceFile -Encoding UTF8
        }
        catch {
            throw "Updating the workspace file $workspaceFileName failed.$([environment]::Newline) $($_.Exception.Message)"
        }
    }
}

Export-ModuleMember -Function New-SampleApp
Export-ModuleMember -Function New-SampleTestApp
Export-ModuleMember -Function New-SamplePerformanceTestApp
Export-ModuleMember -Function Confirm-IdRanges
Export-ModuleMember -Function Update-WorkSpaces

Export-ModuleMember -Function New-SampleApp
Export-ModuleMember -Function New-SampleTestApp
Export-ModuleMember -Function New-SamplePerformanceTestApp
Export-ModuleMember -Function Confirm-IdRanges
Export-ModuleMember -Function Update-WorkSpaces
# SIG # Begin signature block
# MIIFYQYJKoZIhvcNAQcCoIIFUjCCBU4CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUOL6r1rMBOBoXw8XWG2W4IaXw
# mTCgggMAMIIC/DCCAeSgAwIBAgIQWIq0Hnul0rVA6V3CGFkRiTANBgkqhkiG9w0B
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
# DAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUPsi5iryI+I+imxzg+ZrTEeZT
# NbUwDQYJKoZIhvcNAQEBBQAEggEA9ei1QzK+e8xZLBIZqzJexETub4h+WI/j1KhX
# Z4SFXtlEM2RR9540db1xh5Bmo01shh4eozeWysJuKjo0OKpsyRP69wL9Kc+UHsWN
# r3Qg/Ry2WTYaEwEpPRKbCVs5XLbxlEsW0JO4mnCivnBDY7aDlYYQYyDhh+sDyHTX
# u8ORcSqjolXTHd1et5nX45bMSaK0sDeLGzMnJZxykViQ3oI+xPWKstFHbrU9v19j
# QiI7jby82H7iYxB4yUJapA4qvruvaELC8zhtZIeU9sMizsjAWXkbLBXQi1h4vA8h
# FOaamS7YQQ+cxc6cC6p23lKMISM230MsMVTD0vdtPz255FocyQ==
# SIG # End signature block
