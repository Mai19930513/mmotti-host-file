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
    $hosts    = New-Object System.Collections.ArrayList

    # Regex for the downloaded host files
    $hf_regex = "^host_(?:\d){16}\.txt$"

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

    # If there are web host files
    if($w_host_files)
    {
        # For each one
        $web_host_files | % {
            # Define timestamp
            $hf_stamp = Get-Date -Format ddMMyyHHmmssffff
            
            # Define host file name
            $dwn_host = "$dir\host_$hf_stamp.txt"

            # Status update
            Write-Host "--> W: $_"
            
            try
            {
                # Download the host file
                (New-Object System.Net.Webclient).DownloadFile($_, $dwn_host)
            }
            catch
            {
                Write-Error "Unable to download: $_"
                # Jump to next host
                continue
            }

            # Read it
            $WHL = (Get-Content $dwn_host) | Where {$_}

            # Parse it
            $WHL = Parse-Hosts $WHL

            # Add hosts to array
            $WHL | % {[void]$hosts.Add($_)}
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
   

    # If there are local host files (incl. blacklist)
    if($l_host_files)
    {
        $l_host_files | % {
           # Status update
           Write-Host "--> L: $_"
           
           # Read it
           $LHL = (Get-Content $_) | Where {$_}

           # Parse it
           $LHL = Parse-Hosts $LHL

           # Add non-wildcard hosts to  array
           $LHL | % {[void]$hosts.Add($_)}
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

    # Set valid type options
    $filter_type    = "important|third-party|popup|subdocument|websocket"
       
    # Regex to match domains within a filter list
    $filter_regex   = "(?=.{4,253}\^)((?<=^[|]{2})(((?!-)[a-z0-9-]{1,63}(?<!-)\.)+[a-z]{2,63})(?=\^(?:[$](?:$filter_type))?$))"

    # Output valid filter domains
    $hosts | Select-String "(?i)$filter_regex" -AllMatches `
           | % {$_.Matches.Value}

}

Function Extract-Domains
{
    Param
    (
       [Parameter(Mandatory=$true)]
       $hosts
    )

    # Regex to match standard domains
    $domain_regex   = "(?=^.{4,253}$)(^((?!-)[a-z0-9-]{1,63}(?<!-)\.)+[a-z]{2,63}$)"

    # Output valid domains
    $hosts | Select-String '(?i)(localhost)' -NotMatch `
           | % {$_.Line} `
           | Select-String "(?i)$domain_regex" -AllMatches `
           | % {$_.Matches.Value}
}

Function Extract-Wildcards
{
    Param
    (
       [Parameter(Mandatory=$true)]
       $hosts
    )

    # Regex to match wildcards
    $wildcard_regex = "^\*([A-Z0-9-_.]+)$|^([A-Z0-9-_.]+)\*$|^\*([A-Z0-9-_.]+)\*$"

    # Output valid wildcards
    $hosts | Select-String "(?i)$wildcard_regex" -AllMatches `
           | % {$_.Matches.Value}
}

Function Parse-Hosts
{
    Param
    (
        [Parameter(Mandatory=$true)]
        $hosts
    )
 
    # Remove local end-zone
    $hosts          = $hosts -replace '127.0.0.1'`
                             -replace '0.0.0.0'

    # Remove user comments
    $hosts          = $hosts -replace '\s*(?:#.*)$'

    # Remove whitespace
    $hosts          = $hosts.Trim()

    # Check for filter lists
    $filter_list    = Extract-Filter-Domains $hosts

    if($filter_list)
    {
        $hosts = $filter_list
    }
    else
    {
        $hosts = Extract-Domains $hosts
    }

    # Remove WWW prefix
    $hosts          = $hosts -replace "^www(?:[0-9]{1,3})?(?:\.)"
      
    # Output lower case hosts
    $hosts.ToLower() | Where {$_}
   
}

<#
Function Identify-Wildcard-Prefixes
{
    Param
    (
        [Parameter(Mandatory=$true)]
        $hosts,
        $whitelist,
        [Parameter(Mandatory=$true)]
        [int] $prefix_determination_count
    )

    # Here we are looking to shrink down the host file
    # Adhell3 will no longer add a * prefix, so we can't just discard any matching items anymore
    # Instead, we'll check for repeating instances to work out which domains we could add a * prefix to
    # This needs to be ran near the start of the script so we have all the new wildcards prior to the regex removal

    # Reverse each string
    # Sort them again
    # Set initial variables
    $hosts | foreach {Reverse-String $_} `
           | Sort-Object `
           | foreach {$previous_host=$null; $i=0} {
                
                # Re-reverse string
                $re_reverse = Reverse-String $_
                # Prepare regex
                $re_regex   = "($re_reverse)$" -replace "\.", "\." 

                # If there's no previous host (first iteration)
                # Or there is a match against the whitelist       
                if((!$previous_host) -or ($whitelist -match $re_regex))
                {
                    # Set the current host as the previous
                    $previous_host = $_
                    # Jump to next iteration
                    return
                }
    
                # If the current iteration is like our comparison criteria
                if($_ -like "$previous_host.*")
                {
                    # Increment counter
                    $i++
                    # Jump to next iteration
                    return
                }
                # Else if we are dealing with a new host
                else
                {       
                    # If there were more than x matches
                    if($i -ge $prefix_determination_count)
                    {                
                        # Output a wildcard
                        Write-Output "*$(Reverse-String $previous_host)"
                    }
           
                    # Set the previous host as the current
                    $previous_host = $_

                    # Reset the increment 
                    $i = 0;       
                }

           }
}
#>

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
                '(?i)^\*[A-Z0-9-_.]+$'
                {
                    $replace_pattern = "^\*([A-Z0-9-_.]+)$", '$1$'
                }
                '(?i)^\*[A-Z0-9-_.]+\*$'
                {
                     $replace_pattern = "^\*([A-Z0-9-_.]+)\*$", '$1'
                }
                '(?i)^[A-Z0-9-_.]+\*$'
                {
                    $replace_pattern ="^([A-Z0-9-_.]+)\*$", '^$1'
                }

                # No regex match
                Default
                {
                    # Output error and exit function
                    Write-Error "$wildcard is not a valid wildcard."
                    return
                }
            }
      
    
    $wildcard -replace $replace_pattern -replace "\.", "\."
                  
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
  
    # Create empty array
    $wildcard_arr_list = New-Object System.Collections.ArrayList

    # Add existing wildcards to the array list
    $wildcards         | % {[void]$wildcard_arr_list.Add($_)}

    # For each wildcard
    $wildcards         | % {
        
        # Store the wildcard and regex version of wildcard
        $wcard       = $_
        $wcard_regex = Process-Wildcard-Regex $_

        # If the wildcard is whitelisted
        # Remove it from the array list and iterate
        if($whitelist -match $wcard_regex)
        {
            $wildcard_arr_list.Remove($_)
            return
        }

        # If there were more than two matches for a given wildcard
        # (We found an un-necessary wildcard)
        if(($wildcards -match $wcard_regex).Count -ge 2)
        {
            # Specify our target wildcards for removal
            # Excluding the wildcard we used to match >= 2 results
            $target_wcards = $wildcard_arr_list | ? {$_ -notcontains $wcard} `
                                                | ? {$_ -match $wcard_regex}
        
            # For each target wildcard
            # While each target wildcard is present, remove it.
            $target_wcards | % {
                while($wildcard_arr_list.Contains($_))
                {
                    $wildcard_arr_list.Remove($_);
                }
            }      
        }
    }

    return $wildcard_arr_list 
}

Function Fetch-Regex-Removals
{

    Param
    (
        $whitelist,
        $wildcards
    )

    # Removals (whitelisted) items should be added to the regex remove array
    # Something.com -> Remove exactly Something.com
    # *Something.com -> Remove anything that ends in Something.com
    

    # For each whitelisted domain
    $whitelist | foreach {
                    
        # If the whitelisted item is a wildcard
        if($_ -match "\*")
        {
            # Fetch the correct regex replace formatting
            Process-Wildcard-Regex $_
        }
        else
        # Otherwise, process as a standard domain
        {
            $_ = $_ -replace "\.", "\."
            Write-Output "^$_$"
        }
    }

    # For each wildcard
    $wildcards | foreach {
        # Fetch the correct regex formatting and add to array
        # Wildcards have been checked against whitelist in Remove-Conflicting-Wildcards
        Process-Wildcard-Regex $_
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
        # Case insensitive
        $regex = "(?i)$regex"

        # Select hosts that do not match regex
        $hosts -match $regex | % {
            while($hosts.Contains($_))
            {
                $hosts.Remove($_)
            }
        }
    }

    return $hosts
}

Function Remove-Host-Clutter
{
    Param
    (
        [Parameter(Mandatory=$true)]
        $hosts
    )
    
    # Reverse each string
    # Sort them again
    # Set initial variables
    $hosts | foreach {Reverse-String $_} `
           | Sort-Object `
           | foreach {$previous_host=$null} {

            # If this is the first host to process, or the reversed string is not like the previous
            if((!$previous_host) -or ($_ -notlike "$previous_host.*"))
            {
                # Output the reversed host
                Reverse-String $_
                # Set the current host to this host
                $previous_host = $_
            }

            # Skip to the next

    } 
}
<#
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
#>

<#

Function Remove-WWW
{
    Param
    (
        [Parameter(Mandatory=$true)]
        $hosts
    )
   
    # Define the WWW regex
    # Match at least two periods to ensure we are wildcarding properly.
    $www_regex   = "^www(?:[0-9]{1,3})?(?:\.[^.\s]+){2,}"
    $www_replace = "^www(?:[0-9]{1,3})?(?:\.)"

    # Fetch WWW hosts
    # Remove the prefix
    # Create an array and add *something.com to it
    $hosts | Where {$_ -match $www_regex} `
           | foreach {$_ -replace $www_replace} `
           | foreach {$www_arr=@()}{$www_arr += "*$_"}

    
    # Replace all www prefixes
    # Remove hosts that are about to be added as wildcards
    $hosts = $hosts | where {$_ -notmatch $www_regex} `
                    | where {$www_arr -notcontains "*$_"}

    # Add our prefixed (ex WWW) domains back
    $hosts + $www_arr   
}

#>

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

Function Finalise-Hosts
{
    Param
    (
        [Parameter(Mandatory=$true)]
        $hosts,
        $wildcards,
        $nxhosts
    )

    # Remove the WWW domains and replace with *something.com
    #$hosts        = Remove-WWW $hosts
    
    # Add wildcards to the array after removals
    $hosts        = $hosts + $wildcards

    # Select Unique hosts
    $hosts        = $hosts | Sort-Object -Unique

    # Re-create ArrayList from hosts
    $hosts        | % {$hosts = [System.Collections.ArrayList]@()} {[void]$hosts.add($_)}
    
    # For each NXHOST
    $nxhosts      | % {
        
                    # Remove the preceeding * and/or .
                    $_ = $_ -replace "^\*" -replace "^\."

                    # Remove matches from array
                    while($hosts.Contains($_))
                    {
                        $hosts.Remove($_)
                    }   
    }  
    
    # Return lower case hosts
    $hosts.toLower()
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