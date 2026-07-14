<#
    .SYNOPSIS
        Audit public IP addresses across subscriptions.

    .DESCRIPTION
        Connects to Azure interactively, enumerates subscriptions, and lists public
        IP addresses. Removes organization-specific filters and writes results to
        a configurable output path.

    .NOTES
        - Replace the `Export-Csv` path below with a safe output path before running,
          or update the `$outputPath` variable.
        - Uses `Connect-AzAccount` (interactive) so run this on a system with
          an authenticated Az module and network access to Azure.
#>

try {
    Connect-AzAccount -WarningAction Ignore

    #Get all Subs IDs (no org-specific filtering)
    $subscriptions = Get-AzSubscription -WarningAction Ignore | Where-Object {$_.State -eq "Enabled"}

    # Configurable output path - change from <file-path> to a real path before running
    $outputPath = "<file-path>"

    foreach ($sub in $subscriptions) {

        #Set subscription
        Set-AzContext -Subscription $sub.Id -WarningAction Ignore

        Write-Host "Connected to $($sub.Name)..." -ForegroundColor Blue

        #Get all public IPs
        $publicIps = Get-AzPublicIpAddress

        if ($null -ne $publicIps) {
            Write-Host "Public IP Addresses found..." -ForegroundColor Cyan
            foreach ($ip in $publicIps) {

                if ($null -ne $ip.IpConfiguration) {
                    Write-Warning "$($ip.Name) is associated! Do not remove..."
                    $status = "Associated"
                }else{
                    Write-Host "$($ip.Name) is not associated! Please review and remove IPs if not needed..." -ForegroundColor Green
                    $status = "Not Associated"
                }

                $data = [PSCustomObject]@{
                    Name = $ip.Name;
                    ResourceGroup = $ip.ResourceGroupName;
                    Subscription = $sub.Name;
                    IP = $ip.IpAddress
                    Status = $status
                }

                #Adding IPs to a csv file (replace $outputPath before running)
                $data | Export-Csv -Path $outputPath -Append -NoTypeInformation
        }
        }else{
            Write-Warning "No public IPs found on $($sub.Name)"
        }
    }
}
catch {
    Write-Error "$($_.Exception.Message) at $(Get-Date)"
    exit 1
}