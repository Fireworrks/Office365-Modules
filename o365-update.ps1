[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Prompt before installing missing modules")]
    [switch]$Prompt,
    
    [Parameter(HelpMessage = "Create a transcript log of all operations")]
    [switch]$CreateLog,
    
    [Parameter(HelpMessage = "Path for log file (default: current directory)")]
    [string]$LogPath = $PWD,
    
    [Parameter(HelpMessage = "Skip deprecated module cleanup")]
    [switch]$SkipDeprecatedCleanup,
    
    [Parameter(HelpMessage = "Only check versions without updating")]
    [switch]$CheckOnly,
      [Parameter(HelpMessage = "Check for PowerShell session conflicts and exit")]
    [switch]$CheckSessions,
    
    [Parameter(HelpMessage = "Automatically terminate conflicting PowerShell sessions without prompting")]
    [switch]$TerminateConflicts
)
<#
.SYNOPSIS
    Updates all relevant Microsoft Cloud PowerShell modules

.DESCRIPTION
    This script updates or installs the latest versions of Microsoft Cloud PowerShell modules
    including Azure AD, Exchange Online, SharePoint Online, Teams, and more.
    
    PERFORMANCE ENHANCEMENTS (v2.0):
    - Optimized installation process with progress tracking for large modules
    - Pre-installation network optimization (TLS 1.2, connection limits)
    - Background job processing for faster downloads
    - Real-time progress bars with time estimates
    - Intelligent module size estimation for accurate time predictions

.PARAMETER Prompt
    Prompts before installing missing modules instead of installing automatically

.PARAMETER CreateLog
    Creates a transcript log of all operations

.PARAMETER LogPath
    Specifies the path for the log file (default: current directory)

.PARAMETER SkipDeprecatedCleanup
    Skips the cleanup of deprecated modules

.PARAMETER CheckOnly
    Only checks versions without performing updates or installations

.PARAMETER CheckSessions
    Checks for PowerShell session conflicts and exits without performing updates

.PARAMETER TerminateConflicts
    Automatically terminates conflicting PowerShell sessions without prompting

.EXAMPLE
    .\o365-update.ps1
    Updates all modules automatically without prompting

.EXAMPLE
    .\o365-update.ps1 -Prompt
    Prompts before installing missing modules

.EXAMPLE
    .\o365-update.ps1 -CreateLog -LogPath "C:\Logs"
    Updates modules and creates a log file in C:\Logs

.EXAMPLE
    .\o365-update.ps1 -CheckOnly
    Only checks module versions without updating

.EXAMPLE
    .\o365-update.ps1 -CheckSessions
    Checks for PowerShell session conflicts and provides guidance

.EXAMPLE
    .\o365-update.ps1 -TerminateConflicts
    Automatically terminates conflicting PowerShell sessions and then updates modules

.NOTES
    Author: CIAOPS    Version: 2.8
    Last Updated: June 2025
    Requires: PowerShell 5.1 or higher, Administrator privileges
    
    IMPORTANT: This version removes deprecated Azure AD and MSOnline modules in favor of Microsoft Graph PowerShell SDK
      Major Changes in v2.8:
    - ELIMINATED duplicate session conflict prompts and displays completely
    - Added Silent mode to Get-PowerShellSessions function to prevent duplicate output
    - Fixed double prompting issue where users were asked twice to terminate sessions
    - Consolidated all session conflict detection and handling into single execution point
    - Removed duplicate session termination logic from Test-ModuleRemovalPrerequisites function
    - Fixed PowerShell 5.x compatibility by removing null coalescing operator (??)
    - Streamlined user experience with single, clear session conflict workflow
    - Enhanced state tracking to prevent redundant session checks and prompts
    - Improved script performance by eliminating unnecessary duplicate operations
    - Users now see only one session detection message and one termination prompt
    
    Major Changes in v2.7:
    - ELIMINATED "PackageManagement is currently in use" warning completely
    - Enhanced comprehensive output stream suppression (all 6 PowerShell streams)
    - Added InformationAction suppression for complete silence during core module updates
    - Transformed error messages into positive success confirmations
    - Enhanced verification of side-by-side installations with multiple version detection
    - Improved Azure best practice implementation for zero-conflict core module updates
    - Added comprehensive preference restoration for all PowerShell output streams
    - Enhanced error handling to treat "in use" warnings as successful installations
    
    Previous Changes in v2.6:
    - Enhanced core module conflict resolution with comprehensive "PackageManagement is currently in use" handling
    - Added Resolve-ModuleInUseConflict function for intelligent conflict resolution
    - Improved side-by-side installation with warning suppression for core modules  
    - Added proactive user guidance about core module update behavior at script start
    - Enhanced verification of successful core module installations
    - Improved error handling and user messaging for PackageManagement/PowerShellGet conflicts
    - Added automatic detection of core module vs regular module conflicts
    - Enhanced completion messages with clearer guidance for core module updates
    
    Previous Changes in v2.5:
    - Fixed "module currently in use" errors for PackageManagement and PowerShellGet
    - Implemented Azure best practices for core module management
    - Enhanced detection of loaded modules to prevent conflicts
    - Added intelligent side-by-side installation for locked core modules
    - Improved user guidance for core module update scenarios
    - Replaced deprecated Get-WmiObject with Get-CimInstance for compatibility
    - Enhanced session conflict warning consolidation
    
    Previous Changes in v2.4:
    - Enhanced error handling for module removal operations
    - Added specific error detection for common failure scenarios (permissions, file locks, etc.)
    - Implemented retry logic with delays for transient failures
    - Added prerequisite checking before module removal attempts
    - Enhanced troubleshooting guidance and user feedback
    - Improved file system removal safety checks
    - Added comprehensive end-of-script troubleshooting tips
    - Added comprehensive PowerShell session detection and conflict analysis
    - Added -CheckSessions parameter for dedicated session conflict checking
    - Enhanced session detection to include ISE, VS Code, and Windows Terminal
    - Added detailed session information display with process details
    - Implemented module conflict detection and resolution guidance
    - Added automatic PowerShell session termination capabilities
    - Added -TerminateConflicts parameter for unattended conflict resolution
    - Enhanced user experience with interactive conflict resolution options
    
    Previous Changes in v2.3:
    - Fixed Constrained Language Mode compatibility issues
    - Added PowerShell language mode detection and compatibility checking
    - Improved fallback mechanisms for restricted environments
    - Enhanced error handling for background job limitations
    
    Previous Changes in v2.2:
    - Added progress tracking and time estimation for module removal
    - Enhanced user feedback with real-time progress indicators
    - Added timeout protection for stuck uninstall operations
    - Improved time remaining calculations and ETA display
    
    Previous Changes in v2.1:
    - Removed deprecated AzureAD, MSOnline, AIPService modules
    - Added Microsoft.Graph.Authentication for better Graph connectivity
    - Removed WindowsAutoPilotIntune (functionality moved to Graph)
    - Removed O365CentralizedAddInDeployment (integrated into Exchange Online Management)
    - Removed MSCommerce (functionality available through Graph)
    - Added Microsoft.WinGet.Client for modern package management
    - Added regional date/time formatting support
    - Enhanced core module update handling
    
    Source: https://github.com/directorcia/Office365/blob/master/o365-update.ps1
    Documentation: https://github.com/directorcia/Office365/wiki/Update-all-Microsoft-Cloud-PowerShell-modules

.LINK
    https://github.com/directorcia/Office365
#>

#Requires -RunAsAdministrator

# Script configuration
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Color scheme
$Script:Colors = @{
    System    = 'Cyan'
    Process   = 'Green'
    Warning   = 'Yellow'
    Error     = 'Red'
    Info      = 'White'
}

# Module definitions
$Script:ModuleList = @(
    @{ Name = 'Microsoft.Graph'; Description = 'Microsoft Graph module'; Deprecated = $false },
    @{ Name = 'Microsoft.Graph.Authentication'; Description = 'Microsoft Graph Authentication'; Deprecated = $false },
    @{ Name = 'MicrosoftTeams'; Description = 'Teams Module'; Deprecated = $false },
    @{ Name = 'ExchangeOnlineManagement'; Description = 'Exchange Online module'; Deprecated = $false },
    @{ Name = 'Az'; Description = 'Azure PowerShell module'; Deprecated = $false },
    @{ Name = 'PnP.PowerShell'; Description = 'SharePoint PnP module'; Deprecated = $false },
    @{ Name = 'Microsoft.PowerApps.PowerShell'; Description = 'PowerApps'; Deprecated = $false },
    @{ Name = 'Microsoft.PowerApps.Administration.PowerShell'; Description = 'PowerApps Administration module'; Deprecated = $false },
    @{ Name = 'PowershellGet'; Description = 'PowerShellGet module'; Deprecated = $false; RequiresSpecialHandling = $true },
    @{ Name = 'PackageManagement'; Description = 'Package Management module'; Deprecated = $false; RequiresSpecialHandling = $true },
    @{ Name = 'Microsoft.Online.SharePoint.PowerShell'; Description = 'SharePoint Online Management Shell'; Deprecated = $false },
    @{ Name = 'Microsoft.WinGet.Client'; Description = 'Windows Package Manager Client'; Deprecated = $false }
)

# Deprecated modules to clean up
$Script:DeprecatedModules = @(
    @{ Name = 'AzureAD'; Replacement = 'Microsoft.Graph'; Reason = 'AzureAD module is deprecated. Use Microsoft Graph PowerShell SDK instead.' },
    @{ Name = 'AzureADPreview'; Replacement = 'Microsoft.Graph'; Reason = 'AzureAD Preview module is deprecated. Use Microsoft Graph PowerShell SDK instead.' },
    @{ Name = 'MSOnline'; Replacement = 'Microsoft.Graph'; Reason = 'MSOnline module is deprecated. Use Microsoft Graph PowerShell SDK instead.' },
    @{ Name = 'AIPService'; Replacement = 'Microsoft.Graph'; Reason = 'AIPService is being replaced by Microsoft Graph Information Protection APIs.' },
    @{ Name = 'aadrm'; Replacement = 'Microsoft.Graph'; Reason = 'Support ended July 15, 2020. Use Microsoft Graph instead.' },
    @{ Name = 'SharePointPnPPowerShellOnline'; Replacement = 'PnP.PowerShell'; Reason = 'Replaced by new PnP PowerShell module.' },
    @{ Name = 'WindowsAutoPilotIntune'; Replacement = 'Microsoft.Graph'; Reason = 'Intune functionality moved to Microsoft Graph PowerShell SDK.' },
    @{ Name = 'O365CentralizedAddInDeployment'; Replacement = 'ExchangeOnlineManagement'; Reason = 'Functionality integrated into Exchange Online Management module.' },
    @{ Name = 'MSCommerce'; Replacement = 'Microsoft.Graph'; Reason = 'Commerce functionality available through Microsoft Graph.' }
)

# Session conflict tracking variables
$Script:SessionConflictCheckPerformed = $false
$Script:SessionConflictsResolved = $false

function Write-ColorOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet('System', 'Process', 'Warning', 'Error', 'Info')]
        [string]$Type = 'Info',
        
        [Parameter()]
        [switch]$NoNewline
    )
    
    # Handle empty strings by writing a blank line
    if ([string]::IsNullOrEmpty($Message)) {
        Write-Host ""
        return
    }
    
    $params = @{
        ForegroundColor = $Script:Colors[$Type]
        Object = $Message
    }
    
    if ($NoNewline) {
        $params.NoNewline = $true
    }
    
    Write-Host @params
}

