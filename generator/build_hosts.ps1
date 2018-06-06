Clear-Host

# Include functions file

. "$PSScriptRoot\includes\scripts\functions.ps1"

# Reset hosts array

$hosts = @()

# User Variables

$parent_dir       = Split-Path $PSScriptRoot

$out_file         = "$parent_dir\hosts"

$web_host_files   = 'http://someonewhocares.org/hosts/hosts',`
                    'https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0',`
                    'https://zeustracker.abuse.ch/blocklist.php?download=domainblocklist',`
                    'https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt',`
                    'https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt',`
                    'https://filters.adtidy.org/extension/chromium/filters/11.txt'

$local_host_dir   = "$PSScriptRoot\includes\hosts"
$local_host_files = "$PSScriptRoot\includes\config\blacklist.txt"
$local_wildcards  = "$PSScriptRoot\includes\config\wildcards.txt"
$local_regex      = "$PSScriptRoot\includes\config\regex.txt"
$local_whitelist  = "$PSScriptRoot\includes\config\whitelist.txt"
$local_nxhosts    = "$PSScriptRoot\includes\config\nxdomains.txt"

# Check the domain is still alive?
# This can take some time depending on host counts.

$check_heartbeat  = $false

# Fetch Hosts

Write-Output "--> Fetching Hosts"

$hosts            = Fetch-Hosts -w_host_files $web_host_files `
                                -l_host_files $local_host_files `
                                -dir $local_host_dir

# Quit in the event of no hosts detected

if(!($hosts))
{
    Write-Output "No hosts detected. Please check your configuration."
    Start-Sleep -Seconds 5
    exit
}

# Fetch Wildcards

Write-Output "--> Fetching wildcards"

$wildcards         = (Get-Content $local_wildcards) -split '\n' | Where {$_}

# Fetch Whitelist

$whitelist         = (Get-Content $local_whitelist) -split '\n' | Where {$_}

# Parse host file(s)

Write-Output '--> Parsing host files'

$hosts             = Parse-Hosts -hosts $hosts

# Output host count prior to removals

Write-Output "--> Valid hosts detected: $($hosts.count)"

# Update Regex Removals

Write-Output "--> Updating regex criteria"

Update-Regex-Removals -whitelist $whitelist -wildcards $wildcards -out_file $local_regex

# Fetch Regex criteria

$regex_removals    = (Get-Content $local_regex) -split '\n' | Where {$_}

# Run regex removals

Write-Output "--> Running regex removals"

$hosts             = Regex-Remove -local_regex $regex_removals -hosts $hosts

Write-Output "--> Hosts Detected: $($hosts.count)"

# If check heartbeats is enabled

if($check_heartbeat)
{
    Write-Output "--> Checking for heartbeats" 
    
    # Check the heartbeats

    Check-Heartbeat -hosts $hosts -out_file $local_nxhosts

}

# Fetch NXHOSTS before finalising

$nxhosts       = (Get-Content $local_nxhosts) -split "\n" | Where {$_}

# Finalise the hosts

Write-Output "--> Finalising"

$hosts             = Finalise-Hosts -hosts $hosts -wildcards $wildcards -nxhosts $nxhosts

Write-Output "--> Hosts added: $($hosts.count)"

# Save host file

Write-Output "--> Saving host file to: $out_file"

Save-Hosts -hosts $hosts -out_file $out_file