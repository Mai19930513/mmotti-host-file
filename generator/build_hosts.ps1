<#
    Include functions
#>

. "$PSScriptRoot\includes\scripts\functions.ps1"

<#
    Reset variables

    To make sure those using PowerShell ISE execute the script with
    a clean slate.
#>

$blacklist = $filter_results = $filter_rules = $nxdomains = $web_host_sources = $null

<#
    Initialise variables
#>

# Create empty ArrayLists
#
$wildcards_arr_l   = [System.Collections.ArrayList]::new()
$wildcards_f_arr_l = [System.Collections.ArrayList]::new()
$regex_arr_l       = [System.Collections.ArrayList]::new()
$whitelist_arr_l   = [System.Collections.ArrayList]::new()
$hosts_arr_l       = [System.Collections.ArrayList]::new()

<#
    Set script parameters
#>

# Directories
$dir_parent        = Split-Path $PSScriptRoot
$dir_settings      = "$PSScriptRoot\settings"

# Config files
$file_sources      = "$dir_settings\sources.txt"
$file_blacklist    = "$dir_settings\blacklist.txt"
$file_whitelist    = "$dir_settings\whitelist.txt"
$file_ah_filter    = "$dir_settings\adhell_specific\filter.txt"
$file_nxdomains    = "$dir_settings\nxdomains.txt"

# Settings
$out_file          = "$dir_parent\hosts"
$check_heartbeat   = $false


<#
    Fetch whitelist
#>

Write-Output         "--> Fetching whitelist"

try
{
    # Add whitelist to array
    Get-Content      $file_whitelist -ErrorAction Stop | ? {$_} `
                     | % {[void]$whitelist_arr_l.add($_)}

    # If there are whitelisted domains
    if($whitelist_arr_l)
    {
        Parse-Hosts $whitelist_arr_l `
                    | % {$whitelist_arr_l.Clear()}{[void]$whitelist_arr_l.Add($_)}
    }
    else {throw}
}
catch
{"--> !: Whitelist unavailable"}

<#
    Fetch hosts
#>

Write-Output         "--> Fetching hosts"

# Web hosts
try
{
    # Read from the file source
    $web_host_sources = Get-Content $file_sources -ErrorAction Stop | ? {$_}

    # If there are web sources
    if($web_host_sources)
    {
        # Fetch the hosts
        # Add to hosts array
        Fetch-Hosts      -host_sources $web_host_sources `
                         | sort -Unique `
                         | % {[void]$hosts_arr_l.Add($_)}
    }
    else {throw}
}
catch {"--> !: Web hosts unavailable"}

