# Check if the script is running as administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script must be run as administrator. Please restart PowerShell as an administrator and try again." -ForegroundColor Red
    exit
}

# Define DNS options
$dnsOptions = @{
    "SHEKAN"       = @("178.22.122.100", "185.51.200.2")
    "403ONLINE"    = @("10.202.10.202", "10.202.10.102")
    "ELECTRO"      = @("78.157.42.101", "78.157.42.100")
    "BEGZAR"       = @("185.55.226.26", "185.55.225.25")
    "RADAR"        = @("10.202.10.10", "10.202.10.11")
    "SHELTER"      = @("94.103.125.157", "94.103.125.158")
    "BESHKAN"      = @("181.41.194.177", "181.41.194.186")
    "PISHGAMAN"    = @("5.202.100.100", "5.202.100.101")
    "SHATEL"       = @("85.15.1.14", "85.15.1.15")
    "LEVEL3"       = @("209.244.0.3", "209.244.0.4")
    "CLOUDFLARE"   = @("1.1.1.1", "1.0.0.1")
}

# Function to test DNS performance using HTTP status code
function Test-DNSWithHTTP {
    param (
        [string]$website
    )
    $results = @()
    $totalDNSOptions = $dnsOptions.Count
    $currentDNSOption = 0

    foreach ($dns in $dnsOptions.GetEnumerator()) {
        $currentDNSOption++
        $dnsName = $dns.Key
        $dnsServers = $dns.Value
        $httpResults = @()

        # Update progress bar
        $percentComplete = [math]::Round(($currentDNSOption / $totalDNSOptions) * 100)
        Write-Progress -Activity "Testing DNS Options" -Status "Testing $dnsName ($currentDNSOption of $totalDNSOptions)" -PercentComplete $percentComplete

        foreach ($server in $dnsServers) {
            try {
                # Temporarily set DNS for testing
                Set-DnsClientServerAddress -InterfaceIndex 5 -ServerAddresses $server
                Start-Sleep -Seconds 2 # Wait for DNS to take effect

                # Make HTTP request and check status code
                $response = Invoke-WebRequest -Uri "http://$website" -UseBasicParsing -ErrorAction Stop
                $statusCode = $response.StatusCode
                $httpResults += [PSCustomObject]@{
                    DNS       = $server
                    Status    = $statusCode
                    Result    = if ($statusCode -eq 200) { "Success" } else { "Failed ($statusCode)" }
                }
            } catch {
                $httpResults += [PSCustomObject]@{
                    DNS       = $server
                    Status    = "Error"
                    Result    = "Failed (No Response)"
                }
            }
        }
        $results += [PSCustomObject]@{
            DNSName   = $dnsName
            DNSServers = $dnsServers -join ', '
            HTTPResults = $httpResults
        }
    }
    # Reset DNS to DHCP after testing
    Set-DnsClientServerAddress -InterfaceIndex 5 -ResetServerAddresses
    return $results
}

# Function to show DNS settings on all up interfaces
function Show-DNSOnUpInterfaces {
    Write-Host "`nCurrent DNS Settings on Up Interfaces:"
    $upInterfaces = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

    if ($upInterfaces.Count -eq 0) {
        Write-Host "No active (up) network interfaces found." -ForegroundColor Yellow
        return
    }

    foreach ($interface in $upInterfaces) {
        $dnsSettings = Get-DnsClientServerAddress -InterfaceIndex $interface.InterfaceIndex -AddressFamily IPv4
        Write-Host "`nInterface: $($interface.Name) (Index: $($interface.InterfaceIndex))"
        if ($dnsSettings.ServerAddresses) {
            Write-Host "DNS Servers: $($dnsSettings.ServerAddresses -join ', ')"
        } else {
            Write-Host "DNS Servers: None (DHCP)"
        }
    }
}

# Main script
Write-Host "DNS Configuration Script"
Write-Host "------------------------"

# Display menu
Write-Host "`nSelect an option:"
Write-Host "1: Set one of the predefined DNSs"
Write-Host "2: Test all DNSs for a specific URL"
Write-Host "3: Unset DNS and revert to automatic (DHCP) allocation"
Write-Host "4: Show DNS settings on all up interfaces"
$choice = Read-Host "`nEnter your choice (1, 2, 3, or 4):"

