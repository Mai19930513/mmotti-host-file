<#
    Reset variables

    To make sure those using PowerShell ISE execute the script with
    a clean slate.
#>


Remove-Variable * -ErrorAction SilentlyContinue; Remove-Module *; $error.Clear(); Clear-Host


<#
    Include functions
#>


. "$PSScriptRoot\includes\scripts\functions.ps1"


<#
    Set script parameters
#>


# Directories

$dir_parent       = Split-Path $PSScriptRoot
$dir_settings     = "$PSScriptRoot\settings"
$dir_hosts        = "$PSScriptRoot\hosts"

# Config files

$sources         = "$dir_settings\sources.txt"
$file_blacklist  = "$dir_settings\blacklist.txt"
$file_whitelist  = "$dir_settings\whitelist.txt"
$file_nxdomains  = "$dir_settings\nxdomains.txt"

# Settings
$out_file        = "$dir_parent\hosts"
$exit_timeout    = 10     # Seconds
$check_heartbeat = $false # Check for NXDOMAINS?


<#
    Start fetching hosts
    
    Try / Catch statements to suppress errors if the user does not
    include web host sources or a local blacklist
#>


Write-Output         "Fetching hosts... `n"

# Read web host sources

try
{
    $web_host_files = Get-Content $sources -ErrorAction Stop | ? {$_}
}
catch
{
    Write-Output     "`t Web sources file unavailable `n"
}

# Read local blacklist

try
{
    $blacklist      = Get-Content $file_blacklist -ErrorAction Stop | ? {$_}
}
catch
{
    Write-Output     "`t Local blacklist file unavailable `n"
}


# Fetch valid hosts from the provided web and local hosts

$hosts              = Fetch-Hosts -w_host_sources $web_host_files -l_host_file $blacklist -dir $dir_hosts `
                                  | sort -Unique


# Quit in the event of no valid hosts

if(!$hosts)
{
    Write-Output     "No hosts detected. Please check your configuration."
    Start-Sleep      -Seconds 5
    exit
}


# Status update

Write-Output         "`n`t # Hosts: $($hosts.Count) `n"


<#
    Fetch whitelist

    Try / catch statements to suppress errors if the user does
    not provide a whitelist.
#>


Write-Output         "Fetching whitelist... `n"

# Read whitelist file (if available)

try
{

    $whitelist      = Get-Content $file_whitelist -ErrorAction Stop | ? {$_}

    Write-Output     "`t # Whitelist: $($whitelist.Count) `n"
}
catch
{
    Write-Output     "`t Whitelist unavailable `n"
    
}


<#
    Extract wildcards

    We extract wildcards from the local blacklist, so only process
    if we have a blacklist.
#>


# If a blacklist exists
if($blacklist)
{
    Write-Output     "Fetching wildcards... `n"

    # Extract wildcards from it
    $wildcards      = Extract-Wildcards $blacklist `
                      | sort -Unique

    # If any wildcards were extracted
    # Remove conflicting or duplicate wildcards
    # Otherwise output a blank array
    if($wildcards)
    {
        Write-Output "`t # Wildcards: $($wildcards.Count) `n"

        Write-Output "Checking wildcards for conflicts... `n"

        $wildcards  = Remove-Conflicting-Wildcards -wildcards $wildcards -whitelist $whitelist

        Write-Output "`t # Wildcards: $($wildcards.Count) `n"
    }
}


<#
    Fetch regex removal criteria
#>


Write-Output         "Fetching regex criteria... `n"

$regex_removals     = Fetch-Regex-Removals -whitelist $whitelist -wildcards $wildcards

Write-Output         "`t # Regex checks: $($regex_removals.Count) `n"


<#
    Run regex removals
    
    It's possible that the $regex_removals could be null if the user has
    not provided a whitelist or any wildcards. We'll only proceed if there are
    things to remove.
#>


# If we have any removals
# Remove them from the host array
# Show count

if($regex_removals)
{
    Write-Output     "Running regex removals... `n"

    $hosts          = Regex-Remove -regex_removals $regex_removals -hosts $hosts

    Write-Output     "`t # Hosts: $($hosts.Count) `n"
}


<#
    Remove host clutter
    
    As Adhell3 / SABS etc prefix with a wildcard (*), there's a lot of domains
    that we can remove
    
    E.g. if we have something.com, we don't need test.something.com
    or bad.test.com
#>


Write-Output         "Removing host clutter... `n"

$hosts              = Remove-Host-Clutter $hosts

Write-Output         "`t # Hosts: $($hosts.Count) `n"


<#
    Check for dead hosts (NXDOMAINS)

    We can save some space by excluding dead domains. This function will save
    dead hosts to a file.
#>


if($check_heartbeat)
{
    Write-Output     "Checking for heartbeats... `n"
    
    # Check the heartbeats

    Check-Heartbeat  -hosts $hosts -out_file $file_nxdomains

}


<#
    Fetch NXDOMAINS

    Fetch any domains that have been previously gathered and saved.
#>


Write-Output         "Fetching NXDOMAINS... `n"

# Read NXDOMAINS file (if available)

try
{
    $nxdomains      = Get-Content $file_nxdomains -ErrorAction Stop | ? {$_}
    
    Write-Output     "`t # NXDOMAINS: $($nxdomains.Count) `n"
}
catch
{
    Write-Output     "`t NXDOMAINS unavailable `n"
}


<#
    Finalise the hosts

    We need to add the wildcards, remove dead hosts and exclude duplicates
#>


Write-Output         "Finalising... `n"

$hosts              = Finalise-Hosts -hosts $hosts -wildcards $wildcards -nxdomains $nxdomains

Write-Output         "`t # Hosts: $($hosts.Count) `n"


<#
    Save host file

    Join the host file on "`n" and add a blank line to the end of the file
#>


Write-Output         "Saving host file to: $out_file `n"

Save-Hosts           -hosts $hosts -out_file $out_file


<#
    Sleep

    Give the user a chance to read the script output
#>


Write-Output         "Exiting in $exit_timeout seconds"

Start-Sleep          -Seconds $exit_timeout

exit