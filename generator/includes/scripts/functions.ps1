Function Fetch-Hosts
{
    Param
    (
        $w_host_files,
        $l_host_files,
        [Parameter(Mandatory=$true)]
        $dir
    )

    # SSL Support
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    # If the host download directory exists, clear it out.
    # Otherwise create a fresh directory
    if(Test-Path $dir)
    {
        Remove-Item "$dir\*" -Recurse | Out-Null
    }
    else
    {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }

    # Set Iterator
    $i = 1
    
    # WEB
    if($w_host_files)
    {    
        foreach($host_file in $w_host_files)
        {
            # Define host file name
            $dwn_host = "$dir\$i.txt"
            
            # Download the host file
            (New-Object System.Net.Webclient).DownloadFile($host_file, $dwn_host)

            # Read it
            $WHL = (Get-Content $dwn_host) | Where {$_}

            # Parse it
            $WHL =  Parse-Hosts -hosts $WHL

            # Add hosts to array
            $hosts += $WHL           
            
            $i++
        }

        # Purge downloaded hosts
        Remove-Item "$dir" -Recurse | Out-Null
    }

    # LOCAL
    if($l_host_files)
    {
        foreach($host_file in $l_host_files)
        {
           # Read it
           $LHL = (Get-Content $host_file) | Where {$_}

           # Parse it
           $LHL = Parse-Hosts -hosts $LHL

           # Add non-wildcard hosts to  array
           $hosts += $LHL
        }
    }    

    return $hosts
}

Function Parse-Hosts
{
    Param
    (
        [Parameter(Mandatory=$true)]
        $hosts
    )

     # First, test for a filter list
    $filter_list  = $hosts | Select-String "(?sim)((?<=^\|\|)([A-Z0-9-_.]+)(?=\^([$]third-party)?$))" -AllMatches

    # If we are processing a filter list
    if($filter_list)
    {
        # Only capture compatible hosts
        $hosts = $filter_list | % {$_.Matches.Value}
    }
    
    # Remove local end-zone
    $hosts        = $hosts -replace '127.0.0.1'`
                           -replace '0.0.0.0'
    # Remove whitespace
    $hosts        = $hosts -replace '\s'

    # Remove user comments
    $hosts        = $hosts -replace '(#.*)|((\s)+#.*)'

    # Remove www prefixes
    $hosts        = $hosts -replace '^(www)([0-9]{0,3})?(\.)'

    # Only select 'valid' URLs
    $hosts        = $hosts | Select-String '(?sim)(localhost)' -NotMatch `
                           | Select-String '(?sim)(?=^.{4,253}$)(^((?!-)[a-z0-9-]{1,63}(?<!-)\.)+[a-z]{2,63}$)|^([\*])([A-Z0-9-_.]+)$|^([A-Z0-9-_.]+)([\*])$|^([\*])([A-Z0-9-_.]+)([\*])$' -AllMatches

    # Remove empty lines 
    $hosts        = $hosts | Select-String '(^\s*$)' -NotMatch

    # Remove MatchInfo before selecting unique hosts
    $hosts        = $hosts -replace ''
    
    # Remove duplicates and force lower case
    ($hosts).toLower() | Sort-Object -Unique
   
}