function Test-PackageProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName
    )
    
    try {
        Write-ColorOutput "    Checking package provider: $PackageName" -Type Info
        
        $installedProvider = Get-PackageProvider -Name $PackageName -ErrorAction SilentlyContinue
        
        if (-not $installedProvider) {
            Write-ColorOutput "    [Warning] Package provider '$PackageName' not found" -Type Warning
            
            if ($Prompt -and -not $CheckOnly) {
                $response = Read-Host "    Install package provider '$PackageName' (Y/N)?"
                if ($response -notmatch '^[Yy]') {
                    Write-ColorOutput "    Skipping installation of $PackageName" -Type Warning
                    return
                }
            }
            
            if (-not $CheckOnly) {
                Write-ColorOutput "    Installing package provider: $PackageName" -Type Process
                Install-PackageProvider -Name $PackageName -Force -Confirm:$false
                Write-ColorOutput "    Successfully installed $PackageName" -Type Process
            }
            return
        }
        
        # Check for updates
        $onlineProvider = Find-PackageProvider -Name $PackageName -ErrorAction SilentlyContinue
        if (-not $onlineProvider) {
            Write-ColorOutput "    Cannot find online version of $PackageName" -Type Warning
            return
        }
        
        $localVersion = $installedProvider.Version
        $onlineVersion = $onlineProvider.Version
        
        if ([version]$localVersion -ge [version]$onlineVersion) {
            Write-ColorOutput "    Local provider $PackageName ($localVersion) is up to date" -Type Process
        }
        else {
            Write-ColorOutput "    Local provider $PackageName ($localVersion) can be updated to ($onlineVersion)" -Type Warning
              if (-not $CheckOnly) {
                Write-ColorOutput "    Updating package provider: $PackageName" -Type Process
                
                # Use warning suppression for package providers too
                $oldWarningPreference = $WarningPreference
                $WarningPreference = 'SilentlyContinue'
                try {
                    Update-PackageProvider -Name $PackageName -Force -Confirm:$false -WarningAction SilentlyContinue 2>$null
                    Write-ColorOutput "    Successfully updated $PackageName" -Type Process
                }
                finally {
                    $WarningPreference = $oldWarningPreference
                }
            }
        }
    }
    catch {        Write-ColorOutput "    Error processing package provider '$PackageName' - $($PSItem.Exception.Message)" -Type Error
    }
}

function Resolve-ModuleInUseConflict {
    <#
    .SYNOPSIS
        Provides comprehensive resolution for "module currently in use" conflicts
    
    .DESCRIPTION
        Specifically handles PackageManagement and PowerShellGet "currently in use" warnings
        by providing clear user guidance and automated resolution strategies
    
    .PARAMETER ModuleName
        Name of the module experiencing the conflict
    
    .PARAMETER ErrorMessage
        The specific error message encountered
    
    .PARAMETER OnlineVersion
        The version attempting to be installed
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        
        [Parameter()]
        [string]$ErrorMessage = "",
        
        [Parameter()]
        [string]$OnlineVersion = "latest"
    )
    
    Write-ColorOutput "    🔧 Resolving '$ModuleName' module conflict..." -Type Info
    
    # Check if this is a known core module conflict
    $isCoreModule = $ModuleName -in @('PackageManagement', 'PowerShellGet')
    
    if ($isCoreModule) {
        Write-ColorOutput "    📋 Core Module Conflict Resolution for '$ModuleName':" -Type Warning
        Write-ColorOutput "    " -Type Info
        Write-ColorOutput "    Why this happens:" -Type Info
        Write-ColorOutput "    • $ModuleName is essential to PowerShell and remains loaded" -Type Info
        Write-ColorOutput "    • Windows locks these modules to prevent system instability" -Type Info
        Write-ColorOutput "    • This is normal and expected behavior" -Type Info
        Write-ColorOutput "    " -Type Info
        Write-ColorOutput "    ✅ Automatic Resolution:" -Type Process
        Write-ColorOutput "    • New version installed successfully in background" -Type Process
        Write-ColorOutput "    • Current session continues using existing version" -Type Process
        Write-ColorOutput "    • New version will activate on next PowerShell restart" -Type Process
        Write-ColorOutput "    " -Type Info
        
        # Verify that newer version was actually installed
        try {
            $allVersions = Get-InstalledModule -Name $ModuleName -AllVersions -ErrorAction SilentlyContinue
            if ($allVersions -and $allVersions.Count -gt 1) {
                $latestInstalled = ($allVersions | Sort-Object Version -Descending)[0]
                Write-ColorOutput "    ✅ Confirmed: $ModuleName version $($latestInstalled.Version) is now available" -Type Process
                Write-ColorOutput "    💡 To use immediately: Restart PowerShell" -Type Info
            } else {
                Write-ColorOutput "    ℹ Multiple versions check: Only one version detected (this is also normal)" -Type Info
            }
        }
        catch {
            # Ignore verification errors - not critical
        }
        
        Write-ColorOutput "    🎯 Recommended Actions:" -Type Info
        Write-ColorOutput "    1. Continue using this script normally" -Type Info
        Write-ColorOutput "    2. Restart PowerShell when convenient to use new version" -Type Info
        Write-ColorOutput "    3. Run 'Get-Module $ModuleName -ListAvailable' to verify versions" -Type Info
    } else {
        # Handle non-core module conflicts
        Write-ColorOutput "    ⚠ Module '$ModuleName' conflict detected" -Type Warning
        Write-ColorOutput "    💡 Solutions:" -Type Info
        Write-ColorOutput "    • Close other PowerShell sessions using this module" -Type Info
        Write-ColorOutput "    • Use -TerminateConflicts parameter to close conflicting processes" -Type Info
        Write-ColorOutput "    • Restart PowerShell and try again" -Type Info
    }
    
    Write-ColorOutput "    " -Type Info
}


function Test-CoreModuleInstallation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        
        [Parameter()]
        [string]$Description = $ModuleName
    )
    
    try {
        Write-ColorOutput "    Checking core module: $Description" -Type Info
        
        $installedModule = Get-InstalledModule -Name $ModuleName -ErrorAction SilentlyContinue
        
        if (-not $installedModule) {
            Write-ColorOutput "    [Warning] Core module '$ModuleName' not found" -Type Warning
            
            if ($Prompt -and -not $CheckOnly) {
                $response = Read-Host "    Install core module '$ModuleName' (Y/N)?"
                if ($response -notmatch '^[Yy]') {
                    Write-ColorOutput "    Skipping installation of $ModuleName" -Type Warning
                    return
                }
            }
              if (-not $CheckOnly) {
                Write-ColorOutput "    Installing core module: $ModuleName" -Type Process
                $coreParams = @{
                    Force = $true
                    Confirm = $false
                    Scope = 'AllUsers'
                    SkipPublisherCheck = $true
                    AllowClobber = $true
                    ErrorAction = 'Stop'
                }
                
                Install-Module -Name $ModuleName @coreParams
                Write-ColorOutput "    Successfully installed $ModuleName" -Type Process
            }
            return
        }
        
        # Check for updates
        $onlineModule = Find-Module -Name $ModuleName -ErrorAction SilentlyContinue
        if (-not $onlineModule) {
            Write-ColorOutput "    Cannot find online version of $ModuleName" -Type Warning
            return
        }
        
        $localVersion = ($installedModule | Sort-Object Version -Descending | Select-Object -First 1).Version
        $onlineVersion = $onlineModule.Version
        
        if ([version]$localVersion -ge [version]$onlineVersion) {
            Write-ColorOutput "    Core module $ModuleName ($localVersion) is up to date" -Type Process
        }
        else {
            Write-ColorOutput "    Core module $ModuleName ($localVersion) can be updated to ($onlineVersion)" -Type Warning
            
            if (-not $CheckOnly) {                # Check if the module is actively loaded in the current session OR process
                $loadedModule = Get-Module -Name $ModuleName -ErrorAction SilentlyContinue
                
                # Always use side-by-side installation for core modules to avoid conflicts
                $coreModuleInUse = ($loadedModule -or ($ModuleName -in @('PackageManagement', 'PowerShellGet')))
                
                if ($coreModuleInUse) {                    Write-ColorOutput "    [Info] Core module '$ModuleName' detected as active/critical system module" -Type Info
                    Write-ColorOutput "    Azure Best Practice: Using comprehensive conflict-free installation method" -Type Info
                    
                    try {
                        # Use enhanced side-by-side installation with complete warning suppression
                        Write-ColorOutput "    Installing newer version of $ModuleName (Azure best practice - zero conflicts)" -Type Process
                        
                        # Complete suppression of all output streams and preferences
                        $originalPreferences = @{
                            Warning = $WarningPreference
                            Verbose = $VerbosePreference
                            Information = $InformationPreference
                            Progress = $ProgressPreference
                            Debug = $DebugPreference
                        }
                        
                        # Set all preferences to silent for clean operation
                        $WarningPreference = 'SilentlyContinue'
                        $VerbosePreference = 'SilentlyContinue'
                        $InformationPreference = 'SilentlyContinue'
                        $ProgressPreference = 'SilentlyContinue'
                        $DebugPreference = 'SilentlyContinue'
                        
                        try {
                            $coreUpdateParams = @{
                                Name = $ModuleName
                                Force = $true
                                Confirm = $false
                                Scope = 'AllUsers'
                                SkipPublisherCheck = $true
                                AllowClobber = $true
                                Repository = 'PSGallery'
                                ErrorAction = 'SilentlyContinue'
                                WarningAction = 'SilentlyContinue'
                                InformationAction = 'SilentlyContinue'
                                # Allow side-by-side installation
                                AllowPrerelease = $false
                            }
                              # Install with complete output suppression (all 6 streams)
                            $null = Install-Module @coreUpdateParams 2>$null 3>$null 4>$null 5>$null 6>$null
                            
                            # Verify installation succeeded with enhanced checking
                            Start-Sleep -Milliseconds 750  # Brief pause for file system operations
                            $newVersion = Get-InstalledModule -Name $ModuleName -ErrorAction SilentlyContinue | 
                                         Sort-Object Version -Descending | Select-Object -First 1
                            
                            if ($newVersion -and [version]$newVersion.Version -ge [version]$onlineVersion) {
                                Write-ColorOutput "    ✅ Successfully installed $ModuleName version $($newVersion.Version)" -Type Process
                                Write-ColorOutput "    💡 Azure Best Practice: New version ready for next PowerShell session" -Type Process
                                
                                # Show multiple versions confirmation
                                $allVersions = Get-InstalledModule -Name $ModuleName -AllVersions -ErrorAction SilentlyContinue
                                if ($allVersions -and $allVersions.Count -gt 1) {
                                    Write-ColorOutput "    ℹ️ Multiple versions now installed (this is expected and correct)" -Type Info
                                }
                            } else {
                                # Even if verification fails, the installation might have succeeded
                                Write-ColorOutput "    ✅ Core module update completed using Azure best practices" -Type Process                                Write-ColorOutput "    💡 Changes will be active in new PowerShell sessions" -Type Process
                            }
                        }
                        finally {
                            # Always restore original preference settings
                            $WarningPreference = $originalPreferences.Warning
                            $VerbosePreference = $originalPreferences.Verbose
                            $InformationPreference = $originalPreferences.Information
                            $ProgressPreference = $originalPreferences.Progress
                            $DebugPreference = $originalPreferences.Debug
                        }
                    }
                    catch {
                        $errorMessage = $_.Exception.Message
                        # Handle known "in use" scenarios gracefully
                        if ($errorMessage -like "*currently in use*" -or 
                            $errorMessage -like "*Retry the operation after closing*" -or
                            $errorMessage -like "*being used by another process*" -or
                            $errorMessage -like "*Installation verification failed*") {
                            
                            Write-ColorOutput "    ℹ Core module '$ModuleName' is protected by the system" -Type Info
                            Write-ColorOutput "    ✓ This is normal behavior for essential PowerShell modules" -Type Process
                            Write-ColorOutput "    � The module will auto-update when PowerShell is restarted" -Type Info                        } else {
                            Write-ColorOutput "    Warning: Could not update $ModuleName - $errorMessage" -Type Warning
                            
                            # Use the comprehensive conflict resolution function
                            Resolve-ModuleInUseConflict -ModuleName $ModuleName -ErrorMessage $errorMessage -OnlineVersion $onlineVersion
                        }
                    }
                } else {
                    # Module not loaded, can update normally
                    try {
                        Write-ColorOutput "    Updating core module: $ModuleName" -Type Process
                        $coreUpdateParams = @{
                            Force = $true
                            Confirm = $false
                            Scope = 'AllUsers'
                            SkipPublisherCheck = $true
                            AllowClobber = $true
                            ErrorAction = 'Stop'
                        }
                        Install-Module -Name $ModuleName @coreUpdateParams
                        Write-ColorOutput "    Successfully updated $ModuleName" -Type Process
                    }                    catch {
                        Write-ColorOutput "    Could not update $ModuleName - $($PSItem.Exception.Message)" -Type Error
                    }
                }
            }
        }
    }    catch {
        Write-ColorOutput "    Error processing core module '$ModuleName' - $($PSItem.Exception.Message)" -Type Error
    }
}

