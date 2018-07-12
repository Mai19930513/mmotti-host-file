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
    Initialise variables
#>

# Create empty hosts ArrayList
$hosts             = [System.Collections.ArrayList]::new()

# Create hash tables for splatting
# These are used where we have optional parameters
$args_white_wcard = @{}
$args_finalise    = @{}

<#
    Set script parameters
#>

# Directories
$dir_parent       = Split-Path $PSScriptRoot
$dir_settings     = "$PSScriptRoot\settings"
$dir_hosts        = "$PSScriptRoot\hosts"

# Config files
$file_sources    = "$dir_settings\sources.txt"
$file_blacklist  = "$dir_settings\blacklist.txt"
$file_whitelist  = "$dir_settings\whitelist.txt"
$file_nxdomains  = "$dir_settings\nxdomains.txt"

# Settings
$out_file        = "$dir_parent\hosts"
$check_heartbeat = $false

<#
    Fetch whitelist
#>

Write-Output         "--> Fetching whitelist"

# If the whitelist exists
if(Test-Path $file_whitelist -PathType Leaf)
{
    # Read it
    $whitelist      = Get-Content $file_whitelist | ? {$_}

    # If there are items in the whitelist
    if($whitelist)
    {   
        # Add to argument
        $args_white_wcard.whitelist = $whitelist
    }
}

<#
    Fetch hosts
#>

Write-Output         "--> Fetching hosts"

# If the host sources file exists
if(Test-Path $file_sources -PathType Leaf)
{
    # Read it
    $web_host_files = Get-Content $file_sources | ? {$_}
    
    # If there are host sources
    if($web_host_files)
    {
        # Fetch the hosts
        # Add to hosts array
        Fetch-Hosts -host_sources $web_host_files -dir $dir_hosts `
                    | sort -Unique `
                    | % {if(!$hosts.Contains($_)){[void]$hosts.Add($_)}}
    }   
}

# If the local blacklist exists
if(Test-Path $file_blacklist -PathType Leaf)
{
    # Read it
    $blacklist      = Get-Content $file_blacklist | ? {$_}

    # If there are items in the local blacklist
    if($blacklist)
    {
        # Fetch hosts
        # if not already in the array, add the host to it.
        Parse-Hosts       $blacklist | sort -Unique `
                                     | % {if(!$hosts.Contains($_)){[void]$hosts.Add($_)}}
        
        # Extract wildcards from it

        Write-Output     "--> Fetching wildcards"

        $wildcards      = Extract-Wildcards $blacklist `
                          | sort -Unique

        # If any wildcards were extracted
        if($wildcards)
        {
            # Add wildcards argument
            $args_white_wcard.wildcards = $wildcards
            
            # Remove conflicts
            $wildcards                   = Remove-Conflicting-Wildcards @args_white_wcard

            # If there are still wildcards after conflict removal
            if($wildcards)
            {
                # Add updated wildcards to necessary arguments
                $args_white_wcard.wildcards  = $wildcards
                $args_finalise.wildcards     = $wildcards
            }
        }
    }
}

# Quit in the event of no valid hosts
if(!$hosts)
{
    Write-Output     "--> No hosts detected. Please check your configuration."
    Start-Sleep      -Seconds 5
    exit
}

<#
    Process Regex Removals
#>

Write-Output         "--> Processing Regex Removals"

$regex_removals     = Fetch-Regex-Removals @args_white_wcard

# If there are removals to process
if($regex_removals)
{
    # Regex remove hosts
    [System.Collections.ArrayList]`
    $hosts          = Regex-Remove -regex_removals $regex_removals -hosts $hosts
}

<#
    Remove host clutter
    
    As Adhell3 / SABS etc prefix with a wildcard (*), there's a lot of domains
    that we can remove
    
    E.g. if we have something.com, we don't need test.something.com
    or bad.test.com
#>

Write-Output         "--> Removing host clutter"

[System.Collections.ArrayList]`
$hosts              = Remove-Host-Clutter $hosts

<#
    Check for dead hosts (NXDOMAINS)

    We can save some space by excluding dead domains. This function will save
    dead hosts to a file.
#>

if($check_heartbeat)
{
    Write-Output     "--> Checking for heartbeats"
    
    # Check the heartbeats

    Check-Heartbeat  -hosts $hosts -out_file $file_nxdomains

}

<#
    Fetch NXDOMAINS

    Fetch any domains that have been previously gathered and saved.
#>

Write-Output         "--> Fetching dead domains (NXDOMAINS)"

# If the NXDOMAINS file exists
if(Test-Path $file_nxdomains -PathType Leaf)
{
    # Read it
    $nxdomains      = Get-Content $file_nxdomains | ? {$_}  
    
    # If there are NXDOMAINS
    if($nxdomains)
    {
        $args_finalise.nxdomains = $nxdomains
    } 
}

<#
    Finalise the hosts

    We need to add the wildcards, remove dead hosts and exclude duplicates
#>

Write-Output         "--> Finalising hosts"

[System.Collections.ArrayList]`
$hosts              = Finalise-Hosts -hosts $hosts @args_finalise

<#
    Save host file

    Join the host file on "`n" and add a blank line to the end of the file
#>

Write-Output         "--> Saving $($hosts.Count) hosts to: $out_file"

Save-Hosts           -hosts $hosts -out_file $out_file