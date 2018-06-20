Clear-Host

# Include functions file

. "$PSScriptRoot\includes\scripts\functions.ps1"

# Reset arrays

$hosts            = @()
$wildcards        = @()

# User Variables

$parent_dir       = Split-Path $PSScriptRoot

$web_sources      = "$PSScriptRoot\includes\config\user_settings\web_sources.txt"

$host_down_dir    = "$PSScriptRoot\includes\hosts"

$local_blacklists = "$PSScriptRoot\includes\config\user_settings\blacklist.txt"
$local_regex      = "$PSScriptRoot\includes\config\generated_settings\regex.txt"
$local_whitelist  = "$PSScriptRoot\includes\config\user_settings\whitelist.txt"
$local_nxhosts    = "$PSScriptRoot\includes\config\generated_settings\nxdomains.txt"

$out_file         = "$parent_dir\hosts"

# Check the domain is still alive?
# This can take some time depending on host counts.

$check_heartbeat  = $false

# Fetch Hosts (Excluding wildcards)
# Each host file will be parsed individually to accommodate for non-standard lists.

Write-Output "--> Fetching Hosts"

$web_host_files   = Get-Content $web_sources | Where {$_}


$hosts            = Fetch-Hosts -w_host_files $web_host_files -l_host_files $local_blacklists -dir $host_down_dir `
                                | Where {$_ -notmatch "\*"} `
                                | Sort-Object -Unique

# Quit in the event of no hosts detected

if(!($hosts))
{
    Write-Output "No hosts detected. Please check your configuration."
    Start-Sleep -Seconds 5
    exit
}

# Fetch Whitelist

Write-Output "--> Fetching whitelist"

$whitelist        = (Get-Content $local_whitelist) | Where {$_}

# Fetch wildcards

Write-Output "--> Fetching wildcards from blacklist"

$wildcards       += (Get-Content $local_blacklists) | Where {$_ -match "^((\*)([A-Z0-9-_.]+))$|^((\*)([A-Z0-9-_.]+)(\*))$|^(([A-Z0-9-_.]+)(\*))$"}

# Identify wildcard prefixes

Write-Output "--> Identifying wildcard prefixes"

$wildcards       += Identify-Wildcard-Prefixes -hosts $hosts -whitelist $whitelist -prefix_determination_count 4 `
                                               | Sort-Object

# Convert WWW to * and add to wildcards

$www_regex        = "^(www)([0-9]{0,3})?(\.)"

$wildcards       += $hosts | Select-String $www_regex -AllMatches `
                           | foreach {$_ -replace $www_regex, "*" }

# Check for conflicting wildcards

Write-Output "--> Checking for conflicting wildcards"

$wildcards        = Remove-Conflicting-Wildcards -wildcards $wildcards -whitelist $whitelist

# Update Regex Removals

Write-Output "--> Updating regex criteria"

Update-Regex-Removals -whitelist $whitelist -wildcards $wildcards -out_file $local_regex

# Fetch Regex criteria

Write-Output "--> Fetching regex criteria"

$regex_removals   = (Get-Content $local_regex) | Where {$_}

# Run regex removals

Write-Output "--> Running regex removals"

$hosts            = Regex-Remove -local_regex $regex_removals -hosts $hosts

Write-Output "--> Post-regex hosts detected: $($hosts.count)"

# If check heartbeats is enabled

if($check_heartbeat)
{
    Write-Output "--> Checking for heartbeats" 
    
    # Check the heartbeats

    Check-Heartbeat -hosts $hosts -out_file $local_nxhosts

}

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