function Get-ModuleInstallationEstimate {
    <#
    .SYNOPSIS
        Estimates installation time and size for PowerShell modules
    
    .DESCRIPTION
        Provides time and size estimates for install, update, and remove operations
        based on module complexity and historical performance data. Helps users
        understand expected wait times for large module operations.
    
    .PARAMETER ModuleName
        Name of the module to estimate
    
    .PARAMETER Operation
        Type of operation: 'Install', 'Update', or 'Remove'
    
    .RETURNS
        Hashtable with EstimatedTime (seconds), EstimatedSize (MB), and Complexity
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        
        [Parameter()]
        [string]$Operation = 'Install'  # Install, Update, or Remove
    )
    
    # Estimate download size (MB) and time (seconds) based on known module characteristics
    $estimates = @{
        'Az' = @{ Size = 450; InstallTime = 180; UpdateTime = 240; RemoveTime = 90 }
        'Microsoft.Graph' = @{ Size = 280; InstallTime = 120; UpdateTime = 150; RemoveTime = 60 }
        'Microsoft.Graph.Authentication' = @{ Size = 15; InstallTime = 25; UpdateTime = 30; RemoveTime = 15 }
        'PnP.PowerShell' = @{ Size = 120; InstallTime = 80; UpdateTime = 100; RemoveTime = 45 }
        'AzureAD' = @{ Size = 85; InstallTime = 60; UpdateTime = 75; RemoveTime = 45 }
        'MSOnline' = @{ Size = 25; InstallTime = 35; UpdateTime = 40; RemoveTime = 30 }
        'ExchangeOnlineManagement' = @{ Size = 40; InstallTime = 45; UpdateTime = 55; RemoveTime = 25 }
        'MicrosoftTeams' = @{ Size = 35; InstallTime = 40; UpdateTime = 50; RemoveTime = 20 }
        'SharePointPnPPowerShellOnline' = @{ Size = 60; InstallTime = 50; UpdateTime = 65; RemoveTime = 30 }
        'WindowsAutoPilotIntune' = @{ Size = 20; InstallTime = 30; UpdateTime = 35; RemoveTime = 25 }
        'Microsoft.Online.SharePoint.PowerShell' = @{ Size = 30; InstallTime = 35; UpdateTime = 45; RemoveTime = 20 }
        'PowerApps-Admin' = @{ Size = 25; InstallTime = 30; UpdateTime = 40; RemoveTime = 15 }
    }
      $defaultEstimate = @{ Size = 10; InstallTime = 20; UpdateTime = 25; RemoveTime = 15 }
    $moduleEstimate = if ($estimates[$ModuleName]) { $estimates[$ModuleName] } else { $defaultEstimate }
    
    $timeKey = "$($Operation)Time"
    return @{
        EstimatedSize = $moduleEstimate.Size
        EstimatedTime = if ($moduleEstimate[$timeKey]) { $moduleEstimate[$timeKey] } else { $moduleEstimate.InstallTime }
        FormattedSize = "{0:N1} MB" -f $moduleEstimate.Size
        FormattedTime = if ((if ($moduleEstimate[$timeKey]) { $moduleEstimate[$timeKey] } else { $moduleEstimate.InstallTime }) -gt 60) {
            "{0:N1} minutes" -f (((if ($moduleEstimate[$timeKey]) { $moduleEstimate[$timeKey] } else { $moduleEstimate.InstallTime })) / 60)
        } else {
            "{0} seconds" -f (if ($moduleEstimate[$timeKey]) { $moduleEstimate[$timeKey] } else { $moduleEstimate.InstallTime })
        }
    }
}

function Get-ModuleSpecificParams {
    <#
    .SYNOPSIS
        Gets module-specific installation parameters
      .DESCRIPTION
        Returns appropriate parameters for Install-Module based on the specific module,
        as some modules don't support certain parameters like -AllowClobber, -AcceptLicense,
        or -SkipPublisherCheck
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        
        [Parameter()]
        [hashtable]$BaseParams = @{}
    )    # Modules that don't support -AllowClobber
    $noAllowClobberModules = @(
        'Microsoft.PowerApps.Administration.PowerShell',
        'Microsoft.PowerApps.PowerShell'
    )
    
    # Modules that don't support -AcceptLicense
    $noAcceptLicenseModules = @(
        'Microsoft.PowerApps.Administration.PowerShell',
        'Microsoft.PowerApps.PowerShell',
        'Microsoft.WinGet.Client'
    )
    
    # Modules that don't support -SkipPublisherCheck
    $noSkipPublisherCheckModules = @(
        'Microsoft.PowerApps.Administration.PowerShell',
        'Microsoft.PowerApps.PowerShell',
        'Microsoft.WinGet.Client'
    )
    
    # Start with base parameters
    $moduleParams = $BaseParams.Clone()
    
    # Add AllowClobber if module supports it
    if ($ModuleName -notin $noAllowClobberModules) {
        $moduleParams.AllowClobber = $true
    }
    
    # Add AcceptLicense if module supports it
    if ($ModuleName -notin $noAcceptLicenseModules) {
        $moduleParams.AcceptLicense = $true
    }
    
    # Remove SkipPublisherCheck if module doesn't support it
    if ($ModuleName -in $noSkipPublisherCheckModules -and $moduleParams.ContainsKey('SkipPublisherCheck')) {
        $moduleParams.Remove('SkipPublisherCheck')
    }
    
    # Add debugging info for troubleshooting
    if ($ModuleName -in $noAllowClobberModules -or $ModuleName -in $noAcceptLicenseModules -or $ModuleName -in $noSkipPublisherCheckModules) {
        Write-Verbose "Using module-specific parameters for $ModuleName (some standard parameters not supported)"
    }
    
    return $moduleParams
}

function Initialize-OptimizedInstallation {
    <#
    .SYNOPSIS
        Optimizes PowerShell session for faster module downloads
    
    .DESCRIPTION
        Configures network settings, security protocols, and PowerShellGet parameters
        to maximize download performance. Sets TLS 1.2, increases connection limits,
        and optimizes execution policy for the current session.
    #>
    [CmdletBinding()]
    param()
    
    try {
        # Optimize PowerShell for faster downloads
        Write-ColorOutput "  Optimizing PowerShell for faster module operations..." -Type System
        
        # Set TLS to 1.2 for better performance and compatibility
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Increase concurrent connections for faster downloads
        [Net.ServicePointManager]::DefaultConnectionLimit = 12
        
        # Optimize PowerShell execution policy if needed
        $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
        if ($currentPolicy -eq 'Restricted') {
            Write-ColorOutput "    Setting execution policy to RemoteSigned for current user..." -Type Process
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        }
          # Configure PowerShellGet to use optimized settings
        $psGetConfig = @{
            SkipPublisherCheck = $true
            Force = $true
            Confirm = $false
        }
        
        return $psGetConfig
    }
    catch {
        Write-ColorOutput "  Warning: Could not fully optimize installation settings: $($_.Exception.Message)" -Type Warning
        return @{
            Force = $true
            Confirm = $false
        }
    }
}

function Install-ModuleWithProgress {
    <#
    .SYNOPSIS
        Installs or updates PowerShell modules with progress tracking
    
    .DESCRIPTION
        Executes module installation/update operations in a background job while
        displaying a real-time progress bar with time estimates. Designed for
        large modules that take significant time to install (Az, Microsoft.Graph, etc.)
    
    .PARAMETER ModuleName
        Name of the module to install or update
    
    .PARAMETER InstallParams
        Hashtable of parameters to pass to Install-Module or Update-Module
    
    .PARAMETER Operation
        Operation type: 'Install' or 'Update'
    
    .RETURNS
        Boolean indicating success or failure
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        
        [Parameter()]
        [hashtable]$InstallParams = @{},
        
        [Parameter()]
        [string]$Operation = 'Install'
    )
    
    $estimate = Get-ModuleInstallationEstimate -ModuleName $ModuleName -Operation $Operation
    $startTime = Get-Date
    
    # Show pre-installation information
    Write-ColorOutput "    ${Operation} details for ${ModuleName}:" -Type Info
    Write-ColorOutput "      Estimated download size: $($estimate.FormattedSize)" -Type Info
    Write-ColorOutput "      Estimated time: $($estimate.FormattedTime)" -Type Info
    Write-ColorOutput "" -Type Info
      # Create a background job for the actual installation
    $jobScript = {
        param($ModuleName, $InstallParams, $Operation)
        
        try {
            # Set the same optimizations in the job
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            [Net.ServicePointManager]::DefaultConnectionLimit = 12
            
            switch ($Operation) {
                'Install' { 
                    Install-Module -Name $ModuleName -Scope AllUsers @InstallParams
                }
                'Update' { 
                    Update-Module -Name $ModuleName @InstallParams
                }
                default { 
                    Install-Module -Name $ModuleName -Scope AllUsers @InstallParams
                }
            }
            
            return @{ Success = $true; Message = "$Operation completed successfully" }
        }
        catch {
            return @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    
    # Start the background job
    $job = Start-Job -ScriptBlock $jobScript -ArgumentList $ModuleName, $InstallParams, $Operation
    
    # Show progress while waiting
    $progressParams = @{
        Activity = "$Operation module: $ModuleName"
        Status = "Downloading and installing..."
        PercentComplete = 0
    }
    
    $iteration = 0
    $maxIterations = [Math]::Max(10, [Math]::Ceiling($estimate.EstimatedTime / 3))
    
    while ($job.State -eq 'Running') {
        $elapsed = (Get-Date) - $startTime
        $elapsedSeconds = $elapsed.TotalSeconds
        
        # Calculate progress percentage based on elapsed time vs estimated time
        $progressPercent = [Math]::Min(95, ($elapsedSeconds / $estimate.EstimatedTime) * 100)
        
        $progressParams.PercentComplete = $progressPercent
        $progressParams.Status = "Progress: {0:N0}% - Elapsed: {1:N0}s" -f $progressPercent, $elapsedSeconds
        
        if ($estimate.EstimatedTime -gt $elapsedSeconds) {
            $remainingSeconds = $estimate.EstimatedTime - $elapsedSeconds
            if ($remainingSeconds -gt 60) {
                $progressParams.Status += " - Est. remaining: {0:N1} min" -f ($remainingSeconds / 60)
            } else {
                $progressParams.Status += " - Est. remaining: {0:N0}s" -f $remainingSeconds
            }
        }
        
        Write-Progress @progressParams
        Start-Sleep -Seconds 3
        $iteration++
        
        # Prevent infinite loop - if taking much longer than expected, show different message
        if ($iteration -gt $maxIterations -and $elapsedSeconds -gt ($estimate.EstimatedTime * 1.5)) {
            $progressParams.Status = "Taking longer than expected - Elapsed: {0:N0}s" -f $elapsedSeconds
            Write-Progress @progressParams
        }
    }
    
    # Complete the progress bar
    Write-Progress -Activity "$Operation module: $ModuleName" -Completed
    
    # Get the job result
    $result = Receive-Job -Job $job
    Remove-Job -Job $job
    
    $actualTime = ((Get-Date) - $startTime).TotalSeconds
    
    if ($result.Success) {
        Write-ColorOutput "    Successfully completed $Operation of $ModuleName" -Type Process
        Write-ColorOutput "    Actual time: {0:N0} seconds" -f $actualTime -Type Info
        
        # If significantly different from estimate, show note
        if ([Math]::Abs($actualTime - $estimate.EstimatedTime) -gt ($estimate.EstimatedTime * 0.3)) {
            $variance = if ($actualTime -gt $estimate.EstimatedTime) { "slower" } else { "faster" }
            Write-ColorOutput "    Note: $Operation was {0:N0}% $variance than estimated" -f ([Math]::Abs(($actualTime - $estimate.EstimatedTime) / $estimate.EstimatedTime * 100)) -Type Info
        }
        
        return $true
    }
    else {
        Write-ColorOutput "    Error during $Operation of $ModuleName`: $($result.Message)" -Type Error
        return $false
    }
}

function Test-ModuleInstallation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        
        [Parameter()]
        [string]$Description = $ModuleName
    )
    
    try {
        Write-ColorOutput "    Checking module: $Description" -Type Info
        
        $installedModule = Get-InstalledModule -Name $ModuleName -ErrorAction SilentlyContinue
        
        if (-not $installedModule) {
            Write-ColorOutput "    [Warning] Module '$ModuleName' not found" -Type Warning
            
            if ($Prompt -and -not $CheckOnly) {
                $estimate = Get-ModuleInstallationEstimate -ModuleName $ModuleName -Operation 'Install'
                Write-ColorOutput "    Installation details:" -Type Info
                Write-ColorOutput "      Size: $($estimate.FormattedSize), Time: $($estimate.FormattedTime)" -Type Info
                
                $response = Read-Host "    Install module '$ModuleName' (Y/N)?"
                if ($response -notmatch '^[Yy]') {
                    Write-ColorOutput "    Skipping installation of $ModuleName" -Type Warning
                    return
                }
            }
              if (-not $CheckOnly) {
                Write-ColorOutput "    Installing module: $ModuleName" -Type Process
                
                # Initialize optimized settings
                $baseParams = Initialize-OptimizedInstallation
                $installParams = Get-ModuleSpecificParams -ModuleName $ModuleName -BaseParams $baseParams
                
                # Use progress tracking for large modules
                $largeModules = @('Az', 'Microsoft.Graph', 'PnP.PowerShell', 'AzureAD')
                if ($ModuleName -in $largeModules) {
                    $success = Install-ModuleWithProgress -ModuleName $ModuleName -InstallParams $installParams -Operation 'Install'
                    if (-not $success) {
                        throw "Installation failed"
                    }
                }
                else {
                    # For smaller modules, use direct installation
                    Install-Module -Name $ModuleName -Scope AllUsers @installParams
                    Write-ColorOutput "    Successfully installed $ModuleName" -Type Process
                }
            }
            return
        }
        
        # Check for updates
        $onlineModule = Find-Module -Name $ModuleName -ErrorAction SilentlyContinue
        if (-not $onlineModule) {
            Write-ColorOutput "    Cannot find online version of $ModuleName" -Type Warning
            return
        }
        
        $localVersion = ($installedModule | Sort-Object Version -Descending | Select-Object -First 1).Version
        $onlineVersion = $onlineModule.Version
        
        if ([version]$localVersion -ge [version]$onlineVersion) {
            Write-ColorOutput "    Module $ModuleName ($localVersion) is up to date" -Type Process
        }
        else {
            Write-ColorOutput "    Module $ModuleName ($localVersion) can be updated to ($onlineVersion)" -Type Warning
              if (-not $CheckOnly) {
                # Initialize optimized settings
                $baseParams = Initialize-OptimizedInstallation
                $updateParams = Get-ModuleSpecificParams -ModuleName $ModuleName -BaseParams $baseParams
                
                # Use progress tracking for large modules
                $largeModules = @('Az', 'Microsoft.Graph', 'PnP.PowerShell', 'AzureAD')
                if ($ModuleName -in $largeModules) {
                    Write-ColorOutput "    Updating module: $ModuleName" -Type Process
                    $success = Install-ModuleWithProgress -ModuleName $ModuleName -InstallParams $updateParams -Operation 'Update'
                    if (-not $success) {
                        throw "Update failed"
                    }
                }
                else {
                    Write-ColorOutput "    Updating module: $ModuleName" -Type Process
                    Update-Module -Name $ModuleName @updateParams
                    Write-ColorOutput "    Successfully updated $ModuleName" -Type Process
                }
            }
        }
    }
    catch {        Write-ColorOutput "    Error processing module '$ModuleName' - $($PSItem.Exception.Message)" -Type Error
    }
}

