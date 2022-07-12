Param(
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ".",
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}'
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
    $telemetryScope = CreateScope -eventId 'DO0077' -parentTelemetryScopeJson $parentTelemetryScopeJson

    if ($project -eq ".") { $project = "" }

    $containerName = GetContainerName($project)
    Remove-BcContainer $containerName

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message "PipelineCleanup action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
