<#
    .SYNOPSIS
        Create Private Endpoints for storage accounts listed in a CSV.

    .DESCRIPTION
        Reads a CSV with storage account names and resource groups, then
        creates private endpoints and private link service connections. Replace
        placeholders before running.
#>

# CSV containing Name, ResourceGroup columns
$list = Import-Csv -Path "<file-path>"

# Authenticate interactively (or use service principal for automation)
Connect-AzAccount

# Create private endpoints
foreach ($item in $list) {
    #Details
    $storageAccountName = $item.Name
    $storageAccountRGName = $item.ResourceGroup

    #Get Storage Account
    $storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRGName

    #Create Private Link Connection
    #Parameters
    $privateLink = @{
        Name = "$($item.name)-link"
        PrivateLinkServiceID = $storageAccount.Id
        GroupID = "blob"
    }

    $privateEndpointConnection = New-AzPrivateLinkServiceConnection @privateLink

    # Virtual network and subnet to host the private endpoint - replace placeholders
    $vnet = Get-AzVirtualNetwork -Name '<vnet-name>' -ResourceGroupName '<vnet-resource-group>'
    $subnet = $vnet | Select-Object -ExpandProperty Subnets | Where-Object {$_.Name -eq "<subnet-name>"}

    $privateEndpoint = @{
        Name = "$($item.Name)-pe"
        ResourceGroup = "<pe-resource-group>"
        Location = "<location>"
        Subnet = $subnet
        PrivateLinkServiceConnection = $privateEndpointConnection
    }

    $endpoint = New-AzPrivateEndpoint @privateEndpoint
}