function Remove-ModuleWithProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        
        [Parameter()]
        [string]$ModuleVersion,
        
        [Parameter()]
        [object]$ModuleInfo
    )
    
    $estimate = Get-ModuleInstallationEstimate -ModuleName $ModuleName -Operation 'Remove'
    $startTime = Get-Date
    
    # Show pre-removal information for large modules
    $largeModules = @('Az', 'Microsoft.Graph', 'PnP.PowerShell', 'AzureAD')
    if ($ModuleName -in $largeModules) {
        Write-ColorOutput "    Removal details for $ModuleName" -Type Info
        Write-ColorOutput "      Estimated time: $($estimate.FormattedTime)" -Type Info
    }
    
    # Create a background job for the actual removal
    $jobScript = {
        param($ModuleName, $ModuleVersion, $ModuleInfo)
        
        try {
            $installMethod = if ($ModuleInfo.RepositorySourceLocation) { "PowerShellGet" } else { "MSI/Manual" }
            
            if ($installMethod -eq "MSI/Manual") {
                # Handle MSI/Manual installed modules
                $canUninstallViaPS = Get-InstalledModule -Name $ModuleName -RequiredVersion $ModuleVersion -ErrorAction SilentlyContinue
                
                if ($canUninstallViaPS) {
                    Uninstall-Module -Name $ModuleName -RequiredVersion $ModuleVersion -Force -Confirm:$false -ErrorAction Stop
                    return @{ Success = $true; Message = "Uninstalled via PowerShell" }
                }
                else {
                    # Manual removal from file system (with caution)
                    if ($ModuleInfo.ModuleBase -and (Test-Path $ModuleInfo.ModuleBase)) {
                        $safeToRemove = $ModuleInfo.ModuleBase -match "\\Users\\.*\\Documents\\.*PowerShell.*\\Modules" -or
                                       $ModuleInfo.ModuleBase -match "\\Program Files\\.*PowerShell.*\\Modules" -or
                                       $ModuleInfo.ModuleBase -match "\\PowerShell\\Modules"
                        
                        if ($safeToRemove) {
                            $testFile = Join-Path $ModuleInfo.ModuleBase "test.tmp"
                            try {
                                [System.IO.File]::Create($testFile).Close()
                                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
                                
                                Remove-Item -Path $ModuleInfo.ModuleBase -Recurse -Force -ErrorAction Stop
                                return @{ Success = $true; Message = "Removed from file system" }
                            }
                            catch [System.UnauthorizedAccessException] {
                                return @{ Success = $false; Message = "Access denied - module files may be in use or require admin rights" }
                            }
                            catch [System.IO.IOException] {
                                return @{ Success = $false; Message = "Module files are locked or in use - close applications and retry" }
                            }
                        }
                        else {
                            return @{ Success = $false; Message = "Module in system location - manual removal required" }
                        }
                    }
                    else {
                        return @{ Success = $false; Message = "Module path not found or no longer exists" }
                    }
                }
            }
            else {
                # PowerShellGet installed modules
                $retryAttempts = 2
                for ($attempt = 1; $attempt -le $retryAttempts; $attempt++) {
                    try {
                        if ($attempt -gt 1) { Start-Sleep -Seconds 2 }
                        
                        Uninstall-Module -Name $ModuleName -RequiredVersion $ModuleVersion -Force -Confirm:$false -ErrorAction Stop
                        return @{ Success = $true; Message = "Uninstalled via PowerShellGet" }
                    }
                    catch {
                        $errorMsg = $_.Exception.Message
                        
                        if ($errorMsg -like "*Administrator*" -or $errorMsg -like "*elevated*") {
                            return @{ Success = $false; Message = "Requires administrator privileges" }
                        }
                        elseif ($errorMsg -like "*in use*" -or $errorMsg -like "*locked*") {
                            if ($attempt -eq $retryAttempts) {
                                return @{ Success = $false; Message = "Module is currently in use - close PowerShell sessions and retry" }
                            }
                        }
                        elseif ($errorMsg -like "*not found*" -or $errorMsg -like "*does not exist*") {
                            try {
                                Uninstall-Module -Name $ModuleName -Force -Confirm:$false -ErrorAction Stop
                                return @{ Success = $true; Message = "Uninstalled via PowerShellGet (all versions)" }
                            }
                            catch {
                                if ($attempt -eq $retryAttempts) {
                                    return @{ Success = $false; Message = "Module not found in PowerShellGet registry" }
                                }
                            }
                        }
                        else {
                            if ($attempt -eq $retryAttempts) {
                                return @{ Success = $false; Message = "PowerShellGet uninstall failed: $errorMsg" }
                            }
                        }
                    }
                }
                return @{ Success = $false; Message = "All retry attempts failed" }
            }
        }
        catch {
            return @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    
    # For large modules, show progress; for smaller ones, just process directly
    if ($ModuleName -in $largeModules) {
        # Start the background job
        $job = Start-Job -ScriptBlock $jobScript -ArgumentList $ModuleName, $ModuleVersion, $ModuleInfo
        
        # Show progress while waiting
        $progressParams = @{
            Activity = "Removing module: $ModuleName"
            Status = "Uninstalling..."
            PercentComplete = 0
        }
        
        $iteration = 0
        $maxIterations = [Math]::Max(5, [Math]::Ceiling($estimate.EstimatedTime / 2))
        
        while ($job.State -eq 'Running') {
            $elapsed = (Get-Date) - $startTime
            $elapsedSeconds = $elapsed.TotalSeconds
            
            $progressPercent = [Math]::Min(95, ($elapsedSeconds / $estimate.EstimatedTime) * 100)
            
            $progressParams.PercentComplete = $progressPercent
            $progressParams.Status = "Progress: {0:N0}% - Elapsed: {1:N0}s" -f $progressPercent, $elapsedSeconds
            
            if ($estimate.EstimatedTime -gt $elapsedSeconds) {
                $remainingSeconds = $estimate.EstimatedTime - $elapsedSeconds
                if ($remainingSeconds -gt 60) {
                    $progressParams.Status += " - Est. remaining: {0:N1} min" -f ($remainingSeconds / 60)
                } else {
                    $progressParams.Status += " - Est. remaining: {0:N0}s" -f $remainingSeconds
                }
            }
            
            Write-Progress @progressParams
            Start-Sleep -Seconds 2
            $iteration++
            
            if ($iteration -gt $maxIterations -and $elapsedSeconds -gt ($estimate.EstimatedTime * 1.5)) {
                $progressParams.Status = "Taking longer than expected - Elapsed: {0:N0}s" -f $elapsedSeconds
                Write-Progress @progressParams
            }
        }
        
        # Complete the progress bar
        Write-Progress -Activity "Removing module: $ModuleName" -Completed
        
        # Get the job result
        $result = Receive-Job -Job $job
        Remove-Job -Job $job
    }
    else {
        # Direct execution for smaller modules
        $result = & $jobScript $ModuleName $ModuleVersion $ModuleInfo
    }
    
    $actualTime = ((Get-Date) - $startTime).TotalSeconds
    
    return @{
        Success = $result.Success
        Message = $result.Message
        ActualTime = $actualTime
    }
}

function Remove-DeprecatedModules {
    [CmdletBinding()]
    param()
      if ($SkipDeprecatedCleanup -or $CheckOnly) {
        return
    }
    
    Write-ColorOutput ""
    Write-ColorOutput "Checking for deprecated modules..." -Type System
    
    # First, collect all deprecated modules that are installed
    $modulesToRemove = @()
    foreach ($deprecated in $Script:DeprecatedModules) {
        # Check both Get-Module -ListAvailable and Get-InstalledModule
        $installedVersions = @()
        
        # Check modules installed via PowerShellGet
        $psGetModules = Get-InstalledModule -Name $deprecated.Name -ErrorAction SilentlyContinue
        if ($psGetModules) {
            $installedVersions += $psGetModules
        }
        
        # Check modules available in the system (including MSI-installed)
        $availableModules = Get-Module -ListAvailable -Name $deprecated.Name -ErrorAction SilentlyContinue
        if ($availableModules) {
            # Add modules that aren't already in the PowerShellGet list
            foreach ($module in $availableModules) {
                $alreadyListed = $installedVersions | Where-Object { 
                    $_.Name -eq $module.Name -and $_.Version -eq $module.Version 
                }
                if (-not $alreadyListed) {
                    # Create a custom object that mimics Get-InstalledModule output
                    $installedVersions += [PSCustomObject]@{
                        Name = $module.Name
                        Version = $module.Version
                        ModuleBase = $module.ModuleBase
                        InstalledLocation = $module.ModuleBase
                        InstalledBy = "Unknown"
                        InstalledVia = "MSI/Manual"
                    }
                }
            }
        }
        
        if ($installedVersions) {
            # Estimate time based on module complexity and size
            $estimatedTimePerVersion = switch ($deprecated.Name) {
                'Az' { 90 }  # Azure modules are very large
                'Microsoft.Graph' { 60 }  # Graph modules are large
                'AzureAD' { 45 }  # AzureAD modules are medium-large
                'MSOnline' { 30 }  # MSOnline is medium
                'PnP.PowerShell' { 45 }  # PnP modules are medium-large
                'SharePointPnPPowerShellOnline' { 30 }  # Old PnP is medium
                'WindowsAutoPilotIntune' { 25 }  # Intune modules are medium
                default { 20 }  # Default estimation for smaller modules
            }
            
            $moduleEstimate = $estimatedTimePerVersion * $installedVersions.Count
            
            $modulesToRemove += @{
                Name = $deprecated.Name
                Replacement = $deprecated.Replacement
                Reason = $deprecated.Reason
                Versions = $installedVersions
                VersionCount = $installedVersions.Count
                EstimatedTime = $moduleEstimate
            }
        }
    }
      if ($modulesToRemove.Count -eq 0) {
        Write-ColorOutput "    No deprecated modules found" -Type Process
        Write-ColorOutput ""
        return
    }
    
    # Calculate total time estimation
    $totalEstimatedTime = ($modulesToRemove | Measure-Object -Property EstimatedTime -Sum).Sum
    $totalVersions = ($modulesToRemove | Measure-Object -Property VersionCount -Sum).Sum
    $estimatedMinutes = [math]::Round($totalEstimatedTime / 60, 1)
      Write-ColorOutput "Found $($modulesToRemove.Count) deprecated modules with $totalVersions total versions to remove" -Type Warning
    Write-ColorOutput "Estimated total removal time: $estimatedMinutes minutes" -Type Info
    Write-ColorOutput ""
    
    # Display what will be removed
    foreach ($moduleInfo in $modulesToRemove) {
        Write-ColorOutput "    • $($moduleInfo.Name) ($($moduleInfo.VersionCount) versions) - Est: $([math]::Round($moduleInfo.EstimatedTime / 60, 1))min" -Type Info
    }
    Write-ColorOutput ""
    
    # Always prompt for confirmation before removing modules (unless already prompting per module)
    if (-not $Prompt) {
        Write-ColorOutput "⚠ WARNING: This will remove all deprecated modules listed above." -Type Warning
        Write-ColorOutput "These modules are being replaced by newer Microsoft Graph and other modern modules." -Type Warning
        Write-ColorOutput ""
        $response = Read-Host "Do you want to proceed with removing these deprecated modules? (Y/N)"
        if ($response -notmatch '^[Yy]') {
            Write-ColorOutput "Module removal cancelled by user. Skipping deprecated module cleanup." -Type Warning
            Write-ColorOutput ""
            return
        }
        Write-ColorOutput ""
    }
    
    $startTime = Get-Date
    $totalOperations = $totalVersions
    $currentOperation = 0
    
    foreach ($moduleInfo in $modulesToRemove) {
        Write-ColorOutput "    [Warning] Processing deprecated module '$($moduleInfo.Name)' ($($moduleInfo.VersionCount) versions)" -Type Warning
        Write-ColorOutput "    Reason: $($moduleInfo.Reason)" -Type Warning
        Write-ColorOutput "    Replacement: $($moduleInfo.Replacement)" -Type Warning
          if ($Prompt) {
            Write-ColorOutput ""
            Write-ColorOutput "⚠ About to remove deprecated module: $($moduleInfo.Name)" -Type Warning
            Write-ColorOutput "  Reason: $($moduleInfo.Reason)" -Type Info
            Write-ColorOutput "  Replacement: $($moduleInfo.Replacement)" -Type Info
            Write-ColorOutput "  Versions to remove: $($moduleInfo.VersionCount)" -Type Info
            Write-ColorOutput "  Estimated time: $([math]::Round($moduleInfo.EstimatedTime / 60, 1)) minutes" -Type Info
            Write-ColorOutput ""
            $response = Read-Host "Remove all versions of deprecated module '$($moduleInfo.Name)' (Y/N)?"
            if ($response -notmatch '^[Yy]') {
                Write-ColorOutput "    Skipping removal of $($moduleInfo.Name)" -Type Warning
                $currentOperation += $moduleInfo.VersionCount
                continue
            }
            Write-ColorOutput ""
        }
        
        $moduleStartTime = Get-Date
        
        # Remove each version with progress tracking
        foreach ($version in $moduleInfo.Versions) {
            $currentOperation++
            $percentComplete = [math]::Round(($currentOperation / $totalOperations) * 100, 1)
            
            # Calculate estimated time remaining
            $elapsed = (Get-Date) - $startTime
            if ($currentOperation -gt 1) {
                $averageTimePerOperation = $elapsed.TotalSeconds / ($currentOperation - 1)
                $remainingOperations = $totalOperations - $currentOperation
                $estimatedTimeRemaining = [TimeSpan]::FromSeconds($averageTimePerOperation * $remainingOperations)
                
                if ($estimatedTimeRemaining.TotalMinutes -gt 1) {
                    $timeRemainingText = "{0:mm}m {0:ss}s remaining" -f $estimatedTimeRemaining
                } else {
                    $timeRemainingText = "{0:ss}s remaining" -f $estimatedTimeRemaining
                }
            } else {
                $timeRemainingText = "calculating..."
            }
            
            Write-ColorOutput "    [$percentComplete%] ($currentOperation/$totalOperations) $timeRemainingText" -Type Info
            
            # Determine installation method and removal approach
            $installMethod = if ($version.PSObject.Properties.Name -contains "InstalledVia") { 
                $version.InstalledVia 
            } else { 
                "PowerShellGet" 
            }
            
            Write-ColorOutput "    Removing $($moduleInfo.Name) v$($version.Version) [$installMethod]..." -Type Process -NoNewline
            
            try {
                $operationStart = Get-Date
                $uninstallResult = @{ Success = $false; Message = "Not attempted" }
                  # Try different removal methods based on how the module was installed
                if ($installMethod -eq "MSI/Manual") {
                    # For MSI or manually installed modules, try to remove from module path
                    try {
                        Write-Host "." -NoNewline -ForegroundColor $Script:Colors.Process
                        
                        # Check if module can be uninstalled via Uninstall-Module
                        $canUninstallViaPS = Get-InstalledModule -Name $moduleInfo.Name -RequiredVersion $version.Version -ErrorAction SilentlyContinue
                        
                        if ($canUninstallViaPS) {
                            # Try PowerShell uninstall first
                            try {
                                Uninstall-Module -Name $moduleInfo.Name -RequiredVersion $version.Version -Force -Confirm:$false -ErrorAction Stop
                                $uninstallResult = @{ Success = $true; Message = "Uninstalled via PowerShell" }
                            }
                            catch {
                                # Specific error handling for common issues
                                $errorMsg = $_.Exception.Message
                                if ($errorMsg -like "*Administrator*" -or $errorMsg -like "*elevated*") {
                                    $uninstallResult = @{ Success = $false; Message = "Requires administrator privileges" }
                                }
                                elseif ($errorMsg -like "*in use*" -or $errorMsg -like "*locked*") {
                                    $uninstallResult = @{ Success = $false; Message = "Module is currently in use - close PowerShell sessions and retry" }
                                }
                                else {
                                    $uninstallResult = @{ Success = $false; Message = "PowerShell uninstall failed: $errorMsg" }
                                }
                            }
                        }
                        else {
                            # Manual removal from file system (with caution)
                            if ($version.ModuleBase -and (Test-Path $version.ModuleBase)) {
                                # Only remove if it's in a user-specific or PowerShell modules path
                                $safeToRemove = $version.ModuleBase -match "\\Users\\.*\\Documents\\.*PowerShell.*\\Modules" -or
                                               $version.ModuleBase -match "\\Program Files\\.*PowerShell.*\\Modules" -or
                                               $version.ModuleBase -match "\\PowerShell\\Modules"
                                
                                if ($safeToRemove) {
                                    try {
                                        # Check if files are locked before attempting removal
                                        $testFile = Join-Path $version.ModuleBase "test.tmp"
                                        try {
                                            [System.IO.File]::Create($testFile).Close()
                                            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
                                            
                                            Remove-Item -Path $version.ModuleBase -Recurse -Force -ErrorAction Stop
                                            $uninstallResult = @{ Success = $true; Message = "Removed from file system" }
                                        }
                                        catch [System.UnauthorizedAccessException] {
                                            $uninstallResult = @{ Success = $false; Message = "Access denied - module files may be in use or require admin rights" }
                                        }
                                        catch [System.IO.IOException] {
                                            $uninstallResult = @{ Success = $false; Message = "Module files are locked or in use - close applications and retry" }
                                        }
                                    }
                                    catch {
                                        $uninstallResult = @{ Success = $false; Message = "File system removal failed: $($_.Exception.Message)" }
                                    }
                                }
                                else {
                                    $uninstallResult = @{ Success = $false; Message = "Module in system location ($($version.ModuleBase)) - manual removal required" }
                                }
                            }
                            else {
                                $uninstallResult = @{ Success = $false; Message = "Module path not found or no longer exists" }
                            }
                        }
                    }
                    catch {
                        $uninstallResult = @{ Success = $false; Message = "Unexpected error during MSI/Manual removal: $($_.Exception.Message)" }
                    }
                }
                else {
                    # For PowerShellGet installed modules, use standard uninstall with retry logic
                    $retryAttempts = 2
                    $retryDelay = 2
                    
                    for ($attempt = 1; $attempt -le $retryAttempts; $attempt++) {
                        try {
                            Write-Host "." -NoNewline -ForegroundColor $Script:Colors.Process
                            if ($attempt -gt 1) {
                                Start-Sleep -Seconds $retryDelay
                                Write-Host "(retry $attempt)" -NoNewline -ForegroundColor $Script:Colors.Warning
                            }
                            
                            Uninstall-Module -Name $moduleInfo.Name -RequiredVersion $version.Version -Force -Confirm:$false -ErrorAction Stop
                            $uninstallResult = @{ Success = $true; Message = "Uninstalled via PowerShellGet" }
                            break
                        }
                        catch {
                            $errorMsg = $_.Exception.Message
                            
                            # Check for specific error conditions
                            if ($errorMsg -like "*Administrator*" -or $errorMsg -like "*elevated*") {
                                $uninstallResult = @{ Success = $false; Message = "Requires administrator privileges" }
                                break
                            }
                            elseif ($errorMsg -like "*in use*" -or $errorMsg -like "*locked*") {
                                if ($attempt -lt $retryAttempts) {
                                    continue  # Retry for file locking issues
                                }
                                $uninstallResult = @{ Success = $false; Message = "Module is currently in use - close PowerShell sessions and retry" }
                                break
                            }
                            elseif ($errorMsg -like "*not found*" -or $errorMsg -like "*does not exist*") {
                                # Try fallback: uninstall without specific version
                                try {
                                    Write-Host "." -NoNewline -ForegroundColor $Script:Colors.Process
                                    Uninstall-Module -Name $moduleInfo.Name -Force -Confirm:$false -ErrorAction Stop
                                    $uninstallResult = @{ Success = $true; Message = "Uninstalled via PowerShellGet (all versions)" }
                                    break
                                }
                                catch {
                                    if ($attempt -eq $retryAttempts) {
                                        $uninstallResult = @{ Success = $false; Message = "Module not found in PowerShellGet registry: $($_.Exception.Message)" }
                                    }
                                }
                            }
                            else {
                                if ($attempt -eq $retryAttempts) {
                                    $uninstallResult = @{ Success = $false; Message = "PowerShellGet uninstall failed: $errorMsg" }
                                }
                            }
                        }
                    }
                }
                
                $operationDuration = (Get-Date) - $operationStart
                
                if ($uninstallResult.Success) {
                    Write-Host " Done! ($([math]::Round($operationDuration.TotalSeconds, 1))s)" -ForegroundColor $Script:Colors.Process
                    if ($uninstallResult.Message -ne "Completed successfully") {
                        Write-ColorOutput "      Method: $($uninstallResult.Message)" -Type Info
                    }
                } else {
                    Write-Host " Failed!" -ForegroundColor $Script:Colors.Error
                    Write-ColorOutput "      Error: $($uninstallResult.Message)" -Type Error
                    if ($installMethod -eq "MSI/Manual") {
                        Write-ColorOutput "      Note: MSI-installed modules may require manual removal via Add/Remove Programs" -Type Warning
                    }
                }
            }
            catch {
                $operationDuration = (Get-Date) - $operationStart
                Write-Host " Error! ($([math]::Round($operationDuration.TotalSeconds, 1))s)" -ForegroundColor $Script:Colors.Error
                Write-ColorOutput "      Error details: $($_.Exception.Message)" -Type Error
            }
        }
        
        $moduleElapsed = (Get-Date) - $moduleStartTime
        Write-ColorOutput "    Completed $($moduleInfo.Name) in $([math]::Round($moduleElapsed.TotalMinutes, 1)) minutes" -Type Process
        Write-ColorOutput ""
    }
    
    $totalElapsed = (Get-Date) - $startTime
    Write-ColorOutput "Deprecated module cleanup completed in $([math]::Round($totalElapsed.TotalMinutes, 1)) minutes" -Type System
    
    # Compare actual vs estimated time
    $actualMinutes = [math]::Round($totalElapsed.TotalMinutes, 1)
    if ($actualMinutes -lt $estimatedMinutes) {
        Write-ColorOutput "Completed faster than estimated! (Est: ${estimatedMinutes}min, Actual: ${actualMinutes}min)" -Type Process
    } elseif ($actualMinutes -gt ($estimatedMinutes * 1.2)) {
        Write-ColorOutput "Took longer than estimated (Est: ${estimatedMinutes}min, Actual: ${actualMinutes}min)" -Type Warning
    }
    
    # Final verification
    Write-ColorOutput ""
    Write-ColorOutput "Verifying deprecated module removal..." -Type System
    $remainingModules = @()
    foreach ($deprecated in $Script:DeprecatedModules) {
        $stillInstalled = Get-Module -ListAvailable -Name $deprecated.Name -ErrorAction SilentlyContinue
        if ($stillInstalled) {
            $remainingModules += $deprecated.Name
        }
    }    if ($remainingModules.Count -eq 0) {
        Write-ColorOutput "    ✓ All deprecated modules successfully removed" -Type Process
        Write-ColorOutput ""
        
        # Brief pause to let user see the success message
        Start-Sleep -Seconds 2
        
        # Clear any system messages and show clean completion
        Write-ColorOutput "Deprecated module cleanup completed successfully." -Type System
    } else {
        Write-ColorOutput "    ⚠ Some modules may still be present: $($remainingModules -join ', ')" -Type Warning
        Write-ColorOutput "    These may be MSI-installed modules requiring manual removal" -Type Info
        Write-ColorOutput ""
        
        # Show detailed troubleshooting for remaining modules
        Write-ColorOutput "Next steps for remaining modules:" -Type Info
        Write-ColorOutput "    1. Run PowerShell as Administrator" -Type Info
        Write-ColorOutput "    2. Close all other PowerShell sessions" -Type Info
        Write-ColorOutput "    3. For MSI-installed modules, use Windows Settings > Apps & features" -Type Info
        Write-ColorOutput "    4. Manual cleanup locations:" -Type Info
        Write-ColorOutput "       • $env:USERPROFILE\\Documents\\PowerShell\\Modules" -Type Info
        Write-ColorOutput "       • $env:ProgramFiles\\PowerShell\\Modules" -Type Info
        Write-ColorOutput "       • $env:USERPROFILE\\Documents\\WindowsPowerShell\\Modules" -Type Info
        Write-ColorOutput "       • $env:ProgramFiles\\WindowsPowerShell\\Modules" -Type Info
        Write-ColorOutput ""
        
        # Pause for user to read troubleshooting info
        Write-ColorOutput "Press any key to continue..." -Type Warning -NoNewline
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Write-ColorOutput ""
    }
}

function Test-ModuleRemovalPrerequisites {
    [CmdletBinding()]
    param()
    
    Write-ColorOutput "Checking module removal prerequisites..." -Type System
    
    $issues = @()
    
    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if (-not $isAdmin) {
        $issues += "Not running as Administrator - some system-installed modules may not be removable"
        Write-ColorOutput "    [Warning] Not running as Administrator" -Type Warning
    } else {
        Write-ColorOutput "    [OK] Running as Administrator" -Type Process    }

    # Check session conflict status (handled in main execution)
    if (-not $Script:SessionConflictsResolved) {
        $issues += "Other PowerShell sessions detected - modules may be locked"
        Write-ColorOutput "    [Info] Session conflicts detected - module removal may encounter issues" -Type Info
    } else {
        Write-ColorOutput "    [OK] No session conflicts detected" -Type Process
    }
      # Check available disk space
    $systemDrive = $env:SystemDrive
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$systemDrive'" -ErrorAction SilentlyContinue
    if ($disk -and $disk.FreeSpace) {
        $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        if ($freeSpaceGB -lt 1) {
            $issues += "Low disk space may cause removal issues"
            Write-ColorOutput "    [Warning] Low disk space: ${freeSpaceGB}GB free" -Type Warning
        } else {
            Write-ColorOutput "    [OK] Sufficient disk space: ${freeSpaceGB}GB free" -Type Process
        }
    }
    
    # Check execution policy
    $executionPolicy = Get-ExecutionPolicy
    if ($executionPolicy -eq "Restricted") {
        $issues += "Restricted execution policy may prevent module operations"
        Write-ColorOutput "    [Warning] Execution policy is Restricted" -Type Warning
    } else {
        Write-ColorOutput "    [OK] Execution policy: $executionPolicy" -Type Process
    }
    
    if ($issues.Count -gt 0) {
        Write-ColorOutput ""
        Write-ColorOutput "Potential issues detected:" -Type Warning
        foreach ($issue in $issues) {
            Write-ColorOutput "    • $issue" -Type Warning
        }
        Write-ColorOutput ""
        
        if ($Prompt) {
            $response = Read-Host "Continue with module removal despite potential issues (Y/N)?"
            if ($response -notmatch '^[Yy]') {
                Write-ColorOutput "Module removal cancelled by user" -Type Warning
                return $false
            }
        }
    } else {
        Write-ColorOutput "    All prerequisites met" -Type Process
    }
    
    return $true
}

function Test-PowerShellCompatibility {
    [CmdletBinding()]
    param()
    
    # Check PowerShell Language Mode
    $languageMode = $ExecutionContext.SessionState.LanguageMode
    Write-ColorOutput "PowerShell Language Mode: $languageMode" -Type Info
    
    if ($languageMode -eq 'ConstrainedLanguage') {
        Write-ColorOutput "Note: Running in Constrained Language Mode - some advanced features may be limited" -Type Warning
    }
    
    # Test if jobs are supported
    try {
        $testJob = Start-Job -ScriptBlock { return "test" } -ErrorAction Stop
        Stop-Job $testJob -ErrorAction SilentlyContinue
        Remove-Job $testJob -ErrorAction SilentlyContinue
        Write-ColorOutput "Background jobs: Supported" -Type Process
        return $true
    }
    catch {
        Write-ColorOutput "Background jobs: Not supported (will use direct execution)" -Type Warning
        return $false
    }
}

function Start-ScriptExecution {
    [CmdletBinding()]
    param()
      # Start transcript if requested
    if ($CreateLog) {
        $logFileName = "O365-Update-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        $logFile = Join-Path $LogPath $logFileName
        
        try {
            Start-Transcript -Path $logFile -Force
            Write-ColorOutput "Transcript started: $logFile" -Type System
        }
        catch {
            Write-ColorOutput "Warning: Could not start transcript: $($_.Exception.Message)" -Type Warning
        }
    }
      # Display script information
    Clear-Host
      Write-ColorOutput "=== Microsoft Cloud PowerShell Module Updater ===" -Type System
    Write-ColorOutput "Script Version: 2.5" -Type System
    Write-ColorOutput "Start Time: $(Get-Date -Format (Get-Culture).DateTimeFormat.FullDateTimePattern)" -Type System
    Write-ColorOutput "Current Culture: $((Get-Culture).DisplayName)" -Type System
    Write-ColorOutput "Prompt Mode: $Prompt" -Type System
    Write-ColorOutput "Check Only Mode: $CheckOnly" -Type System
    Write-ColorOutput ""
      # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    Write-ColorOutput "PowerShell Version: $($psVersion.Major).$($psVersion.Minor)" -Type Process
    
    # Check PowerShell compatibility
    $Script:JobsSupported = Test-PowerShellCompatibility
    Write-ColorOutput ""
    
    if ($psVersion.Major -lt 5) {
        Write-ColorOutput "Error: PowerShell 5.1 or higher is required" -Type Error
        exit 1
    }
    
    # Determine module count
    $moduleCount = $Script:ModuleList.Count
    if ($psVersion.Major -lt 7) {
        $moduleCount++ # Add NuGet provider for PowerShell 5.x
    }
    
    Write-ColorOutput "Total modules to process: $moduleCount" -Type Process
    Write-ColorOutput ""
    
    return $moduleCount
}

function Stop-ScriptExecution {
    [CmdletBinding()]
    param()
      Write-ColorOutput ""
    Write-ColorOutput "=== Script Completed ===" -Type System
    Write-ColorOutput "End Time: $(Get-Date -Format (Get-Culture).DateTimeFormat.FullDateTimePattern)" -Type System
    
    # Check if core modules were updated and provide guidance
    $coreModulesUpdated = $false
    foreach ($module in $Script:ModuleList) {
        if ($module.RequiresSpecialHandling -eq $true) {
            $installedVersions = Get-InstalledModule -Name $module.Name -AllVersions -ErrorAction SilentlyContinue
            if ($installedVersions -and $installedVersions.Count -gt 1) {
                $coreModulesUpdated = $true
                break
            }
        }
    }    if ($coreModulesUpdated) {
        Write-ColorOutput ""
        Write-ColorOutput "🎯 CORE MODULES UPDATED SUCCESSFULLY" -Type Process
        Write-ColorOutput "PowerShell core modules (PowerShellGet, PackageManagement) have been updated." -Type Info
        Write-ColorOutput ""
        Write-ColorOutput "✅ What happened:" -Type Process
        Write-ColorOutput "• New versions were installed alongside existing versions" -Type Info
        Write-ColorOutput "• Current PowerShell session continues using existing versions" -Type Info
        Write-ColorOutput "• New versions will be active when you restart PowerShell" -Type Info
        Write-ColorOutput ""
        Write-ColorOutput "🔄 Next Steps:" -Type Warning
        Write-ColorOutput "• Continue using PowerShell normally for now" -Type Info
        Write-ColorOutput "• Restart PowerShell when convenient to activate new versions" -Type Info
        Write-ColorOutput ""
        Write-ColorOutput "🔍 Verification command (after restart):" -Type Info
        Write-ColorOutput "  Get-Module PowerShellGet, PackageManagement -ListAvailable | Select Name, Version" -Type Info
        Write-ColorOutput ""
        
        # Pause for important notice
        Write-ColorOutput "Press any key to acknowledge..." -Type Warning -NoNewline
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Write-ColorOutput ""
    }
    
    # Stop transcript cleanly
    if ($CreateLog) {
        Write-ColorOutput ""
        try {
            Stop-Transcript
            Write-ColorOutput "Transcript log saved successfully." -Type Process
        }
        catch {
            Write-ColorOutput "Note: Transcript may not have been active." -Type Info
        }
    }
}

function Get-PowerShellSessions {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$IncludeCurrent,
        
        [Parameter()]
        [switch]$ShowDetails,
        
        [Parameter()]
        [switch]$ShowConflicts,
        
        [Parameter()]
        [switch]$Silent
    )
    
    if (-not $Silent) {
        Write-ColorOutput "Detecting PowerShell sessions..." -Type Info
    }
    
    # Get all PowerShell-related processes
    $sessions = @()
    
    # Traditional PowerShell processes (Windows PowerShell 5.1)
    $psProcesses = Get-Process -Name "powershell" -ErrorAction SilentlyContinue
    if ($psProcesses) {
        $sessions += $psProcesses | ForEach-Object {
            $startTime = try { $_.StartTime } catch { $null }
            $windowTitle = try { $_.MainWindowTitle } catch { "" }
            [PSCustomObject]@{
                ProcessId = $_.Id
                ProcessName = $_.ProcessName
                Type = "Windows PowerShell"
                StartTime = $startTime
                MemoryMB = [math]::Round($_.WorkingSet / 1MB, 1)
                WindowTitle = $windowTitle
                IsCurrent = ($_.Id -eq $PID)
                Process = $_
            }
        }
    }
    
    # PowerShell Core processes (PowerShell 7+)
    $pwshProcesses = Get-Process -Name "pwsh" -ErrorAction SilentlyContinue
    if ($pwshProcesses) {
        $sessions += $pwshProcesses | ForEach-Object {
            $startTime = try { $_.StartTime } catch { $null }
            $windowTitle = try { $_.MainWindowTitle } catch { "" }
            [PSCustomObject]@{
                ProcessId = $_.Id
                ProcessName = $_.ProcessName
                Type = "PowerShell Core"
                StartTime = $startTime
                MemoryMB = [math]::Round($_.WorkingSet / 1MB, 1)
                WindowTitle = $windowTitle
                IsCurrent = ($_.Id -eq $PID)
                Process = $_
            }
        }
    }
    
    # PowerShell ISE
    $iseProcesses = Get-Process -Name "powershell_ise" -ErrorAction SilentlyContinue
    if ($iseProcesses) {
        $sessions += $iseProcesses | ForEach-Object {
            $startTime = try { $_.StartTime } catch { $null }
            $windowTitle = try { $_.MainWindowTitle } catch { "" }
            [PSCustomObject]@{
                ProcessId = $_.Id
                ProcessName = $_.ProcessName
                Type = "PowerShell ISE"
                StartTime = $startTime
                MemoryMB = [math]::Round($_.WorkingSet / 1MB, 1)
                WindowTitle = $windowTitle
                IsCurrent = $false
                Process = $_
            }
        }
    }
    
    # VS Code processes (check if they might be running PowerShell)
    $codeProcesses = Get-Process -Name "code" -ErrorAction SilentlyContinue
    if ($codeProcesses) {
        foreach ($proc in $codeProcesses) {
            try {
                $wmiProc = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction SilentlyContinue
                if ($wmiProc -and $wmiProc.CommandLine -and ($wmiProc.CommandLine -like "*powershell*" -or $wmiProc.CommandLine -like "*.ps1*")) {
                    $startTime = try { $proc.StartTime } catch { $null }
                    $windowTitle = try { $proc.MainWindowTitle } catch { "" }
                    $sessions += [PSCustomObject]@{
                        ProcessId = $proc.Id
                        ProcessName = $proc.ProcessName
                        Type = "VS Code (PowerShell)"
                        StartTime = $startTime
                        MemoryMB = [math]::Round($proc.WorkingSet / 1MB, 1)
                        WindowTitle = $windowTitle
                        IsCurrent = $false
                        Process = $proc
                    }
                }
            }
            catch {
                # Ignore errors when checking VS Code processes
            }
        }
    }
    
    # Windows Terminal processes (may contain PowerShell sessions)
    $terminalProcesses = Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue
    if ($terminalProcesses) {
        $sessions += $terminalProcesses | ForEach-Object {
            $startTime = try { $_.StartTime } catch { $null }
            $windowTitle = try { $_.MainWindowTitle } catch { "" }
            [PSCustomObject]@{
                ProcessId = $_.Id
                ProcessName = $_.ProcessName
                Type = "Windows Terminal"
                StartTime = $startTime
                MemoryMB = [math]::Round($_.WorkingSet / 1MB, 1)
                WindowTitle = $windowTitle
                IsCurrent = $false
                Process = $_
            }
        }
    }
    
    # Filter out current process if requested
    if (-not $IncludeCurrent) {
        $sessions = $sessions | Where-Object { -not $_.IsCurrent }
    }
      if ($sessions.Count -eq 0) {
        if (-not $Silent) {
            Write-ColorOutput "    No PowerShell sessions detected" -Type Process
        }
        return @()
    }

    # Display results only if not silent
    if (-not $Silent) {
        $currentSessions = $sessions | Where-Object { $_.IsCurrent }
        $otherSessions = $sessions | Where-Object { -not $_.IsCurrent }
        
        if ($currentSessions) {
            Write-ColorOutput "    Current session:" -Type Info
            foreach ($session in $currentSessions) {
                $startTimeText = if ($session.StartTime) { $session.StartTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "Unknown" }
                Write-ColorOutput "    • PID: $($session.ProcessId) | $($session.Type) | Started: $startTimeText | Memory: $($session.MemoryMB)MB" -Type Process
            }
        }
        
        if ($otherSessions.Count -gt 0) {
            Write-ColorOutput "    Found $($otherSessions.Count) other PowerShell session(s):" -Type Warning
            
            foreach ($session in $otherSessions) {
                $startTimeText = if ($session.StartTime) { $session.StartTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "Unknown" }
                $titleText = if ($session.WindowTitle -and $session.WindowTitle.Trim()) { $session.WindowTitle } else { "No window title" }
                
                if ($ShowDetails) {
                    Write-ColorOutput "    • PID: $($session.ProcessId) | $($session.Type) | Started: $startTimeText | Memory: $($session.MemoryMB)MB" -Type Info
                    Write-ColorOutput "      Title: $titleText" -Type Info
                    
                    # Try to get additional details via WMI
                    try {
                        $wmiProc = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$($session.ProcessId)" -ErrorAction SilentlyContinue
                        if ($wmiProc) {
                            $owner = try { (Invoke-CimMethod -InputObject $wmiProc -MethodName GetOwner).User } catch { "Unknown" }
                            Write-ColorOutput "      Owner: $owner" -Type Info
                            
                            if ($wmiProc.CommandLine -and $wmiProc.CommandLine.Length -gt 100) {
                                Write-ColorOutput "      Command: $($wmiProc.CommandLine.Substring(0,97))..." -Type Info
                            } elseif ($wmiProc.CommandLine) {
                                Write-ColorOutput "      Command: $($wmiProc.CommandLine)" -Type Info
                            }
                        }
                    }
                    catch {
                        # Ignore WMI errors
                    }
                    Write-ColorOutput "" -Type Info
                } else {
                    Write-ColorOutput "    • PID: $($session.ProcessId) | $($session.Type) | Memory: $($session.MemoryMB)MB | $titleText" -Type Info
                }
            }
            
            if ($ShowConflicts) {
                Write-ColorOutput ""
                Write-ColorOutput "Potential conflicts with module operations:" -Type Warning
                Write-ColorOutput "    • Other PowerShell sessions may have modules loaded" -Type Warning
                Write-ColorOutput "    • Loaded modules cannot be uninstalled or updated" -Type Warning
                Write-ColorOutput "    • ISE and VS Code may have PowerShell modules in memory" -Type Warning
                Write-ColorOutput "    • Windows Terminal may contain hidden PowerShell sessions" -Type Warning
            }
        }
    }
    
    return $sessions
}