# Local hosts
try
{
    # Read it
    $blacklist           = Get-Content $file_blacklist -ErrorAction Stop | ? {$_}

    if($blacklist)
    {
        # Fetch hosts
        # if not already in the array, add the host to it.
        Parse-Hosts         $blacklist | sort -Unique `
                                       | % {if(!$hosts_arr_l.Contains($_)){[void]$hosts_arr_l.Add($_)}}
    } else {throw}
}
catch {"--> !: Local blacklist unavailable"}

# Process Adhell specific filters
try
{
    # Read it
    $filter_rules   = Get-Content $file_ah_filter -ErrorAction Stop | ? {$_} `
                                  | sort -Unique
    if($filter_rules)
    {
        # Extract the rules / instructions
        $filter_results = Extract-Adhell-Filters $filter_rules

        # If there are valid rules / instructions
        if($filter_results)
        {
            $filter_results | % {

                $rule   = $_.Rule
                $domain = $_.Domain
                $option = $_.Option

                switch ($option)
                {
                    '||' {
                            # Skip if whitelisted or already processed
                            if($whitelist_arr_l -match "(^|\.)$domain")
                            {
                                return
                            }

                            # Add the processed rule to the hosts array
                            [void]$hosts_arr_l.Add("@dhell$rule")

                            # || should filter something.com and *.something.com
                            # Adhell should create these entries from the rule, so we don't need
                            # to include them.
                            $domain_result = $domain, "*.$domain"

                            # For each domain result
                            $domain_result | % {
                                # If we have a wildcard, add it to the filter wildcards array
                                # ready for regex removal
                                if($_ -match "\*")
                                {
                                    if(!$wildcards_f_arr_l.Contains($_)){[void]$wildcards_f_arr_l.Add($_)}
                                }
                                else
                                {
                                    # Remove standard domain from host array
                                    while($hosts_arr_l.Contains($_)){$hosts_arr_l.Remove($_)}
                                }
                            }
                         }
                }
            }
        }
        else {throw }
    }
    else {throw}
}
catch {"--> !: No adhell rules detected"}

<#
    Remove whitelisted entries
#>

# Quit if there are no hosts
if(!$hosts_arr_l)
{
    No-Hosts
}
# If there are hosts
else
{
    # ... and items in the whitelist array
    if($whitelist_arr_l)
    {
        try
        {
            # Remove them
            Remove-WhitelistedDomains -hosts $hosts_arr_l -whitelist $whitelist_arr_l `
                                      | % {$hosts_arr_l.Clear()}{[void]$hosts_arr_l.Add($_)}

            # If there are no hosts after the whitelisted items are removed
            if(!$hosts_arr_l)
            {
                No-Hosts
            }
        }
        catch {"--> Unable to remove whitelisted items"}
    }
}

<#
    Fetch wildcards
#>

Write-Output         "--> Searching for wildcards"

try
{
    # Extract wildcards from blacklist
    Extract-Wildcards $blacklist `
                        | sort -Unique `
                        | % {if(!$wildcards_arr_l.Contains($_)){[void]$wildcards_arr_l.Add($_)}}

    # Remove conflicting wildcards
    Remove-Conflicting-Wildcards -wildcards $wildcards_arr_l -filter_wildcards $wildcards_f_arr_l -whitelist $whitelist_arr_l `
                                 | % {$wildcards_arr_l.Clear()}{[void]$wildcards_arr_l.Add($_)}


    # If there were no wildcards
    if(!$wildcards_arr_l)
    {
        throw
    }
}
catch {"--> !: Wildcards unavailable"}


<#
    Process Regex Removals
#>

Write-Output         "--> Processing Regex Removals"

try
{
    # Fetch the removal criteria for standard wildcards
    Fetch-Regex-Removals -wildcards $wildcards_arr_l `
                         | % {[void]$regex_arr_l.Add($_)}

    # Fetch the removal criteria for filter wildcards
    Fetch-Regex-Removals -wildcards $wildcards_f_arr_l `
                         | % {if(!$regex_arr_l.Contains($_)){[void]$regex_arr_l.Add($_)}}

    # If there are items to process
    if($regex_arr_l)
    {
        # Regex remove hosts
        Regex-Remove -regex_removals $regex_arr_l -hosts $hosts_arr_l `
                     | % {$hosts_arr_l.Clear()}{[void]$hosts_arr_l.Add($_)}
    }
    else {throw}
}
catch {"--> !: Regex removals unavailable"}

<#
    Remove host clutter
#>

Write-Output         "--> Removing host clutter"

try
{
    Remove-Host-Clutter $hosts_arr_l `
                        | % {$hosts_arr_l.Clear()}{[void]$hosts_arr_l.Add($_)}
}
catch
{$PSCmdlet.WriteError($_)}

<#
    Check for dead hosts (NXDOMAINS)
#>

if($check_heartbeat)
{
    Write-Output     "--> Checking for heartbeats"

    try
    {
        # Check the heartbeats
        Check-Heartbeat  -hosts $hosts_arr_l -out_file $file_nxdomains
    }
    catch
    {$PSCmdlet.WriteError($_)}
}

<#
    Fetch NXDOMAINS
#>

Write-Output         "--> Fetching dead domains (NXDOMAINS)"

try
{
    # Read it
    $nxdomains      = Get-Content $file_nxdomains -ErrorAction Stop | ? {$_}

    if(!$nxdomains)
    {
        throw
    }
}
catch
{"--> !: NXDOMAINS unavailable"}

<#
    Finalise the hosts

    We need to add the wildcards, remove dead hosts and exclude duplicates
#>

Write-Output         "--> Finalising hosts"

try
{
    Finalise-Hosts -hosts $hosts_arr_l -wildcards $wildcards_arr_l -nxdomains $nxdomains `
                   | % {$hosts_arr_l.Clear()}{[void]$hosts_arr_l.Add($_)}
}
catch
{$PSCmdlet.WriteError($_)}

<#
    Save host file

    Join the host file on "`n" and add a blank line to the end of the file
#>

Write-Output          "--> Saving $($hosts_arr_l.Count) hosts to: $out_file"

try
{
    Save-Hosts        -hosts $hosts_arr_l -out_file $out_file
}
catch {$PSCmdlet.ThrowTerminatingError($_)}