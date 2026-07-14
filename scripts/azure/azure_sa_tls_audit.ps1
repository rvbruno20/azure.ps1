#Initial Banner
Write-Host "`n"
Write-Host "                    -------------------------------------------------            " -ForegroundColor DarkBlue
Write-Host "                    |                                               |            " -ForegroundColor DarkBlue
Write-Host "                    |             Storage Account TLS Audit         |            " -ForegroundColor DarkBlue
Write-Host "                    |                                               |            " -ForegroundColor DarkBlue
Write-Host "                    -------------------------------------------------            " -ForegroundColor DarkBlue
Write-Host "`n"

<#
    .SYNOPSIS
        Ensure storage accounts use TLS 1.2 minimum.

    .DESCRIPTION
        Iterates subscriptions and storage accounts listed in a CSV, then
        enforces TLS 1.2 as the minimum TLS version for each storage account.
#>

# Connect to Azure
Connect-AzAccount -WarningAction Ignore

# Subscription names to check - replace placeholders
$subscriptionName = @(
    "<subscription-name>"
)

# Extract the list of storage accounts from a CSV (one storage account name per line)
$storageAccount = Get-Content -Path "<file-path>"

#Change storare account settings
foreach ($sub in $subscriptionName) {
   Write-Host "Connecting to $($sub)." -ForegroundColor Green
   Set-AzContext -SubscriptionName $sub -WarningAction Ignore

   foreach ($storage in $storageAccount) {
    $object = Get-AzStorageAccount | Where-Object {$_.StorageAccountName -eq $storage}
    if ($object) {
        Write-Host "Storage account $($storage) present in $($sub)"

        if ($object.MinimumTlsVersion -eq "TLS1_2") {
            Write-Host "Storage account $($storage) does not need to be updated! Skipping..." -ForegroundColor Blue
        }
        if ($object.MinimumTlsVersion -ne "TLS1_2") {
            Write-Warning "Storage account $($storage) need to be updated! Making the change now..."
            $object | Set-AzStorageAccount -MinimumTlsVersion TLS1_2
            Write-Host "Storage account $($storage) updated successfully! Moving to the next..." -ForegroundColor Green
        }
    }else {
        Write-Host "Storage account $($storage) not present in $($sub). Trying on the next run..." -ForegroundColor Red
    }
   }
}