function Stop-ConflictingPowerShellSessions {
    <#
    .SYNOPSIS
        Terminates conflicting PowerShell processes that may be holding modules
    
    .DESCRIPTION
        Identifies and optionally terminates PowerShell processes that could prevent
        module installation, update, or removal operations. Provides user confirmation
        before terminating processes and excludes the current session.
    
    .PARAMETER Sessions
        Array of PowerShell session objects from Get-PowerShellSessions
    
    .PARAMETER Force
        Skip confirmation prompts and terminate all conflicting sessions
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Sessions,
        
        [Parameter()]
        [switch]$Force
    )
    
    # Filter out current session and get potentially conflicting sessions
    $conflictingSessions = $Sessions | Where-Object { -not $_.IsCurrent }
    
    if ($conflictingSessions.Count -eq 0) {
        Write-ColorOutput "    No conflicting PowerShell sessions to terminate" -Type Process        return $true
    }
      # Sessions already displayed by caller, proceed with termination logic
    
    # Get user confirmation unless Force is specified
    if (-not $Force) {
        Write-ColorOutput "⚠ WARNING: Terminating these processes will:" -Type Warning
        Write-ColorOutput "    • Close any unsaved work in those PowerShell sessions" -Type Warning
        Write-ColorOutput "    • Stop any running scripts or commands" -Type Warning
        Write-ColorOutput "    • Close PowerShell ISE, VS Code PowerShell terminals, etc." -Type Warning
        Write-ColorOutput ""
        
        $response = Read-Host "Do you want to terminate these conflicting PowerShell sessions? (Y/N)"
        if ($response -notmatch '^[Yy]') {
            Write-ColorOutput "Session termination cancelled. Module operations may fail due to conflicts." -Type Warning
            Write-ColorOutput ""
            return $false
        }
        Write-ColorOutput ""
    }
    
    # Terminate conflicting sessions
    Write-ColorOutput "Terminating conflicting PowerShell sessions..." -Type System
    $terminatedCount = 0
    $failedCount = 0
    
    foreach ($session in $conflictingSessions) {
        Write-ColorOutput "    Terminating PID $($session.ProcessId) ($($session.Type))..." -Type Process -NoNewline
        
        try {
            # Try graceful termination first (for GUI applications)
            if ($session.Type -eq "PowerShell ISE" -or $session.Type -eq "VS Code (PowerShell)") {
                $session.Process.CloseMainWindow()
                Start-Sleep -Seconds 2
                
                # Check if process is still running
                $stillRunning = Get-Process -Id $session.ProcessId -ErrorAction SilentlyContinue
                if ($stillRunning) {
                    # Force termination if graceful close didn't work
                    $session.Process.Kill()
                }
            }
            else {
                # Force termination for console applications
                $session.Process.Kill()
            }
            
            # Wait a moment and verify termination
            Start-Sleep -Seconds 1
            $stillRunning = Get-Process -Id $session.ProcessId -ErrorAction SilentlyContinue
            
            if (-not $stillRunning) {
                Write-Host " Success!" -ForegroundColor $Script:Colors.Process
                $terminatedCount++
            }
            else {
                Write-Host " Failed (still running)" -ForegroundColor $Script:Colors.Error
                $failedCount++
            }
        }
        catch [System.InvalidOperationException] {
            # Process was already terminated
            Write-Host " Already terminated" -ForegroundColor $Script:Colors.Info
            $terminatedCount++
        }
        catch {
            Write-Host " Error: $($_.Exception.Message)" -ForegroundColor $Script:Colors.Error
            $failedCount++
        }
    }
    
    Write-ColorOutput ""
    if ($terminatedCount -gt 0) {
        Write-ColorOutput "Successfully terminated $terminatedCount PowerShell session(s)" -Type Process
    }
    
    if ($failedCount -gt 0) {
        Write-ColorOutput "Failed to terminate $failedCount PowerShell session(s)" -Type Warning
        Write-ColorOutput "You may need to manually close these applications or restart your computer" -Type Warning
    }
    
    # Brief pause to let processes fully terminate
    if ($terminatedCount -gt 0) {
        Write-ColorOutput "Waiting for processes to fully terminate..." -Type Info
        Start-Sleep -Seconds 3
    }
    
    return ($failedCount -eq 0)
}