Function Update-Regex-Removals
{

    Param
    (
        $whitelist,
        $wildcards,
        [Parameter(Mandatory=$true)]
        $out_file
    )

    # Create array
    $updated_regex_arr = @()


    # If there are whitelisted items
    if($whitelist)
    {
        # For each one, format it as regex and add to the array
        foreach($wl_host in $whitelist)
        {
        
            $wl_host          = $wl_host -replace "\.", "\."

            $wl_host_prefix   = "^("
            $wl_host_suffix   = ")$"

            $wl_host          = $wl_host_prefix + $wl_host + $wl_host_suffix

            $updated_regex_arr += $wl_host
        
        }
    }

    # If there are wildcards passed for removal
    if($wildcards)
    {
        # For each one, format it as regex and add to the array

        foreach($wildcard in $wildcards)
        {
        
            $wildcard          = $wildcard -replace '^(\*\.)(.*)', '(.*)(\.$2)' `
                                           -replace '(.*)(\.\*)$', '($1\.)(.*)'

            $wildcard_prefix   = "^("
            $wildcard_suffix   = ")$"

            $wildcard          = $wildcard_prefix + $wildcard + $wildcard_suffix

            $updated_regex_arr += $wildcard
        
        }
    }

    # If the regex removal array has been populated, we need to output it
    if($updated_regex_arr)
    {
        # Sort array and remove duplicates
        $updated_regex_arr = ($updated_regex_arr).ToLower() | Sort-Object -Unique
   
        # Output to file
        $updated_regex_arr = $updated_regex_arr -join "`n"

        [System.IO.File]::WriteAllText($out_file,$updated_regex_arr)
    }

}

Function Regex-Remove
{
    Param
    (
        [Parameter(Mandatory=$true)]
        $local_regex,
        [Parameter(Mandatory=$true)]
        $hosts
    )

    # Loop through each regex and select only non-matching items
    foreach($regex in $local_regex)
    {
        # Single line, multi line, case insensitive
        $regex = "(?sim)$regex"
        
        # Select hosts that do not match regex
        $hosts = $hosts | Select-String $regex -NotMatch
    }

    # Remove MatchInfo after regex removals
    $hosts = $hosts -replace ''

    return $hosts

}

Function Check-Heartbeat
{
    Param
    (
        [Parameter(Mandatory=$true)]
        $hosts,
        [Parameter(Mandatory=$true)]
        $out_file
    )
        
    # Create empty array for NX hosts
    $nx_hosts     = @()

    # NXDOMAIN native error code
    $nx_err_code  = 9003

    # Iterator starting point
    $i            = 1
    $nx           = 1

    # For each host
    foreach($nx_check in $hosts)
    {
        # Output the current progress
        Write-Progress -Activity "Querying Hosts" -status "Query $i of $($hosts.Count)" -percentComplete ($i / $hosts.count*100)
    
        # Try to resolve a DNS name
        try
        {
            Resolve-DnsName $nx_check -Type A -Server 1.1.1.1 -DnsOnly -QuickTimeout -ErrorAction Stop | Out-Null
        }
        # On error
        catch
        {
            # Store error code
            $err_code = $Error[0].Exception.NativeErrorCode

            # If error code matches NXDOMAIN error code
            if($err_code -eq $nx_err_code)
            {
                # Let the user know
                Write-Output "--> NXDOMAIN (#$nx): $nx_check"
            
                # Add to array
                $nx_hosts += $nx_check

                # Iterate
                $nx++
            }
        }
    
        # Iterate
        $i++
    }

    # Remove progress bar
    Write-Progress -Completed -Activity "Querying Hosts"

    # Join array on a new line
    $nx_hosts = $nx_hosts -join "`n"

    # Output the file
    [System.IO.File]::WriteAllText($out_file,$nx_hosts)
}

Function Finalise-Hosts
{
    Param
    (
        [Parameter(Mandatory=$true)]
        $hosts,
        $wildcards,
        $nxhosts
    )

    # If NXDOMAINS have been specified
    if($nxhosts)
    {    
        # Exclude NXDOMAINS
        $hosts    = $hosts | Where {$nxhosts -notcontains $_}
    }

    # Add wildcards to the array after removals
    $hosts        = $hosts += $wildcards

    # Remove duplicates and force lower case
    ($hosts).toLower() | Sort-Object -Unique

}

Function Save-Hosts
{
    Param
    (
        [Parameter(Mandatory=$true)]
        $hosts,
        [Parameter(Mandatory=$true)]
        $out_file
    )
    
    # Join on the new lines

    $hosts     = $hosts -join "`n"

    # Add blank line to the end of the host file

    $hosts += "`n"

    # Output to file

    [System.IO.File]::WriteAllText($out_file,$hosts)
}