switch ($choice) {
    1 {
        # Option 1: Set one of the predefined DNSs
        Write-Host "`nAvailable DNS Options:"

        # Display DNS options in a table with order numbers
        $dnsOptions.GetEnumerator() | ForEach-Object -Begin { $i = 1 } -Process {
            [PSCustomObject]@{
                Order = $i
                Name  = $_.Key
                DNS   = $_.Value -join ', '
            }
            $i++
        } | Format-Table -AutoSize

        # Ask user to select by order number or name
        $selectedOption = Read-Host "`nEnter the order number or name of the DNS option you want to use:"

        # Validate user input
        if ($selectedOption -match "^\d+$") {
            # User entered a number
            $selectedIndex = [int]$selectedOption - 1
            $selectedDNS = $dnsOptions.Keys[$selectedIndex]
            if ($selectedDNS) {
                $dnsServers = $dnsOptions[$selectedDNS]
            } else {
                Write-Host "Invalid order number. Please run the script again and choose a valid option."
                exit
            }
        } else {
            # User entered a name
            if ($dnsOptions.ContainsKey($selectedOption)) {
                $selectedDNS = $selectedOption
                $dnsServers = $dnsOptions[$selectedDNS]
            } else {
                Write-Host "Invalid DNS name. Please run the script again and choose a valid option."
                exit
            }
        }

        # Display all network interfaces
        Write-Host "`nAvailable Network Interfaces:"
        $interfaces = Get-NetAdapter | Select-Object Name, InterfaceIndex, Status
        $interfaces | Format-Table -AutoSize

        # Ask user to select one or more interfaces
        $selectedInterfaces = Read-Host "`nEnter the InterfaceIndex(es) to apply DNS (comma-separated):"
        $interfaceIndexes = $selectedInterfaces -split ',' | ForEach-Object { $_.Trim() }

        # Apply DNS to selected interfaces
        foreach ($index in $interfaceIndexes) {
            if ($interfaces.InterfaceIndex -contains $index) {
                # Ensure $dnsServers is passed as an array of strings
                Set-DnsClientServerAddress -InterfaceIndex $index -ServerAddresses $dnsServers
                Write-Host "DNS has been set to $selectedDNS ($($dnsServers -join ', ')) on InterfaceIndex $index."
            } else {
                Write-Host "Invalid InterfaceIndex: $index. Skipping..."
            }
        }
    }
    2 {
        # Option 2: Test all DNSs for a specific URL
        $website = Read-Host "Enter a website to test DNS performance (e.g., google.com):"
        Write-Host "Testing all DNS options for $website..."
        $testResults = Test-DNSWithHTTP -website $website

        # Clear progress bar
        Write-Progress -Activity "Testing DNS Options" -Completed

        # Display results
        Write-Host "`nDNS Test Results:"
        $testResults | ForEach-Object {
            Write-Host "`nDNS Option: $($_.DNSName)"
            Write-Host "DNS Servers: $($_.DNSServers)"
            $_.HTTPResults | Format-Table -AutoSize
        }
    }
    3 {
        # Option 3: Unset DNS and revert to DHCP
        # Display all network interfaces
        Write-Host "`nAvailable Network Interfaces:"
        $interfaces = Get-NetAdapter | Select-Object Name, InterfaceIndex, Status
        $interfaces | Format-Table -AutoSize

        # Ask user to select one or more interfaces
        $selectedInterfaces = Read-Host "`nEnter the InterfaceIndex(es) to reset DNS (comma-separated):"
        $interfaceIndexes = $selectedInterfaces -split ',' | ForEach-Object { $_.Trim() }

        # Reset DNS to DHCP on selected interfaces
        foreach ($index in $interfaceIndexes) {
            if ($interfaces.InterfaceIndex -contains $index) {
                Set-DnsClientServerAddress -InterfaceIndex $index -ResetServerAddresses
                Write-Host "DNS settings have been cleared on InterfaceIndex $index. Reverted to DHCP."
            } else {
                Write-Host "Invalid InterfaceIndex: $index. Skipping..."
            }
        }
    }
    4 {
        # Option 4: Show DNS settings on all up interfaces
        Show-DNSOnUpInterfaces
    }
    default {
        Write-Host "Invalid choice. Please run the script again and select a valid option (1, 2, 3, or 4)."
    }
}