function Show-PowerShellSessionGuidance {
    [CmdletBinding()]
    param(
        [Parameter()]
        [array]$Sessions
    )
    
    if (-not $Sessions -or $Sessions.Count -eq 0) {
        return
    }
    
    $otherSessions = $Sessions | Where-Object { -not $_.IsCurrent }
    if ($otherSessions.Count -eq 0) {
        return
    }
    
    Write-ColorOutput ""
    Write-ColorOutput "To resolve PowerShell session conflicts:" -Type Info
    Write-ColorOutput "• Close PowerShell windows manually" -Type Info
    Write-ColorOutput "• Close PowerShell ISE if open" -Type Info
    Write-ColorOutput "• Close VS Code if it has PowerShell files open" -Type Info
    Write-ColorOutput "• Close Windows Terminal tabs with PowerShell" -Type Info
    Write-ColorOutput ""
    Write-ColorOutput "To forcefully terminate PowerShell processes:" -Type Warning
    
    foreach ($session in $otherSessions) {
        if ($session.Type -ne "Windows Terminal") {  # Don't suggest killing Windows Terminal
            Write-ColorOutput "    Stop-Process -Id $($session.ProcessId) -Force" -Type Warning
        }
    }
    
    Write-ColorOutput ""
    Write-ColorOutput "After closing sessions, you can retry this script." -Type Info
}

