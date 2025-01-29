# Load required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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

# Create reverse DNS lookup table
$reverseDnsLookup = @{}
foreach ($entry in $dnsOptions.GetEnumerator()) {
    $key = $entry.Value -join ','
    $reverseDnsLookup[$key] = $entry.Key
}

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "DNS Configuration Tool"
$form.Size = New-Object System.Drawing.Size(410, 330)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# Create a label for DNS options
$labelDNS = New-Object System.Windows.Forms.Label
$labelDNS.Text = "Select a DNS Option:"
$labelDNS.Location = New-Object System.Drawing.Point(20, 20)
$labelDNS.AutoSize = $true
$form.Controls.Add($labelDNS)

# Create a combo box for DNS options
$comboDNS = New-Object System.Windows.Forms.ComboBox
$comboDNS.Location = New-Object System.Drawing.Point(20, 50)
$comboDNS.Size = New-Object System.Drawing.Size(250, 30)
$comboDNS.DropDownStyle = "DropDownList"
$dnsOptions.GetEnumerator() | ForEach-Object { $comboDNS.Items.Add($_.Key) }
$comboDNS.SelectedIndex = 0
$form.Controls.Add($comboDNS)

# Create a label for network interfaces
$labelInterfaces = New-Object System.Windows.Forms.Label
$labelInterfaces.Text = "Select Network Interface(s):"
$labelInterfaces.Location = New-Object System.Drawing.Point(20, 100)
$labelInterfaces.AutoSize = $true
$form.Controls.Add($labelInterfaces)

# Create a list box for network interfaces (including broadband)
$listInterfaces = New-Object System.Windows.Forms.ListBox
$listInterfaces.Location = New-Object System.Drawing.Point(20, 130)
$listInterfaces.Size = New-Object System.Drawing.Size(250, 150)
$listInterfaces.SelectionMode = "MultiExtended"

# Get all active interfaces including broadband connections
$interfaces = @()
Get-NetIPInterface | Where-Object {
    ($_.ConnectionState -eq 'Connected') -or 
    ($_.InterfaceType -eq 23)  # 23 = PPP (Point-to-Point Protocol)
} | ForEach-Object {
    $adapter = Get-NetAdapter -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue
    $interfaces += [PSCustomObject]@{
        Index = $_.ifIndex
        Name = if ($adapter) { $adapter.Name } else { "Broadband Connection" }
        Type = $_.InterfaceType
    }
}

$interfaces | Sort-Object Index -Unique | ForEach-Object { 
    $listInterfaces.Items.Add("$($_.Name) (Index: $($_.Index))") 
}
$form.Controls.Add($listInterfaces)

# Create a button to set DNS
$buttonSetDNS = New-Object System.Windows.Forms.Button
$buttonSetDNS.Text = "Set DNS"
$buttonSetDNS.Location = New-Object System.Drawing.Point(280, 50)
$buttonSetDNS.Size = New-Object System.Drawing.Size(100, 30)
$buttonSetDNS.Add_Click({
    $selectedDNS = $comboDNS.SelectedItem
    $selectedInterfaces = $listInterfaces.SelectedItems | ForEach-Object { ($_ -split 'Index: ')[1].TrimEnd(')') }
    $dnsServers = $dnsOptions[$selectedDNS]

    foreach ($index in $selectedInterfaces) {
        Set-DnsClientServerAddress -InterfaceIndex $index -ServerAddresses $dnsServers
        [System.Windows.Forms.MessageBox]::Show("DNS has been set to $selectedDNS ($($dnsServers -join ', ')) on InterfaceIndex $index.", "Success")
    }
})
$form.Controls.Add($buttonSetDNS)

# Create a button to unset DNS
$buttonUnsetDNS = New-Object System.Windows.Forms.Button
$buttonUnsetDNS.Text = "Unset DNS"
$buttonUnsetDNS.Location = New-Object System.Drawing.Point(280, 100)
$buttonUnsetDNS.Size = New-Object System.Drawing.Size(100, 30)
$buttonUnsetDNS.Add_Click({
    $selectedInterfaces = $listInterfaces.SelectedItems | ForEach-Object { ($_ -split 'Index: ')[1].TrimEnd(')') }

    foreach ($index in $selectedInterfaces) {
        Set-DnsClientServerAddress -InterfaceIndex $index -ResetServerAddresses
        [System.Windows.Forms.MessageBox]::Show("DNS settings have been cleared on InterfaceIndex $index. Reverted to DHCP.", "Success")
    }
})
$form.Controls.Add($buttonUnsetDNS)

# Create a button to show DNS settings with broadband support
$buttonShowDNS = New-Object System.Windows.Forms.Button
$buttonShowDNS.Text = "Show DNS"
$buttonShowDNS.Location = New-Object System.Drawing.Point(280, 150)
$buttonShowDNS.Size = New-Object System.Drawing.Size(100, 30)
$buttonShowDNS.Add_Click({
    $output = "Current DNS Settings:`n`n"
    
    # Get all active interfaces including broadband
    $allInterfaces = @()
    Get-NetIPInterface | Where-Object {
        ($_.ConnectionState -eq 'Connected') -or 
        ($_.InterfaceType -eq 23)  # PPP interfaces
    } | ForEach-Object {
        $adapter = Get-NetAdapter -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue
        $allInterfaces += [PSCustomObject]@{
            Index = $_.ifIndex
            Name = if ($adapter) { $adapter.Name } else { "Broadband Connection" }
            Type = $_.InterfaceType
        }
    }

    foreach ($interface in $allInterfaces | Sort-Object Index -Unique) {
        try {
            $dnsSettings = Get-DnsClientServerAddress -InterfaceIndex $interface.Index -AddressFamily IPv4 -ErrorAction Stop
            $output += "Interface: $($interface.Name) (Index: $($interface.Index))`n"
            
            if ($dnsSettings.ServerAddresses) {
                $addressString = $dnsSettings.ServerAddresses -join ','
                $dnsName = $reverseDnsLookup[$addressString]
                
                $output += if ($dnsName) {
                    "DNS Servers: $dnsName ($addressString)`n`n"
                } else {
                    "DNS Servers: $($dnsSettings.ServerAddresses -join ', ')`n`n"
                }
            }
            else {
                $output += "DNS Servers: None (DHCP)`n`n"
            }
        }
        catch {
            $output += "Interface: $($interface.Name) (Index: $($interface.Index))`n"
            $output += "DNS Servers: [Error reading settings]`n`n"
        }
    }

    [System.Windows.Forms.MessageBox]::Show($output, "DNS Settings")
})
$form.Controls.Add($buttonShowDNS)

# Show the form
$form.Add_Shown({ $form.Activate() })
[void] $form.ShowDialog()