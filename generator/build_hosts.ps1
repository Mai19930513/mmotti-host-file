Clear-Host

<#
    Include functions
#>


. "$PSScriptRoot\includes\scripts\functions.ps1"


<#
    Reset variables
#>


$blacklist             = @()
$hosts                 = @()
$nxdomains             = @()
$regex_removals        = @()
$web_host_files        = @()
$whitelist             = @()
$wildcards             = @()


<#
    Set script parameters
#>


$parent_dir            = Split-Path $PSScriptRoot

$web_sources           = "$PSScriptRoot\settings\sources.txt"

$host_down_dir         = "$PSScriptRoot\hosts"

$local_blacklist       = "$PSScriptRoot\settings\blacklist.txt"
$local_whitelist       = "$PSScriptRoot\settings\whitelist.txt"
$local_nxhosts         = "$PSScriptRoot\settings\nxdomains.txt"

$out_file              = "$parent_dir\hosts"


# Check the domain is still alive?
# This can take some time depending on host counts.

$check_heartbeat       = $false


<#
    Start fetching hosts
    
    Try / Catch statements to suppress errors if the user does not
    include web host sources or a local blacklist
#>


Write-Output "--> Fetching: Hosts"

# Read web host sources

try
{
    $web_host_files    = Get-Content $web_sources -ErrorAction Stop | ? {$_}
}
catch
{
    Write-Output "--> Warning: Web sources file unavailable"
}

# Read local blacklist

try
{
    $blacklist         = Get-Content $local_blacklist -ErrorAction Stop | ? {$_}
}
catch
{
    Write-Output "--> Warning: Local blacklist file unavailable"
}


# Fetch valid hosts from the provided web and local hosts

$hosts                 = Fetch-Hosts -w_host_sources $web_host_files -l_host_file $blacklist -dir $host_down_dir `
                                     | sort -Unique


# Quit in the event of no valid hosts

if(!$hosts)
{
    Write-Output "No hosts detected. Please check your configuration."
    Start-Sleep -Seconds 5
    exit
}


# Status update

Write-Output "--> Hosts: $($hosts.Count)"


<#
    Fetch whitelist

    Try / catch statements to suppress errors if the user does
    not provide a whitelist.
#>


Write-Output "--> Fetching: Whitelist"

# Read whitelist file (if available)

try
{

    $whitelist         = Get-Content $local_whitelist -ErrorAction Stop | ? {$_}
}
catch
{
    Write-Output "--> Warning: Whitelist unavailable"
    
}


<#
    Extract wildcards

    We extract wildcards from the local blacklist, so only process
    if we have a blacklist.
#>


Write-Output "--> Fetching: Wildcards"

# If a blacklist exists
if($blacklist)
{
    # Extract wildcards from it
    $wildcards         = Extract-Wildcards $blacklist `
                         | sort -Unique

    # If any wildcards were extracted
    # Remove any that conflict with whitelist or any duplicates
    if($wilcards)
    {
        Write-Output "--> Checking wildcards for conflicts"

        $wildcards     = Remove-Conflicting-Wildcards -wildcards $wildcards -whitelist $whitelist
    }
}


<#
    Fetch regex removal criteria
#>


Write-Output "--> Fetching: Regex criteria"

$regex_removals        = Fetch-Regex-Removals -whitelist $whitelist -wildcards $wildcards


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
    Write-Output "--> Running: Regex removals"

    $hosts             = Regex-Remove -regex_removals $regex_removals -hosts $hosts

    Write-Output "--> Hosts: $($hosts.count)"
}


<#
    Remove host clutter
    
    As Adhell3 / SABS etc prefix with a wildcard (*), there's a lot of domains
    that we can remove
    
    E.g. if we have something.com, we don't need test.something.com
    or bad.test.com
#>


Write-Output "--> Running: Remove host clutter"

$hosts                 = Remove-Host-Clutter $hosts


# Status update

Write-Output "--> Hosts: $($hosts.Count)"


<#
    Check for dead hosts (NXDOMAINS)

    We can save some space by excluding dead domains. This function will save
    dead hosts to a file.
#>


if($check_heartbeat)
{
    Write-Output "--> Checking for heartbeats" 
    
    # Check the heartbeats

    Check-Heartbeat -hosts $hosts -out_file $local_nxhosts

}


<#
    Fetch NXDOMAINS

    Fetch any domains that have been previously gathered and saved.
#>


Write-Output "--> Fetching: NXDOMAINS"

# Read NXDOMAINS file (if available)
try
{
    $nxdomains         = Get-Content $local_nxhosts -ErrorAction Stop | ? {$_}
}
catch
{
    Write-Output "--> Warning: NXDOMAINS unavailable"
}


<#
    Finalise the hosts

    We need to add the wildcards, remove dead hosts and exclude duplicates
#>


Write-Output "--> Finalising"

$hosts                 = Finalise-Hosts -hosts $hosts -wildcards $wildcards -nxdomains $nxdomains

Write-Output "--> Hosts: $($hosts.count)"


<#
    Save host file

    Join the host file on "`n" and add a blank line to the end of the file
#>


Write-Output "--> Saving host file to: $out_file"

Save-Hosts -hosts $hosts -out_file $out_file