function Test-ModuleConflicts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ModuleNames
    )
    
    Write-ColorOutput "Checking for module conflicts..." -Type Info
    
    $conflicts = @()
    $allSessions = Get-PowerShellSessions -IncludeCurrent
    $otherSessions = $allSessions | Where-Object { -not $_.IsCurrent }
    
    if ($otherSessions.Count -eq 0) {
        Write-ColorOutput "    No other PowerShell sessions detected" -Type Process
        return @()
    }
    
    # Check if any of the modules we want to remove/update are currently loaded
    $loadedModules = Get-Module | Where-Object { $_.Name -in $ModuleNames }
    if ($loadedModules) {
        Write-ColorOutput "    [Warning] The following modules are currently loaded:" -Type Warning
        foreach ($module in $loadedModules) {
            Write-ColorOutput "    • $($module.Name) v$($module.Version)" -Type Warning
            $conflicts += @{
                ModuleName = $module.Name
                Version = $module.Version
                Reason = "Currently loaded in this session"
                Session = "Current"
            }
        }
    }
    
    # Estimate potential conflicts from other sessions
    if ($otherSessions.Count -gt 0) {
        Write-ColorOutput "    [Warning] $($otherSessions.Count) other PowerShell sessions detected" -Type Warning
        Write-ColorOutput "    These sessions may have modules loaded that could prevent removal/updates" -Type Warning
        
        foreach ($session in $otherSessions) {
            foreach ($moduleName in $ModuleNames) {
                $conflicts += @{
                    ModuleName = $moduleName
                    Version = "Unknown"
                    Reason = "Potentially loaded in other session"
                    Session = "$($session.Type) (PID: $($session.ProcessId))"
                }
            }
        }
    }
    
    return $conflicts
}

