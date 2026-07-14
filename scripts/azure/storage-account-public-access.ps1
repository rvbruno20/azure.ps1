<#
    .SYNOPSIS
        Audit and remediate storage accounts that allow public network access.

    .DESCRIPTION
        Loads variables from a local `variables.ps1` file (ignored by Git) and
        examines storage accounts in the selected subscription. If public
        network access is enabled it will either disable it (when a private
        endpoint exists) or attempt to create a private endpoint.

    .NOTES
        - Update `$logFile`, `$vnetName`, and `$defaultLocation` before running.
        - `variables.ps1` should contain non-sensitive configuration keys only;
          secrets must be managed securely (Key Vault, automation variables, etc.).
#>

# Calling file with variable values (kept out of source control)
. .\variables.ps1

# Define Error Preference
$ErrorActionPreference = 'Stop'

# Configurable paths and placeholders - replace <file-path> etc. before running
$logFile = "<file-path>"  # e.g. C:\Temp\storage-audit-log.txt

# Convert secret value to a secure string (if using service principal automation).
# Prefer using managed identities or secure stores for automation.
$securePassword = ConvertTo-SecureString $secretValue -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential -ArgumentList $clientID, $securePassword

try {

    # Connect to Azure - interactive or service principal depending on environment
    # For ad-hoc runs, prefer: Connect-AzAccount
    # For automation, a Service Principal or Managed Identity is appropriate.
    Connect-AzAccount -ServicePrincipal -Tenant $tenantID -Credential $credential -ErrorVariable "ErrorLog" -Verbose
    $ErrorLog | Out-File -FilePath $logFile -Append

    # Set Context
    Set-AzContext -Subscription $subscriptionID

    # Retrieve all storage accounts (filter by location if desired)
    # Update the location filter as needed (e.g. "uksouth" -> "<location>")
    $storageAccountList = Get-AzStorageAccount | Where-Object {$_.Location -eq "uksouth"} -Verbose

    #Check if storage account allow public access and if private endpoints are in place
    foreach ($item in $storageAccountList) {
        #Retrive the network settings for storage accounts
        $networkRuleSet = Get-AzStorageAccount -ResourceGroupName $item.ResourceGroupName -Name $item.StorageAccountName

        if ($networkRuleSet.PublicNetworkAccess -eq 'Enabled') {
            Write-Host "Storage Account $($item.StorageAccountName) is allowing Public Access." -BackgroundColor Yellow -ForegroundColor Red
            #Check if private endpoint is in place
            $privateConnection = Get-AzPrivateEndpointConnection -PrivateLinkResourceId $item.Id

            if ($privateConnection) {
                #Public Access allowed and Private Endpoint is in place = Disable Public Access
                Write-Host "PE connection is enabled for storage account $($item.StorageAccountName)." -ForegroundColor Yellow

                Write-Host "#Disabling Public Access#" -ForegroundColor Green
                Set-AzStorageAccount -ResourceGroupName $item.ResourceGroupName -Name $item.StorageAccountName -PublicNetworkAccess Disabled
            }
            else {
                #Public Access allowed and Private Endpoint is not in place = Create Private Endpoint
                Write-Host "PE connection is disabled for storage account $($item.StorageAccountName)."
                Write-Host "#Creating a private endpoint#"

                #Get ResourceID for the storage account
                $resourceID = $item.Id

                # Virtual Network to host the private endpoint - replace placeholders
                $vnet = Get-AzVirtualNetwork -Name "<vnet-name>" -ResourceGroupName "<resource-group>"
                $subnetID = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name "<subnet-name>"

                $pec = @{
                    Name = "$($item.StorageAccountName)-pec"
                    PrivateLinkServiceID = $resourceID
                    GroupID = "blob"
                }

                $privateEndpointConnection = New-AzPrivateLinkServiceConnection @pec -Verbose

                $pe = @{
                    ResourceGroupName = $vnet.ResourceGroupName
                    Name = "$($item.StorageAccountName)-pe"
                    Location = $defaultLocation    # replace with actual location string (e.g. uksouth)
                    Subnet = $subnetID
                    PrivateLinkServiceConnection = $privateEndpointConnection
                }

                New-AzPrivateEndpoint @pe -Verbose
                #Wait for private endpoint to create
                Start-Sleep -Seconds 60
                $privateEndpoint = Get-AzPrivateEndpoint @pe -Verbose
                Write-Host "New Private Endpoint: $($privateEndpoint.Name) has been created on connection storage account name: $($item.StorageAccountName)." -ForegroundColor Green
                

            }                
        }
        elseif ($networkRuleSet.PublicNetworkAccess -eq 'Disabled') {
            #Public Access not allowed
            Write-Host "Storage Account $($item.StorageAccountName) is blocking Public Access." -ForegroundColor Green
            #Check if private endpoint is in place
            $privateConnection = Get-AzPrivateEndpointConnection -PrivateLinkResourceId $item.Id

            if ($privateConnection) {
                #Public Access disabled and Private Endpoint is in place = Not Changes Required
                Write-Host "No changes required for storage account $($item.StorageAccountName)." -ForegroundColor Green
            }
            else {
                #Public Access disabled and Private Endpoint is not in place = Create Private Endpoint
                Write-Host "PE connection is disabled for storage account $($item.StorageAccountName)."
                Write-Host "#Creating a private endpoint#"

                #Get ResourceID for the storage account
                $resourceID = $item.Id

                # Virtual Network to host the private endpoint - replace these values
                $vnet = Get-AzVirtualNetwork -Name "<vnet-name>" -ResourceGroupName "<resource-group>"
                $subnetID = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name "<subnet-name>"

                $pec = @{
                    Name = "$($item.StorageAccountName)-pec"
                    PrivateLinkServiceID = $resourceID
                    #Group ID refers to the type of private link (blob, file, table, etc...)
                    GroupID = "blob"
                }

                $privateEndpointConnection = New-AzPrivateLinkServiceConnection @pec -Verbose

                $pe = @{
                    ResourceGroupName = $vnet.ResourceGroupName
                    Name = "$($item.StorageAccountName)-pe"
                    Location = $defaultLocation
                    Subnet = $subnetID
                    PrivateLinkServiceConnection = $privateEndpointConnection
                }

                New-AzPrivateEndpoint @pe -Verbose
                #Wait for private endpoint to create
                Start-Sleep -Seconds 60
                $privateEndpoint = Get-AzPrivateEndpoint @pe -Verbose
                $privateEndpointIP = $privateEndpoint.NetworkInterfaces

                Write-Host "New Private Endpoint: $($privateEndpoint.Name) `
                has been created on connection storage account name: $($item.StorageAccountName)." -ForegroundColor Green
            
            }

        }

        # Build private DNS zone name based on Group ID (leave as-is or replace $blobType)
        $DNSName = "privatelink.$($blobType).core.windows.net"
        $vnetName = "<vnet-name-to-match>"

        # Get all DNS zones that match the blob type (GroupID)
        $privateDNSZone = Get-AzPrivateDnsZone | Where-Object {$_.Name -match "$($blobType)"}

        foreach ($zone in $privateDNSZone) {
            #Filter to find the on connected to VNUK01.
            $networkLink = Get-AzPrivateDnsVirtualNetworkLink `
            -ResourceGroupName $zone.ResourceGroupName `
            -ZoneName $zone.Name

            #If private DNS zone exists, add record. If private DNS zone doesn't exist, create a PDNSZ and add the record.
            if ($networkLink.VirtualNetworkId -match $vnetName) {
                Write-Output "The private DNS zone $($zone.Name) is linked to $($vnetName)" -ForegroundColor Green
                Write-Output "Writing a new DNS record"

                # TODO: Provide the record set name and resource group before creating DNS records
                # New-AzPrivateDnsRecordSet -Name <record-name> -RecordType A `
                # -ZoneName $zone.Name `
                # -ResourceGroupName <resource-group>
            }
            else {
                Write-Output "The private DNS zone $($zone.Name) is not linked to $($vnetName)" -ForegroundColor Red
                break
            }
        }
    }
}
catch {
    Write-Error $_.Exception.Message | Out-File -FilePath $logFile -Append
    Write-Host "Not able to connect to the Azure Tenant!" -ForegroundColor Red
    break
}
