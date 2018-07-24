Function Fetch-Hosts
{
    Param
    (
        [Parameter(Mandatory)]
        [string[]]
        $host_sources
    )
    
    # SSL Support
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Regex for the downloaded host files
    $hf_regex = "^host_(?:\d{16})\.txt$"

    # Set download directory to %temp%
    $dir      = $env:TEMP

    # Check that the host download directory exists
    # and is not null
    try
    {
        Test-Path $dir | Out-Null
    }
    catch
    {
        Write-Error "Unable to access host download directory"
        return
    }

    # Clear any residual hosts left from early script terminations
    Get-ChildItem $dir | ? {$_.Name -match $hf_regex} | Remove-Item
    
    <# 
        Start processing web sources
    #>
 
    # For each web host source
    $host_sources | % {

        # Status update
        Write-Host "--> $_"
        
        # Define timestamp
        $hf_stamp = Get-Date -Format ddMMyyHHmmssffff
            
        # Define host file name
        $dwn_host = "$dir\host_$hf_stamp.txt"
            
        try
        {
            # Download the host file
            (New-Object System.Net.Webclient).DownloadFile($_, $dwn_host)
        }
        catch
        {
            $PSCmdlet.WriteError($_)
            
            # Jump to next host
            return
        }

        # Read it
        Get-Content $dwn_host | ? {$_}

        # Clear the download
        Remove-Item $dwn_host
    }   
}

Function Extract-Filter-Domains
{
    Param
    (
       [Parameter(Mandatory=$true)]
       [string[]]
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
       [string[]]
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
       [string[]]
       $hosts
    )

    # Regex to match wildcards
    $wildcard_regex = "(?im)(?=^[*]|.*[*]$)^(?:\*[.-]?)?(?:(?!-)[a-z0-9-]+(?:(?<!-)\.)?)+(?:[a-z0-9]+)(?:[.-]?\*)?$"

    # Output valid wildcards
    $hosts | Select-String "(?i)$wildcard_regex" -AllMatches `
           | % {$_.Matches.Value}
}

Function Parse-Hosts
{
    Param
    (
        [Parameter(Mandatory=$true)]
        [string[]]
        $hosts
    )
    
    # Remove local deadzone
    # Remove user comments
    # Remove whitespace
    # Exclude blank lines
    $hosts  -replace '127.0.0.1'`
            -replace '0.0.0.0'`
            -replace '(?:^|[^\S\n]+)#.*$'`
            -replace '\s+'`
            -replace '^(?:\|\|)?www(?:[0-9]{1,3})?(?:\.)'`
            | ? {$_}
}

