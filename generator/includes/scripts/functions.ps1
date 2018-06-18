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
    
    # Create empty hosts array
    $hosts    = @()

    # Regex for the downloaded host files
    $hf_regex = "^((host_)(\d{16})(\.txt))$"

    # If the host download directory exists, clear it out.
    # Otherwise create a fresh directory
    if(Test-Path $dir)
    {
        Get-ChildItem $dir | Where {$_.Name -match $hf_regex} | Remove-Item | Out-Null
    }
    else
    {
        try
        {
            New-Item -ItemType Directory -Path $dir | Out-Null
            $host_dir_created = $true
        }
        catch
        {
            Write-Error "Unable to create host download directory. Web hosts unavailable."
                      
            $w_host_files = $null
        }
           
    }
    
    # WEB
    if($w_host_files)
    {
        foreach($host_file in $w_host_files)
        {
            # Define timestamp
            $hf_stamp = Get-Date -Format ddMMyyHHmmssffff
            
            # Define host file name
            $dwn_host = "$dir\host_$hf_stamp.txt"

            # Status update
            Write-Host "--> W: $host_file"
            
            try
            {
                # Download the host file
                (New-Object System.Net.Webclient).DownloadFile($host_file, $dwn_host)
            }
            catch
            {
                Write-Error "Unable to download: $host_file"
                # Jump to next host
                continue
            }

            # Read it
            $WHL = (Get-Content $dwn_host) | Where {$_}

            # Parse it
            $WHL =  Parse-Hosts $WHL

            # Add hosts to array
            $hosts += $WHL
        }

        # If we had to create a directory, Remove it.
        if($host_dir_created)
        {
            Remove-Item $dir -Recurse | Out-Null
        }
        # Else, just purge the hosts
        else
        {
            Get-ChildItem $dir | Where {$_.Name -match $hf_regex} | Remove-Item | Out-Null
        }
    }

    # LOCAL
    if($l_host_files)
    {
        foreach($host_file in $l_host_files)
        {
           # Status update
           Write-Host "--> L: $host_file"
           
           # Read it
           $LHL = (Get-Content $host_file) | Where {$_}

           # Parse it
           $LHL = Parse-Hosts $LHL

           # Add non-wildcard hosts to  array
           $hosts += $LHL
        }
    }    

    return $hosts
}

