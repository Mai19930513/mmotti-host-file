Clear-Host

# Include functions file

. "$PSScriptRoot\includes\scripts\functions.ps1"

# Reset arrays

$hosts            = New-Object System.Collections.ArrayList
$collated_hosts   = @()
$wildcards        = @()

# User Variables

$parent_dir       = Split-Path $PSScriptRoot

$web_sources      = "$PSScriptRoot\includes\config\user_settings\web_sources.txt"

$host_down_dir    = "$PSScriptRoot\includes\hosts"

$local_blacklists = "$PSScriptRoot\includes\config\user_settings\blacklist.txt"
$local_whitelist  = "$PSScriptRoot\includes\config\user_settings\whitelist.txt"
$local_nxhosts    = "$PSScriptRoot\includes\config\generated_settings\nxdomains.txt"

$out_file         = "$parent_dir\hosts"


# Check the domain is still alive?
# This can take some time depending on host counts.

#$check_heartbeat  = $false


# Collate hosts

Write-Output "--> Fetching hosts"

$web_host_files   = Get-Content $web_sources | Where {$_}

$collated_hosts  += Fetch-Hosts -w_host_files $web_host_files -l_host_files $local_blacklists -dir $host_down_dir `
                    | Sort-Object -Unique


# Fetch Whitelist

Write-Output "--> Fetching whitelist"

$whitelist        = (Get-Content $local_whitelist) | Where {$_}


# Add standard domains to an array

Write-Output "--> Fetching standard domains"

Extract-Domains $collated_hosts | % {[void]$hosts.Add($_)}


# Add filter hosts to an array

Write-Output "--> Fetching filter hosts"

Extract-Filter-Domains $collated_hosts | % {[void]$hosts.Add($_)}


# Status update

Write-Output "--> $($hosts.Count) hosts detected"


# Add wildcards to an array

Write-Output "--> Fetching wildcards"

$wildcards       += Extract-Wildcards $collated_hosts


# Quit in the event of no valid hosts

if(!$hosts -and !$wildcards)
{
    Write-Output "No hosts detected. Please check your configuration."
    Start-Sleep -Seconds 5
    exit
}


# Check for conflicting wildcards

Write-Output "--> Checking wildcards for conflicts"

$wildcards        = $wildcards | Sort-Object -Unique

$wildcards        = Remove-Conflicting-Wildcards -wildcards $wildcards -whitelist $whitelist


# Status update

Write-Output "--> $($wildcards.Count) wildcards detected"


# Update Regex Removals

Write-Output "--> Fetching regex criteria"

$regex_removals   = Fetch-Regex-Removals -whitelist $whitelist -wildcards $wildcards


# Run regex removals

Write-Output "--> Running regex removals"

$hosts            = Regex-Remove -local_regex $regex_removals -hosts $hosts

Write-Output "--> $($hosts.count) hosts remain after regex removal"


# Remove host clutter

Write-Output "--> Removing host clutter"

$hosts            = Remove-Host-Clutter $hosts


# Status update

Write-Output "--> $($hosts.Count) hosts remain after de-clutter"


<#
    This needs checking after the recent changes

# If check heartbeats is enabled

if($check_heartbeat)
{
    Write-Output "--> Checking for heartbeats" 
    
    # Check the heartbeats

    Check-Heartbeat -hosts $hosts -out_file $local_nxhosts

}

#>


# Fetch NXHOSTS before finalising

Write-Output "--> Fetching NXDOMAINS"

$nxhosts          = (Get-Content $local_nxhosts) | Where {$_}


# Finalise the hosts

Write-Output "--> Finalising"

$hosts            = Finalise-Hosts -hosts $hosts -wildcards $wildcards -nxhosts $nxhosts

Write-Output "--> Hosts added: $($hosts.count)"


# Save host file

Write-Output "--> Saving host file to: $out_file"

Save-Hosts -hosts $hosts -out_file $out_file