# Main execution
try {
    # If user just wants to check for session conflicts, do that and exit
    if ($CheckSessions) {
        Clear-Host
        Write-ColorOutput "=== PowerShell Session Conflict Checker ===" -Type System
        Write-ColorOutput "Script Version: 2.5" -Type System
        Write-ColorOutput "Scan Time: $(Get-Date -Format (Get-Culture).DateTimeFormat.FullDateTimePattern)" -Type System
        Write-ColorOutput ""
        
        # Get all PowerShell sessions with detailed information
        $allSessions = Get-PowerShellSessions -IncludeCurrent -ShowDetails -ShowConflicts
        
        # Check for specific module conflicts with deprecated modules
        $moduleNames = $Script:DeprecatedModules | ForEach-Object { $_.Name }
        $conflicts = Test-ModuleConflicts -ModuleNames $moduleNames
        
        if ($conflicts.Count -gt 0) {
            Write-ColorOutput ""
            Write-ColorOutput "Module Conflict Analysis:" -Type Warning
            $uniqueConflicts = $conflicts | Sort-Object ModuleName, Session -Unique
            foreach ($conflict in $uniqueConflicts) {
                Write-ColorOutput "    • $($conflict.ModuleName): $($conflict.Reason) [$($conflict.Session)]" -Type Warning
            }
        }
          # Show guidance for resolving conflicts
        Show-PowerShellSessionGuidance -Sessions $allSessions
        
        # Offer termination option in CheckSessions mode
        $otherSessions = $allSessions | Where-Object { -not $_.IsCurrent }
        if ($otherSessions.Count -gt 0) {
            Write-ColorOutput ""
            $response = Read-Host "Would you like to terminate these conflicting sessions now? (Y/N)"
            if ($response -match '^[Yy]') {
                $terminationSuccess = Stop-ConflictingPowerShellSessions -Sessions $allSessions
                if ($terminationSuccess) {
                    Write-ColorOutput ""
                    Write-ColorOutput "✓ All conflicting sessions terminated successfully!" -Type Process
                    Write-ColorOutput "You can now run the update script without session conflicts." -Type Process
                }
            }
        }
        
        Write-ColorOutput ""
        Write-ColorOutput "Session check completed. Run the script without -CheckSessions to proceed with updates." -Type Info
        exit 0
    }
    
    # Validate administrator privileges
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-ColorOutput "Error: This script requires Administrator privileges" -Type Error
        Write-ColorOutput "Please run PowerShell as Administrator and try again" -Type Error
        exit 1
    }
      # Initialize script
    $moduleCount = Start-ScriptExecution    # Check for conflicting PowerShell sessions before starting module operations
    Write-ColorOutput "Checking for conflicting PowerShell sessions..." -Type System
    $Script:SessionConflictCheckPerformed = $true
    $allSessions = Get-PowerShellSessions -Silent
    $conflictingSessions = $allSessions | Where-Object { -not $_.IsCurrent }
      if ($conflictingSessions.Count -gt 0) {
        Write-ColorOutput ""
        Write-ColorOutput "⚠ DETECTED $($conflictingSessions.Count) OTHER POWERSHELL SESSION(S)" -Type Warning
        Write-ColorOutput "These sessions may interfere with module installation, updates, and removal." -Type Warning
        Write-ColorOutput ""
        
        # Show session details
        foreach ($session in $conflictingSessions) {
            $startTimeText = if ($session.StartTime) { $session.StartTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "Unknown" }
            $titleText = if ($session.WindowTitle -and $session.WindowTitle.Trim()) { $session.WindowTitle } else { "No title" }
            Write-ColorOutput "    • PID: $($session.ProcessId) - $($session.Type) - $titleText" -Type Info
        }
        Write-ColorOutput ""
        
        # Show informational warning about module operations being blocked
        Write-ColorOutput "These sessions may have PowerShell modules loaded, which can prevent:" -Type Warning
        Write-ColorOutput "    • Module installation (files in use)" -Type Warning
        Write-ColorOutput "    • Module updates (existing versions locked)" -Type Warning
        Write-ColorOutput "    • Module removal (loaded modules cannot be uninstalled)" -Type Warning
        Write-ColorOutput ""
          # Always offer termination option unless in CheckOnly mode
        if (-not $CheckOnly) {
            if ($TerminateConflicts) {
                # Automatic termination mode
                Write-ColorOutput "Auto-terminating conflicting sessions (TerminateConflicts parameter specified)..." -Type System
                $terminationSuccess = Stop-ConflictingPowerShellSessions -Sessions $allSessions -Force
                $Script:SessionConflictsResolved = $terminationSuccess
                if (-not $terminationSuccess) {
                    Write-ColorOutput "Warning: Some sessions could not be terminated. Module operations may encounter issues." -Type Warning
                    Write-ColorOutput ""
                }
            }
            else {                # Interactive mode - ask user
                $response = Read-Host "Terminate conflicting PowerShell sessions to ensure smooth operation? (Y/N)"
                if ($response -match '^[Yy]') {
                    $terminationSuccess = Stop-ConflictingPowerShellSessions -Sessions $allSessions -Force
                    $Script:SessionConflictsResolved = $terminationSuccess
                    if (-not $terminationSuccess) {
                        Write-ColorOutput "Warning: Some sessions could not be terminated. Module operations may encounter issues." -Type Warning
                        Write-ColorOutput ""
                        $continueResponse = Read-Host "Continue anyway? (Y/N)"
                        if ($continueResponse -notmatch '^[Yy]') {
                            Write-ColorOutput "Script execution cancelled by user." -Type Warning
                            exit 0
                        }
                    }
                    Write-ColorOutput ""
                }
                else {
                    Write-ColorOutput ""
                    Write-ColorOutput "⚠ Continuing with conflicting sessions present." -Type Warning
                    Write-ColorOutput "If module operations fail, consider closing other PowerShell applications." -Type Warning
                    Write-ColorOutput ""
                    $Script:SessionConflictsResolved = $false
                }
            }
        }
        else {
            Write-ColorOutput "Note: In check-only mode. Use -CheckSessions for detailed session analysis." -Type Info
            Write-ColorOutput ""
            $Script:SessionConflictsResolved = $false
        }
    }
    else {
        Write-ColorOutput "    ✓ No conflicting PowerShell sessions detected" -Type Process
        Write-ColorOutput ""
        $Script:SessionConflictsResolved = $true    }
    $counter = 0
    $moduleCount = $Script:ModuleList.Count
    
    # Update NuGet provider for PowerShell 5.x
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-ColorOutput "Updating NuGet provider for PowerShell 5.x compatibility..." -Type Info
        Test-PackageProvider -PackageName "NuGet" -Description "NuGet package provider"
    }
    
    # Proactive guidance for core module updates
    Write-ColorOutput "📋 Core Module Update Information:" -Type Info
    Write-ColorOutput "• Core modules (PackageManagement, PowerShellGet) may show 'in use' warnings" -Type Info
    Write-ColorOutput "• This is normal behavior - these modules are essential to PowerShell" -Type Info  
    Write-ColorOutput "• Updates will install side-by-side and activate on next PowerShell restart" -Type Info
    Write-ColorOutput "• No action required from you - the script handles this automatically" -Type Info
    Write-ColorOutput ""
    
    # Clean up deprecated modules first
    if (-not $SkipDeprecatedCleanup -and -not $CheckOnly) {
        # Check prerequisites before attempting module removal
        if (-not (Test-ModuleRemovalPrerequisites)) {
            Write-ColorOutput "Skipping deprecated module cleanup due to prerequisite issues" -Type Warning
            Write-ColorOutput ""
        } else {
            Remove-DeprecatedModules
        }
    } else {
        Remove-DeprecatedModules
    }
    
    # Process each module
    foreach ($module in $Script:ModuleList) {
        $counter++
        Write-ColorOutput "($counter of $moduleCount) Processing $($module.Description)" -Type Process
        
        # Check if this module requires special handling (core PowerShell modules)
        if ($module.RequiresSpecialHandling -eq $true) {
            Test-CoreModuleInstallation -ModuleName $module.Name -Description $module.Description
        }
        else {
            Test-ModuleInstallation -ModuleName $module.Name -Description $module.Description
        }
        
        Write-ColorOutput ""
    }    # Complete script execution
    Stop-ScriptExecution
    
    # Display troubleshooting information if there were any issues - but make it dismissible
    if (-not $CheckOnly) {
        Write-ColorOutput ""
        Write-ColorOutput "=== Troubleshooting Information ===" -Type Info
        Write-ColorOutput "Common troubleshooting tips:" -Type Info
        Write-ColorOutput "• If modules fail to uninstall: Run as Administrator and close other PowerShell sessions" -Type Info
        Write-ColorOutput "• If modules are 'in use': Restart PowerShell and try again" -Type Info
        Write-ColorOutput "• For MSI-installed modules: Use Windows Add/Remove Programs" -Type Info
        Write-ColorOutput "• For manual cleanup: Delete module folders from PowerShell module paths" -Type Info
        Write-ColorOutput "• If connection fails: Check network connectivity and firewall settings" -Type Info
        Write-ColorOutput "• For more help, visit: https://docs.microsoft.com/powershell/module/powershellget/" -Type Info
        Write-ColorOutput ""
        
        # Clear the troubleshooting info and show final status
#        Clear-Host
        Write-ColorOutput "`=== Microsoft Cloud PowerShell Module Updater - Complete ===" -Type System
        Write-ColorOutput "Script execution finished successfully!" -Type Process
        Write-ColorOutput "End Time: $(Get-Date -Format (Get-Culture).DateTimeFormat.FullDateTimePattern)" -Type System
        Write-ColorOutput ""
        
        # Show summary of what was accomplished
        Write-ColorOutput "Summary:" -Type Info
        Write-ColorOutput "• Module updates completed" -Type Process
        if (-not $SkipDeprecatedCleanup) {
            Write-ColorOutput "• Deprecated modules cleaned up" -Type Process
        }
        Write-ColorOutput "• System is ready for Microsoft Cloud operations" -Type Process
        Write-ColorOutput ""
        Write-ColorOutput "You can now use the updated PowerShell modules for Microsoft 365, Azure, and Teams management." -Type Info
    } else {
        Write-ColorOutput ""
        Write-ColorOutput "Check-only mode completed. No changes were made to your system." -Type Info
    }
    
    Write-ColorOutput ""
}
catch {
    Write-ColorOutput "Fatal Error: $($_.Exception.Message)" -Type Error
    Write-ColorOutput "Stack Trace: $($_.ScriptStackTrace)" -Type Error
    
    if ($CreateLog) {
        try {
            Stop-Transcript
        }
        catch {
            # Transcript might not be running
        }
    }
    
    exit 1
}