Function Extract-Filter-Domains
{
    Param
    (
       [Parameter(Mandatory=$true)]
       $hosts 
    )

    # Regex to match domains within a filter list
    $filter_regex   = "(?=.{4,253}\^)((?<=^[|]{2})(((?!-)[a-z0-9-]{1,63}(?<!-)\.)+[a-z]{2,63})(?=\^([$]third-party)?$))"

    # Output valid domains
    $hosts | Select-String "(?i)$filter_regex" -AllMatches `
           | % {$_.Matches.Value}

}

Function Parse-Hosts
{
    Param
    (
        [Parameter(Mandatory=$true)]
        $hosts
    )

    # Define regex for matching hosts
    $domain_regex   = "(?=^.{4,253}$)(^((?!-)[a-z0-9-]{1,63}(?<!-)\.)+[a-z]{2,63}$)"
    $wildcard_regex = "^([\*])([A-Z0-9-_.]+)$|^([A-Z0-9-_.]+)([\*])$|^([\*])([A-Z0-9-_.]+)([\*])$"
 
    # Remove local end-zone
    $hosts          = $hosts -replace '127.0.0.1'`
                             -replace '0.0.0.0'
    # Remove whitespace
    $hosts          = $hosts.Trim()

    # Remove user comments
    $hosts          = $hosts -replace '(#.*)|((\s)+#.*)'

    # Remove blank lines
    $hosts          = $hosts | Where {$_}

    # Try to match a filter list
    $filter_list    = Extract-Filter-Domains $hosts

    # If we are processing a filter list
    if($filter_list)
    {
        # Only capture compatible hosts
        $hosts = $filter_list
    }
    # Otherwise, process as a normal host file
    else
    {
        # Only select 'valid' URLs
        $hosts          = $hosts | Select-String '(?i)(localhost)' -NotMatch `
                                 | % {$_.Line} `
                                 | Select-String "(?i)$domain_regex|$wildcard_regex" -AllMatches `
                                 | % {$_.Matches.Value}
    }

    
    # Remove www prefixes
    $hosts          = $hosts -replace '^(www)([0-9]{0,3})?(\.)'
    
    # Remove duplicates and force lower case
    ($hosts).toLower() | Sort-Object -Unique
   
}

Function Process-Wildcard-Regex
{
    Param
    (
        [Parameter(Mandatory=$true)]
        $wildcard
    )

    # Define replacement pattern for each valid wildcard match
    Switch -Regex ($wildcard)
            {
                '(?i)^((\*)([A-Z0-9-_.]+))$'
                {
                    $replace_pattern = "^(([*])([A-Z0-9-_.]+))$", '($3)$'
                }
                '(?i)^((\*)([A-Z0-9-_.]+)(\*))$'
                {
                    $replace_pattern = "^(([*])([A-Z0-9-_.]+)([*]))$", '($3)'
                }
                '(?i)^(([A-Z0-9-_.]+)(\*))$'
                {
                    $replace_pattern = "^(([A-Z0-9-_.]+)([*]))$", '^($2)'
                }
                # No regex match
                Default
                {
                    # Output error and exit function
                    Write-Error "$wildcard is not a valid wildcard."
                    return
                }
            }
      
    
    $wildcard -replace $replace_pattern `
              -replace "\.", "\." `
              -replace "\*", ".*" 
                  
}

Function Remove-Conflicting-Wildcards
{
    Param
    (
        [Parameter(Mandatory=$true)]
        $wildcards,
        [Parameter(Mandatory=$true)]
        $whitelist
    )

    
    $wildcards | foreach {
                            # Get the regexed version of the wildcard
                            $regex_wildcard = Process-Wildcard-Regex  $_

                            # If it doesn't match against any item(s) in the whitelist, output it
                            if(!($whitelist -match $regex_wildcard))
                            {
                                $_
                            }
                          }
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
            # if the whitelisted item is a wildcard
            if($wl_host -match "\*")
            {
                # Fetch the correct regex replace criteria
                # Mainly for formatting
                $wl_host = Process-Wildcard-Regex $wl_host

            }
            # Otherwise, process as a standard domain
            else
            {
                $wl_host          = $wl_host -replace "\.", "\."
            }

            $updated_regex_arr += "^($wl_host)$"
        
        }
    }

    # If there are wildcards passed for removal
    if($wildcards)
    {
        # For each one, format it as regex and add to the array
        foreach($wildcard in $wildcards)
        {
            # Fetch the correct regex replace criteria
            # Mainly for formatting
            $wildcard = Process-Wildcard-Regex $wildcard

            # Skip if there is a match with a whitelist item
            # or the whitelisted item will be inaccessible
            if($whitelist -match $wildcard)
            {
                continue
            }

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
        $regex = "(?i)$regex"
        
        # Select hosts that do not match regex
        $hosts = $hosts -notmatch $regex
    }

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
        
    # Remove duplicates before processing
    $hosts        = $hosts | Sort-Object -Unique
    
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

Function Reverse-String
{
    Param
    (
        [Parameter(Mandatory=$true)]
        $string
    )

    # Convert to Char Array
    $string = $string.toCharArray()
        
    # Reverse the characters
    [Array]::Reverse($string)

    # Join the characters back together
    -join $string 
}

Function Remove-Host-Clutter
{
    Param
    (
        [Parameter(Mandatory=$true)]
        $hosts
    )
    
   
    # Create empty array to store the reversed hosts
    $reversed_hosts    = @()

    # Reverse the hosts and sort to clump them together
    $reversed_hosts    += $hosts | ForEach-Object {Reverse-String -string $_} `
                                 | Sort-Object

    # Set the current host to null
    $current_host      = $null

    # Foreach reversed host
    foreach($reverse in $reversed_hosts)
    {    
        # If this is the first host to process, or the reversed string is not like the previous
        if((!$current_host) -or ($reverse -notlike "$current_host.*"))
        {
            # Output the reversed host
            Reverse-String $reverse
            # Set the current host to this host
            $current_host = $reverse
        }

        # Skip to the next
    }
    
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