Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "Project name if the repository is setup for multiple projects", Mandatory = $false)]
    [string] $project = '.',
    [Parameter(HelpMessage = "Direct Download Url of .app or .zip file", Mandatory = $true)]
    [string] $url,
    [Parameter(HelpMessage = "Direct Commit (Y/N)", Mandatory = $false)]
    [bool] $directCommit
)

function getfiles {
    Param(
        [string] $url
    )

    $path = Join-Path $env:TEMP "$([Guid]::NewGuid().ToString()).app"
    Download-File -sourceUrl $url -destinationFile $path
    if (!(Test-Path -Path $path)) {
        throw "could not download the file."
    }

    expandfile -path $path
    Remove-Item $path -Force -ErrorAction SilentlyContinue
}

function expandfile {
    Param(
        [string] $path
    )

    if ([string]::new([char[]](Get-Content $path -Encoding byte -TotalCount 2)) -eq "PK") {
        # .zip file
        $destinationPath = Join-Path $env:TEMP "$([Guid]::NewGuid().ToString())"
        Expand-7zipArchive -path $path -destinationPath $destinationPath

        $directoryInfo = Get-ChildItem $destinationPath | Measure-Object
        if ($directoryInfo.count -eq 0) {
            throw "The file is empty or malformed."
        }

        $appFolders = @()
        if (Test-Path (Join-Path $destinationPath 'app.json')) {
            $appFolders += @($destinationPath)
        }
        Get-ChildItem $destinationPath -Directory -Recurse | Where-Object { Test-Path -Path (Join-Path $_.FullName 'app.json') } | ForEach-Object {
            if (!($appFolders -contains $_.Parent.FullName)) {
                $appFolders += @($_.FullName)
            }
        }
        $appFolders | ForEach-Object {
            $newFolder = Join-Path $env:TEMP "$([Guid]::NewGuid().ToString())"
            Write-Host "$_ -> $newFolder"
            Move-Item -Path $_ -Destination $newFolder -Force
            Write-Host "done"
            $newFolder
        }
        if (Test-Path $destinationPath) {
            Get-ChildItem $destinationPath -Include @("*.zip", "*.app") -Recurse | ForEach-Object {
                expandfile $_.FullName
            }
            Remove-Item -Path $destinationPath -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
    elseif ([string]::new([char[]](Get-Content $path -Encoding byte -TotalCount 4)) -eq "NAVX") {
        $destinationPath = Join-Path $env:TEMP "$([Guid]::NewGuid().ToString())"
        Extract-AppFileToFolder -appFilename $path -appFolder $destinationPath -generateAppJson
        $destinationPath
    }
    else {
        throw "The provided url cannot be extracted. The url might be wrong or the file is malformed."
    }
}

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $branch = "$(if (!$directCommit) { [System.IO.Path]::GetRandomFileName() })"
    $serverUrl = CloneIntoNewFolder -actor $actor -token $token -branch $branch
    $repoBaseFolder = (Get-Location).path
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $repoBaseFolder

    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0070' -parentTelemetryScopeJson $parentTelemetryScopeJson

    $type = "PTE"
    Write-Host "Reading $RepoSettingsFile"
    $settingsJson = Get-Content $RepoSettingsFile -Encoding UTF8 | ConvertFrom-Json
    if ($settingsJson.PSObject.Properties.Name -eq "type") {
        $type = $settingsJson.Type
    }

    CheckAndCreateProjectFolder -project $project
    $baseFolder = (Get-Location).path

    Write-Host "Reading $ALGoSettingsFile"
    $settingsJson = Get-Content $ALGoSettingsFile -Encoding UTF8 | ConvertFrom-Json
    if ($settingsJson.PSObject.Properties.Name -eq "type") {
        $type = $settingsJson.Type
    }

    $appNames = @()
    getfiles -url $url | ForEach-Object {
        $appFolder = $_
        "?Content_Types?.xml", "MediaIdListing.xml", "navigation.xml", "NavxManifest.xml", "DocComments.xml", "SymbolReference.json" | ForEach-Object {
            Remove-Item (Join-Path $appFolder $_) -Force -ErrorAction SilentlyContinue
        }
        $appJson = Get-Content (Join-Path $appFolder "app.json") -Encoding UTF8 | ConvertFrom-Json
        $appNames += @($appJson.Name)

        $ranges = @()
        if ($appJson.PSObject.Properties.Name -eq "idRanges") {
            $ranges += $appJson.idRanges
        }
        if ($appJson.PSObject.Properties.Name -eq "idRange") {
            $ranges += @($appJson.idRange)
        }

        $ttype = ""
        $ranges | Select-Object -First 1 | ForEach-Object {
            if ($_.from -lt 100000 -and $_.to -lt 100000) {
                $ttype = "PTE"
            }
            else {
                $ttype = "AppSource App"
            }
        }

        if ($appJson.PSObject.Properties.Name -eq "dependencies") {
            $appJson.dependencies | ForEach-Object {
                if ($_.PSObject.Properties.Name -eq "AppId") {
                    $id = $_.AppId
                }
                else {
                    $id = $_.Id
                }
                if ($testRunnerApps.Contains($id)) {
                    $ttype = "Test App"
                }
            }
        }

        if ($ttype -ne "Test App") {
            Get-ChildItem -Path $appFolder -Filter "*.al" -Recurse | ForEach-Object {
                $alContent = (Get-Content -Path $_.FullName -Encoding UTF8) -join "`n"
                if ($alContent -like "*codeunit*subtype*=*test*[test]*") {
                    $ttype = "Test App"
                }
            }
        }

        if ($ttype -ne "Test App" -and $ttype -ne $type) {
            OutputWarning -message "According to settings, repository is for apps of type $type. The app you are adding seams to be of type $ttype"
        }

        $appFolders = Get-ChildItem -Path $appFolder -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'app.json') }
        if (-not $appFolders) {
            $appFolders = @($appFolder)
            # TODO: What to do about the über app.json - another workspace? another setting?
        }

        $orgfolderName = $appJson.name.Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
        $folderName = GetUniqueFolderName -baseFolder $baseFolder -folderName $orgfolderName
        if ($folderName -ne $orgfolderName) {
            OutputWarning -message "$orgFolderName already exists as a folder in the repo, using $folderName instead"
        }

        Move-Item -Path $appFolder -Destination $baseFolder -Force
        Rename-Item -Path ([System.IO.Path]::GetFileName($appFolder)) -NewName $folderName
        $appFolder = Join-Path $baseFolder $folderName

        Get-ChildItem $appFolder -Filter '*.*' -Recurse | ForEach-Object {
            if ($_.Name.Contains('%20')) {
                Rename-Item -Path $_.FullName -NewName $_.Name.Replace('%20', ' ')
            }
        }

        $appFolders | ForEach-Object {
            # Modify .AL-Go\settings.json
            try {
                $settingsJsonFile = Join-Path $baseFolder $ALGoSettingsFile
                $SettingsJson = Get-Content $settingsJsonFile -Encoding UTF8 | ConvertFrom-Json
                if (@($settingsJson.appFolders) + @($settingsJson.testFolders)) {
                    if ($ttype -eq "Test App") {
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
                throw "$ALGoSettingsFile is malformed. Error: $($_.Exception.Message)"
            }

            # Modify workspace
            Get-ChildItem -Path $baseFolder -Filter "*.code-workspace" | ForEach-Object {
                try {
                    $workspaceFileName = $_.Name
                    $workspaceFile = $_.FullName
                    $workspace = Get-Content $workspaceFile -Encoding UTF8 | ConvertFrom-Json
                    if (-not ($workspace.folders | Where-Object { $_.Path -eq $foldername })) {
                        $workspace.folders += @(@{ "path" = $foldername })
                    }
                    $workspace | ConvertTo-Json -Depth 99 | Set-Content -Path $workspaceFile -Encoding UTF8
                }
                catch {
                    throw "$workspaceFileName is malformed.$([environment]::Newline) $($_.Exception.Message)"
                }
            }
        }
    }
    Set-Location $repoBaseFolder
    CommitFromNewFolder -serverUrl $serverUrl -commitMessage "Add existing apps ($($appNames -join ', '))" -branch $branch

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message "AddExistingApp acion failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}

# SIG # Begin signature block
# MIIFYQYJKoZIhvcNAQcCoIIFUjCCBU4CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU35VHrYGHA4l+qHDF5K/8YqD0
# HPWgggMAMIIC/DCCAeSgAwIBAgIQWIq0Hnul0rVA6V3CGFkRiTANBgkqhkiG9w0B
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
# DAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQU01ZaW0VDiVwJ5TMJnfYl57A1
# Gh8wDQYJKoZIhvcNAQEBBQAEggEAh8UrblO2e3MhgZ6lNTo6YzgdKr7zlVDF/Kof
# S4KnRa+1LxbNAOFd1GXX4Z7YaWAOiqzA3tLANxaSgNLA443FKngLPnlUp7N1pjOF
# rp+KHSRvQwR40YN3WaUgB3AC4cnm4BovGBJY/Q0sqmil5ODlN7wsmafBitqojy9O
# On1tUZ0j5x88B0vql9RD0HHShsEGbD9x8ib1kDC24Iy9bRBqpWbC5UroK5Dg8rwX
# xdDm+8U8y/WToavPSFHKVviAJ2ovkVSr+wz9klJKu7RIkbC+/YFUzRE+w//GhMzv
# 5FD44BX8u/7ohLMJBqxZ9v2EOBZCqyVlaZyfByVsz4bfaWnNIA==
# SIG # End signature block
