<#
    Include functions
#>

. "$PSScriptRoot\includes\scripts\functions.ps1"

<#
    Reset variables

    To make sure those using PowerShell ISE execute the script with
    a clean slate.
#>

$whitelist = $blacklist = $filter_results = $filter_rules = $nxdomains = $web_host_sources = $fetched_hosts = $parsed_hosts = $null

Clear-Host

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
    $whitelist     = Get-Content $file_whitelist -ErrorAction Stop | ? {$_}

    # If there are whitelisted domains
    if($whitelist)
    {
        $whitelist = Parse-Hosts $whitelist `
                     | sort -Unique

        Extract-Domains $whitelist `
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
        $fetched_hosts       = Fetch-Hosts $web_host_sources `
                               | sort -Unique

        # Parse the hosts
        $parsed_hosts        = Parse-Hosts $fetched_hosts

        # Extract the domains
        Extract-Domains        $parsed_hosts `
                               | % {[void]$hosts_arr_l.Add($_)}

        # Extract the filter domains
        Extract-Filter-Domains $parsed_hosts `
                               | % {if(!$hosts_arr_l.Contains($_)){[void]$hosts_arr_l.Add($_)}}
    }
    else {throw}
}
catch {"--> !: Web hosts unavailable"}

# Local hosts
try
{
    # Read it
    $blacklist     = Get-Content $file_blacklist -ErrorAction Stop | ? {$_}

    if($blacklist)
    {
        # Parse the blacklist file
        $blacklist = Parse-Hosts $blacklist `
                                 | sort -Unique
        
        # Extract domains from blacklist
        Extract-Domains $blacklist `
                        | % {if(!$hosts_arr_l.Contains($_)){[void]$hosts_arr_l.Add($_)}}
    } else {throw}
}
catch {"--> !: Local blacklist unavailable"}

# Process Adhell specific filters
try
{
    # Read the config file
    $filter_rules   = Get-Content $file_ah_filter -ErrorAction Stop | ? {$_} `
                                  | sort -Unique
    if($filter_rules)
    {
        $filter_results =  Extract-Filters $filter_rules

        # If we have filter rules to process
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

                            # Add *.something.com to the wildcards array
                            if(!$wildcards_f_arr_l.Contains("*.$domain")){[void]$wildcards_f_arr_l.Add("*.$domain")}

                            # Remove something.com from the hosts array
                            while($hosts_arr_l.Contains($domain)){$hosts_arr_l.Remove($domain)}
                          }
                }
            }
        }
        else {throw}
    }
    else {throw}
}
catch {"--> !: Filter rules unavailable"}

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
    Extract-Wildcards            $blacklist `
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
    # If there are wildcards
    if($wildcards_arr_l)
    {
        # Fetch the removal criteria for standard wildcards
        Fetch-Regex-Removals -wildcards $wildcards_arr_l `
                             | % {[void]$regex_arr_l.Add($_)}
    }

    # If there are filter wildcards
    if($wildcards_f_arr_l)
    {
        # Fetch the removal criteria for filter wildcards
        Fetch-Regex-Removals -wildcards $wildcards_f_arr_l `
                             | % {if(!$regex_arr_l.Contains($_)){[void]$regex_arr_l.Add($_)}}
    }

    # If we obtained any regex removals
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