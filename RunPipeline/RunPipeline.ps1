Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "",
    [Parameter(HelpMessage = "Settings from repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '{"AppBuild":"", "AppRevision":""}',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = '{"insiderSasToken":"","licenseFileUrl":"","CodeSignCertificateUrl":"","CodeSignCertificatePassword":"","KeyVaultCertificateUrl":"","KeyVaultCertificatePassword":"","KeyVaultClientId":"","StorageContext":"","ApplicationInsightsConnectionString":""}'
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null
$containerBaseFolder = $null
$projectPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0080' -parentTelemetryScopeJson $parentTelemetryScopeJson

    # Pull docker image in the background
    $genericImageName = Get-BestGenericImageName
    Start-Job -ScriptBlock {
        docker pull --quiet $genericImageName
    } -ArgumentList $genericImageName | Out-Null

    $containerName = GetContainerName($project)

    $runAlPipelineParams = @{}
    if ($project -eq ".") { $project = "" }
    $baseFolder = $ENV:GITHUB_WORKSPACE
    if ($bcContainerHelperConfig.useVolumes -and $bcContainerHelperConfig.hostHelperFolder -eq "HostHelperFolder") {
        $allVolumes = "{$(((docker volume ls --format "'{{.Name}}': '{{.Mountpoint}}'") -join ",").Replace('\','\\').Replace("'",'"'))}" | ConvertFrom-Json | ConvertTo-HashTable
        $containerBaseFolder = Join-Path $allVolumes.hostHelperFolder $containerName
        if (Test-Path $containerBaseFolder) {
            Remove-Item -Path $containerBaseFolder -Recurse -Force
        }
        Write-Host "Creating temp folder"
        New-Item -Path $containerBaseFolder -ItemType Directory | Out-Null
        Copy-Item -Path $ENV:GITHUB_WORKSPACE -Destination $containerBaseFolder -Recurse -Force
        $baseFolder = Join-Path $containerBaseFolder (Get-Item -Path $ENV:GITHUB_WORKSPACE).BaseName
    }

    $projectPath = Join-Path $baseFolder $project
    $sharedFolder = ""
    if ($project) {
        $sharedFolder = $baseFolder
    }
    $workflowName = $env:GITHUB_WORKFLOW

    Write-Host "use settings and secrets"
    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable
    $secrets = $secretsJson | ConvertFrom-Json | ConvertTo-HashTable
    $appBuild = $settings.appBuild
    $appRevision = $settings.appRevision
    'licenseFileUrl', 'insiderSasToken', 'CodeSignCertificateUrl', 'CodeSignCertificatePassword', 'KeyVaultCertificateUrl', 'KeyVaultCertificatePassword', 'KeyVaultClientId', 'StorageContext', 'ApplicationInsightsConnectionString' | ForEach-Object {
        if ($secrets.ContainsKey($_)) {
            $value = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$_"))
        }
        else {
            $value = ""
        }
        Set-Variable -Name $_ -Value $value
    }

    $repo = AnalyzeRepo -settings $settings -token $token -baseFolder $baseFolder -project $project -insiderSasToken $insiderSasToken
    if ((-not $repo.appFolders) -and (-not $repo.testFolders)) {
        Write-Host "Repository is empty, exiting"
        exit
    }

    if ($repo.type -eq "AppSource App" ) {
        if ($licenseFileUrl -eq "") {
            OutputError -message "When building an AppSource App, you need to create a secret called LicenseFileUrl, containing a secure URL to your license file with permission to the objects used in the app."
            exit
        }
    }

    if ($storageContext) {
        if ($project) {
            $projectName = $project -replace "[^a-z0-9]", "-"
        }
        else {
            $projectName = $repo.repoName -replace "[^a-z0-9]", "-"
        }
        try {
            if (Get-Command New-AzureStorageContext -ErrorAction SilentlyContinue) {
                Write-Host "Using Azure.Storage PowerShell module"
            }
            else {
                if (!(Get-Command New-AzStorageContext -ErrorAction SilentlyContinue)) {
                    OutputError -message "When publishing to storage account, the build agent needs to have either the Azure.Storage or the Az.Storage PowerShell module installed."
                    exit
                }
                Write-Host "Using Az.Storage PowerShell module"
                Set-Alias -Name New-AzureStorageContext -Value New-AzStorageContext
                Set-Alias -Name Get-AzureStorageContainer -Value Get-AzStorageContainer
                Set-Alias -Name Set-AzureStorageBlobContent -Value Set-AzStorageBlobContent
            }

            $storageAccount = $storageContext | ConvertFrom-Json | ConvertTo-HashTable
            if ($storageAccount.ContainsKey('sastoken')) {
                $storageContext = New-AzureStorageContext -StorageAccountName $storageAccount.StorageAccountName -SasToken $storageAccount.sastoken
            }
            else {
                $storageContext = New-AzureStorageContext -StorageAccountName $storageAccount.StorageAccountName -StorageAccountKey $storageAccount.StorageAccountKey
            }
            Write-Host "Storage Context OK"
            $storageContainerName = $storageAccount.ContainerName.ToLowerInvariant().replace('{project}', $projectName).ToLowerInvariant()
            $storageBlobName = $storageAccount.BlobName.ToLowerInvariant()
            Write-Host "Storage Container Name is $storageContainerName"
            Write-Host "Storage Blob Name is $storageBlobName"
            Get-AzureStorageContainer -Context $storageContext -Name $storageContainerName | Out-Null
        }
        catch {
            OutputWarning -message "StorageContext secret is malformed. Needs to be formatted as Json, containing StorageAccountName, containerName, blobName and sastoken or storageAccountKey, which points to an existing container in a storage account."
            $storageContext = $null
        }
    }

    $artifact = $repo.artifact
    $installApps = $repo.installApps
    $installTestApps = $repo.installTestApps

    if ($repo.appDependencyProbingPaths) {
        Write-Host "Downloading dependencies ..."
        $installApps += Get-dependencies -probingPathsJson $repo.appDependencyProbingPaths -mask "Apps"
        Get-dependencies -probingPathsJson $repo.appDependencyProbingPaths -mask "TestApps" | ForEach-Object {
            $installTestApps += "($_)"
        }
    }

    # Analyze app.json version dependencies before launching pipeline

    # Analyze InstallApps and InstallTestApps before launching pipeline

    # Check if insidersastoken is used (and defined)

    if (!$repo.doNotSignApps -and $CodeSignCertificateUrl -and $CodeSignCertificatePassword) {
        $runAlPipelineParams += @{
            "CodeSignCertPfxFile"     = $codeSignCertificateUrl
            "CodeSignCertPfxPassword" = ConvertTo-SecureString -String $codeSignCertificatePassword -AsPlainText -Force
        }
    }
    if ($applicationInsightsConnectionString) {
        $runAlPipelineParams += @{
            "applicationInsightsConnectionString" = $applicationInsightsConnectionString
        }
    }

    if ($KeyVaultCertificateUrl -and $KeyVaultCertificatePassword -and $KeyVaultClientId) {
        $runAlPipelineParams += @{
            "KeyVaultCertPfxFile"     = $KeyVaultCertificateUrl
            "keyVaultCertPfxPassword" = ConvertTo-SecureString -String $keyVaultCertificatePassword -AsPlainText -Force
            "keyVaultClientId"        = $keyVaultClientId
        }
    }

    $previousApps = @()
    if ($repo.skipUpgrade) {
        OutputWarning -message "Skipping upgrade tests"
    }
    else {
        try {
            $releasesJson = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY
            if ($env:GITHUB_REF_NAME -like 'release/*') {
                # For CI/CD in a release branch use that release as previous build
                $latestRelease = $releasesJson | Where-Object { $_.tag_name -eq "$env:GITHUB_REF_NAME".SubString(8) } | Select-Object -First 1
            }
            else {
                $latestRelease = $releasesJson | Where-Object { -not ($_.prerelease -or $_.draft) } | Select-Object -First 1
            }
            if ($latestRelease) {
                Write-Host "Using $($latestRelease.name) as previous release"
                $artifactsFolder = Join-Path $baseFolder "artifacts"
                New-Item $artifactsFolder -ItemType Directory | Out-Null
                DownloadRelease -token $token -projects $project -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $latestRelease -path $artifactsFolder
                $previousApps += @(Get-ChildItem -Path $artifactsFolder | ForEach-Object { $_.FullName })
            }
            else {
                OutputWarning -message "No previous release found"
            }
        }
        catch {
            OutputError -message "Error trying to locate previous release. Error was $($_.Exception.Message)"
            exit
        }
    }

    $additionalCountries = $repo.additionalCountries

    $imageName = ""
    if ($repo.gitHubRunner -ne "windows-latest") {
        $imageName = $repo.cacheImageName
        if ($imageName) {
            Flush-ContainerHelperCache -keepDays $repo.cacheKeepDays
        }
    }
    $authContext = $null
    $environmentName = ""
    $CreateRuntimePackages = $false

    if ($repo.versioningStrategy -eq -1) {
        $artifactVersion = [Version]$repo.artifact.Split('/')[4]
        $runAlPipelineParams += @{
            "appVersion" = "$($artifactVersion.Major).$($artifactVersion.Minor)"
        }
        $appBuild = $artifactVersion.Build
        $appRevision = $artifactVersion.Revision
    }
    elseif (($repo.versioningStrategy -band 16) -eq 16) {
        $runAlPipelineParams += @{
            "appVersion" = $repo.repoVersion
        }
    }

    $buildArtifactFolder = Join-Path $projectPath ".buildartifacts"
    New-Item $buildArtifactFolder -ItemType Directory | Out-Null

    $allTestResults = "testresults*.xml"
    $testResultsFile = Join-Path $projectPath "TestResults.xml"
    $testResultsFiles = Join-Path $projectPath $allTestResults
    if (Test-Path $testResultsFiles) {
        Remove-Item $testResultsFiles -Force
    }

    $buildOutputFile = Join-Path $projectPath "BuildOutput.txt"

    "containerName=$containerName" | Add-Content $ENV:GITHUB_ENV

    Set-Location $projectPath
    $runAlPipelineOverrides | ForEach-Object {
        $scriptName = $_
        $scriptPath = Join-Path $ALGoFolder "$ScriptName.ps1"
        if (Test-Path -Path $scriptPath -Type Leaf) {
            Write-Host "Add override for $scriptName"
            $runAlPipelineParams += @{
                "$scriptName" = (Get-Command $scriptPath | Select-Object -ExpandProperty ScriptBlock)
            }
        }
    }

    "doNotBuildTests",
    "doNotRunTests",
    "doNotRunBcptTests",
    "doNotPublishApps",
    "installTestRunner",
    "installTestFramework",
    "installTestLibraries",
    "installPerformanceToolkit",
    "enableCodeCop",
    "enableAppSourceCop",
    "enablePerTenantExtensionCop",
    "enableUICop" | ForEach-Object {
        if ($repo."$_") { $runAlPipelineParams += @{ "$_" = $true } }
    }

    Write-Host "Invoke Run-AlPipeline"
    Run-AlPipeline @runAlPipelineParams `
        -pipelineName $workflowName `
        -containerName $containerName `
        -imageName $imageName `
        -bcAuthContext $authContext `
        -environment $environmentName `
        -artifact $artifact.replace('{INSIDERSASTOKEN}', $insiderSasToken) `
        -companyName $repo.companyName `
        -memoryLimit $repo.memoryLimit `
        -baseFolder $projectPath `
        -sharedFolder $sharedFolder `
        -licenseFile $LicenseFileUrl `
        -installApps $installApps `
        -installTestApps $installTestApps `
        -installOnlyReferencedApps:$repo.installOnlyReferencedApps `
        -generateDependencyArtifact:$repo.generateDependencyArtifact `
        -updateDependencies:$repo.updateDependencies `
        -previousApps $previousApps `
        -appFolders $repo.appFolders `
        -testFolders $repo.testFolders `
        -bcptTestFolders $repo.bcptTestFolders `
        -buildOutputFile $buildOutputFile `
        -testResultsFile $testResultsFile `
        -testResultsFormat 'JUnit' `
        -customCodeCops $repo.customCodeCops `
        -gitHubActions `
        -failOn $repo.failOn `
        -rulesetFile $repo.rulesetFile `
        -AppSourceCopMandatoryAffixes $repo.appSourceCopMandatoryAffixes `
        -additionalCountries $additionalCountries `
        -obsoleteTagMinAllowedMajorMinor $repo.obsoleteTagMinAllowedMajorMinor `
        -buildArtifactFolder $buildArtifactFolder `
        -createRuntimePackages:$CreateRuntimePackages `
        -appBuild $appBuild -appRevision $appRevision `
        -uninstallRemovedApps `
        -RemoveBcContainer { Param([Hashtable]$parameters) Remove-BcContainerSession -containerName $parameters.ContainerName -killPsSessionProcess; Remove-BcContainer @parameters }

    if ($storageContext) {
        Write-Host "Publishing to $storageContainerName in $($storageAccount.StorageAccountName)"
        "Apps", "TestApps" | ForEach-Object {
            $type = $_
            $artfolder = Join-Path $buildArtifactFolder $type
            if (Test-Path "$artfolder\*") {
                $versions = @("$($repo.repoVersion).$appBuild.$appRevision-preview", "preview")
                $tempFile = Join-Path $ENV:TEMP "$([Guid]::newguid().ToString()).zip"
                try {
                    Write-Host "Compressing"
                    Compress-Archive -Path $artfolder -DestinationPath $tempFile -Force
                    $versions | ForEach-Object {
                        $version = $_
                        $blob = $storageBlobName.replace('{project}', $projectName).replace('{version}', $version).replace('{type}', $type).ToLowerInvariant()
                        Write-Host "Publishing $blob"
                        Set-AzureStorageBlobContent -Context $storageContext -Container $storageContainerName -File $tempFile -Blob $blob -Force | Out-Null
                    }
                }
                finally {
                    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    if ($containerBaseFolder) {

        Write-Host "Copy artifacts and build output back from build container"
        $destFolder = Join-Path $ENV:GITHUB_WORKSPACE $project
        Copy-Item -Path (Join-Path $projectPath ".buildartifacts") -Destination $destFolder -Recurse -Force
        Copy-Item -Path (Join-Path $projectPath ".output") -Destination $destFolder -Recurse -Force
        Copy-Item -Path (Join-Path $projectPath "testResults*.xml") -Destination $destFolder
        Copy-Item -Path (Join-Path $projectPath "bcptTestResults*.json") -Destination $destFolder
        Copy-Item -Path (Join-Path $projectPath "buildoutput.txt") -Destination $destFolder
    }

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message "RunPipeline action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
    if ($containerBaseFolder -and (Test-Path $containerBaseFolder) -and $projectPath -and (Test-Path $projectPath)) {
        Write-Host "Removing temp folder"
        Remove-Item -Path (Join-Path $projectPath '*') -Recurse -Force
        Write-Host "Done"
    }
}

# SIG # Begin signature block
# MIIFYQYJKoZIhvcNAQcCoIIFUjCCBU4CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUfOP7M8stekOXEN8PgXcEQ3Ns
# +QGgggMAMIIC/DCCAeSgAwIBAgIQWIq0Hnul0rVA6V3CGFkRiTANBgkqhkiG9w0B
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
# DAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUSEHe4UHa1mgqhMlt7q0Yfnxs
# Xe4wDQYJKoZIhvcNAQEBBQAEggEAJhZuKXFbkpGZVzUUeoptSIHLvW0PhVkU+fdM
# IAOTdTdKyQ7JwcsoRqI4GMx3tw39LG80UhvCDslu+FXky5gWhyObwp0/TyK2JJW+
# U4+npNzZV+yekE4I5DylzVGPB8bByLObl0Jx0OxTg0EacVgw3xnUr4sKXOeJNmAP
# w9gzTMkO7SJpjvQ2UsDEPw425W9bGclf9A2eovHhxNDFjyvaxScXSH4nWZnizRyh
# 7ANDKq5NINlveD8jGxOaFsDhp6d+vSD9GfIR7EKCbmpH4BsXvNlS6IPyVHCksDBG
# hpVHmiCSdUMYf3mreO5brsYQ7cQ/spPoZt8cYGlF3xCDMgQ19Q==
# SIG # End signature block
