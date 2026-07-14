# Connect to Azure
Connect-AzAccount -WarningAction Ignore

# Get all subscriptions
$subscriptions = Get-AzSubscription -WarningAction Ignore

$unusedPrivateEndpoints = @()

foreach ($subscription in $subscriptions) {
    # Set the context to the current subscription
    Set-AzContext -Subscription $subscription.Id -WarningAction Ignore

    Write-Host "Checking subscription: $($subscription.Name)" -ForegroundColor Cyan

    # Get all private endpoints in the subscription
    $privateEndpoints = Get-AzPrivateEndpoint

    foreach ($pe in $privateEndpoints) {
        $isUsed = $false

        # Check if the private endpoint has an associated private link service connection
        if ($null -eq $pe.PrivateLinkServiceConnections -or $pe.PrivateLinkServiceConnections.Count -eq 0) {
            $isUsed = $false
        } else {
            # Check the state of the private link service connection
            $connectionState = $pe.PrivateLinkServiceConnections[0].PrivateLinkServiceConnectionState.Status
            if ($connectionState -ne "Approved" -and $connectionState -ne "Connected") {
                $isUsed = $false
            } else {
                $isUsed = $true
            }
        }

        if (-not $isUsed) {
            $unusedPrivateEndpoints += [PSCustomObject]@{
                SubscriptionName = $subscription.Name
                SubscriptionId = $subscription.Id
                ResourceGroupName = $pe.ResourceGroupName
                Name = $pe.Name
                Location = $pe.Location
                Id = $pe.Id
            }
        }
    }
}

<# Output the results
   Replace `$outputPath` before running to persist results to disk. #>
if ($unusedPrivateEndpoints.Count -gt 0) {
    Write-Host "Found $($unusedPrivateEndpoints.Count) unused private endpoints:" -ForegroundColor Yellow
    $unusedPrivateEndpoints | Format-Table -AutoSize
    
    # Optionally, export to CSV (update the path before running)
    $outputPath = "<file-path>"
    $unusedPrivateEndpoints | Export-Csv -Path $outputPath -NoTypeInformation
    Write-Host "Results exported to $outputPath" -ForegroundColor Green
} else {
    Write-Host "No unused private endpoints found." -ForegroundColor Green
}

# Disconnect from Azure
Disconnect-AzAccount