Function Remove-WhitelistedDomains
{
    Param
    (
        [Parameter(Mandatory=$true)]
        [System.Collections.ArrayList]
        $hosts,
        [Parameter(Mandatory=$true)]
        [string[]]
        $whitelist
    )

    # For each whitelisted item
    $whitelist | % {
        # Remove it from the host array
        while($hosts.Contains($_))
        {
            $hosts.Remove($_)
        }
    }
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
    $hosts |% {Reverse-String $_} `
           | sort `
           | % {$previous_host=$null; $i=0} {
                
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
        [string]
        $wildcard
    )

    # Define replacement pattern for each valid wildcard match
    $replace_pattern =
        Switch -Regex ($wildcard)
        {
            '(?i)^\*[A-Z0-9-_.]+$'
            {
                "^\*([A-Z0-9-_.]+)$", '$1$'
            }
            '(?i)^\*[A-Z0-9-_.]+\*$'
            {
                "^\*([A-Z0-9-_.]+)\*$", '$1'
            }
            '(?i)^[A-Z0-9-_.]+\*$'
            {
                "^([A-Z0-9-_.]+)\*$", '^$1'
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
        [string[]]
        $wildcards,
        [string[]]
        $whitelist
    )
  
    # Convert wildcards to arraylist ready for additions and removals
    $wildcards | % {$wildcard_arr=[System.Collections.ArrayList]::new()}{[void]$wildcard_arr.Add($_)}

    # For each wildcard
    $wildcards | % {

        # Store the wildcard and regex version of wildcard
        $wcard       = $_
        $wcard_regex = Process-Wildcard-Regex $_

        # If the wildcard is whitelisted
        # Remove it from the array list and iterate
        if($whitelist -match $wcard_regex)
        {
            while($wildcard_arr.Contains($_))
            {
                $wildcard_arr.Remove($_);
            }

            return
        }

        # Count matches of wildcard against existing wildcard list
        $wcard_match_count = ($wildcard_arr -match $wcard_regex).Count

        # If there were two or more matches for a given wildcard
        # (We found an un-necessary wildcard)
        if($wcard_match_count -ge 2)
        {
            # Specify our target wildcards for removal
            # Excluding the wildcard we used to match >= 2 results
            $target_wcards = $wildcard_arr | ? {$_ -notcontains $wcard} `
                                                | ? {$_ -match $wcard_regex}
        
            # For each target wildcard
            # While each target wildcard is present, remove it.
            $target_wcards | % {
                while($wildcard_arr.Contains($_))
                {
                    $wildcard_arr.Remove($_);
                }
            }      
        }
    }

    return $wildcard_arr
}

Function Fetch-Regex-Removals
{

    Param
    (
        [Parameter(Mandatory)]
        [string[]]
        $wildcards
    )

    # For each wildcard
    # Fetch the correct regex formatting and add to array
    $wildcards | % {Process-Wildcard-Regex $_}
}

Function Regex-Remove
{
    Param
    (
        [Parameter(Mandatory=$true)]
        [string[]]
        $regex_removals,
        [Parameter(Mandatory=$true)]
        [System.Collections.ArrayList]
        $hosts
    )

    # Loop through each regex and select only non-matching items
    foreach($regex in $regex_removals)
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
}

Function Remove-Host-Clutter
{
    Param
    (
        [Parameter(Mandatory=$true)]
        [string[]]
        $hosts
    )

    # Create duplicate array for removals
    # Convert hosts to arraylist ready for additions and removals
    $hosts | % {$cleaned_hosts=[System.Collections.ArrayList]::new()}{[void]$cleaned_hosts.Add($_)}

    # Reverse each string
    # Sort them again
    # Set initial variables
    $hosts | % {Reverse-String $_} `
           | sort `
           | % {$previous_host=$null} {

            # If this is the first host to process 
            # or the reversed string is not like the previous
            if((!$previous_host) -or ($_ -notlike "$previous_host.*"))
            {
                # Set the current host to this host
                $previous_host = $_
            }
            # else, the host is like the previous
            else
            {
                # Re-reverse the string
                $_ = Reverse-String $_
                
                # Remove it from the hosts array
                while($cleaned_hosts.Contains($_))
                {
                    $cleaned_hosts.Remove($_)
                }
            }
    } 
    
    return $cleaned_hosts
}

Function Check-Heartbeat
{
    Param
    (
        [Parameter(Mandatory=$true)]
        [string[]]
        $hosts,
        [Parameter(Mandatory=$true)]
        [string]
        $out_file
    )
    
    # Create a new StreamWriter for the NXDOMAINS
    $nx_sr           = [System.IO.StreamWriter] $out_file
    
    # Set StreamWriter EOL to \n
    $nx_sr.NewLine   = "`n"
    # Set to output results immediately
    $nx_sr.AutoFlush = $true

    # NXDOMAIN native error code
    $nx_err_code     = 9003

    # Iterator starting point
    $i               = 1
    $nx              = 1

    # Foreach unique host
    $hosts | sort -Unique `
           | % {

            # Store the domain incase we need it
            $nxdomain = $_

            # Output the current progress
            Write-Progress -Activity "Querying Hosts" -status "Query $i of $($hosts.Count)" -percentComplete ($i / $hosts.count*100)
    
            # Try to resolve a DNS name
            try
            {
                Resolve-DnsName $_ -Type A -Server 1.1.1.1 -DnsOnly -QuickTimeout -ErrorAction Stop | Out-Null
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
                    Write-Output "--> NXDOMAIN (#$nx): $nxdomain"
            
                    # Add to array
                    $nx_sr.WriteLine($nxdomain)

                    # Iterate
                    $nx++
                }
            }
    
            # Iterate
            $i++
            }

    # Remove progress bar
    Write-Progress -Completed -Activity "Querying Hosts"

    # Close and dispose the StreamWriter
    $nx_sr.Close()
    $nx_sr.Dispose()
}

Function Reverse-String
{
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]
        $string
    )

    # Convert to Char Array
    [string[]]$string = $string.toCharArray()
        
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
        [System.Collections.ArrayList]
        $hosts,
        [string[]]
        $wildcards,
        [string[]]
        $nxdomains
    )
    
    # Add wildcards
    $wildcards    | ? {$_} | % {[void]$hosts.Add($_)}

    # Remove NXDOMAINS
    $nxdomains    | ? {$_} | % {

        while($hosts.Contains($_))
        {
            $hosts.Remove($_)
        }
    }

    # Force lower case and remove duplicates
    # This will convert to standard array
    $hosts.toLower() | sort -Unique
}

Function Save-Hosts
{
    Param
    (
        [Parameter(Mandatory=$true)]
        [string[]]
        $hosts,
        [Parameter(Mandatory=$true)]
        [string]
        $out_file
    )
    
    # Join on the new lines
    $hosts     = $hosts -join "`n"

    # Add a new line to the end of the file
    $hosts    += "`n"

    # Output to file
    [System.IO.File]::WriteAllText($out_file,$hosts)
}

Function No-Hosts
{
    Write-Output     "--> No hosts detected. Please check your configuration."
    Start-Sleep      -Seconds 5
    exit
}