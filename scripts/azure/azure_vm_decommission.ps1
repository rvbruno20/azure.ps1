<#
.SYNOPSIS
    Decommission an Azure VM and its dependent resources.
.DESCRIPTION
    Authenticates using a service principal, selects the target subscription,
    stops the VM if it is running, deletes the VM, and removes associated
    managed disks and network interfaces.
.NOTES
    Requires the Az PowerShell module.
#>

# ==============================
# Target VM and Azure Context
# ==============================

# Name of the virtual machine to remove.
$virtualMachine = "<vm-name>"

# Subscription name to use for the decommission operation.
$subscriptionName = "<subscription-name>"

# Arrays used to track dependent resources for later deletion.
$nicToDelete = @()
$diskToDelete = @()

# ==============================
# Service Principal Credentials
# ==============================

# Application (client) ID for the Azure service principal.
$applicationID = "<application-id>"

# Tenant ID where the service principal exists.
$tenantID = "<tenant-id>"

# Service principal secret used for authentication.
$secretValue = "<secret-value>"

# Slack webhook URL to send status notifications.
$SlackWebhookURL = "<slack-webhook-url>"

# ==============================
# PowerShell Execution Preferences
# ==============================

# Stop execution on any error and suppress progress output.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ==============================
# Notification Helper
# ==============================

function Send-SlackMessage ($Message) {
    $body = @{ text = $Message } | ConvertTo-Json
    Invoke-RestMethod -Uri $SlackWebhookURL -Method Post -Body $body -ContentType "application/json" | Out-Null
}

# ==============================
# Main Decommission Flow
# ==============================

try {
    Write-Output "Authenticating with Entra using Service Principal..."

    $secureSecret = ConvertTo-SecureString $secretValue -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential($applicationID, $secureSecret)

    # Sign in using service principal credentials.
    Connect-AzAccount -Tenant $tenantID -ServicePrincipal -Credential $Credential | Out-Null
    Write-Output "Authentication Successful."

    Write-Output "Changing context to subscription '$subscriptionName'..."
    Set-AzContext -Subscription $subscriptionName | Out-Null

    # Confirm the subscription context to ensure actions run in the correct tenant.
    $confirmContext = Get-AzContext
    if ($confirmContext.Subscription.Name -eq $subscriptionName) {
        Write-Output "Context set to subscription: $($confirmContext.Subscription.Name)"
    } else {
        Write-Output "Unable to authenticate to the subscription: $subscriptionName"
        Write-Output "Exiting the script..."
        Exit 1
    }

    # ==============================
    # Retrieve VM and power state
    # ==============================

    $vm = Get-AzVM | Where-Object { $_.Name -eq $virtualMachine }
    $vmStatus = Get-AzVM -ResourceId $vm.Id -Status

    # Stop the VM if it is currently running.
    if ($vmStatus -like "*running*") {
        Write-Output "Virtual Machine $($vm.Name) is running... stopping it now..."
        Stop-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Force | Out-Null
        Write-Output "Virtual Machine $($vm.Name) is now stopped."
    } else {
        Write-Output "Virtual Machine $($vm.Name) is already stopped."
    }

    # ==============================
    # Determine disks to delete
    # ==============================

    # Always delete the OS disk and also delete any attached data disks.
    $diskToDelete += $vm.StorageProfile.OsDisk.Name
    $dataDiskObject = $vm.StorageProfile.DataDisks

    if ($dataDiskObject.Count -eq 0) {
        Write-Output "No data disks attached to $($vm.Name)."
    } else {
        Write-Output "Data disks were found for $($vm.Name)."
        foreach ($disk in $dataDiskObject) {
            $diskToDelete += $disk.Name
        }
    }
    Write-Output "All disks have been accounted for."

    # ==============================
    # Determine network interfaces to delete
    # ==============================

    $networkInterfaces = $vm.NetworkProfile.NetworkInterfaces
    if ($networkInterfaces) {
        foreach ($nic in $networkInterfaces) {
            $nicName = ($nic.Id -split '/')[-1]
            $nicToDelete += $nicName
        }
        Write-Output "All network interfaces have been accounted for."
    } else {
        Write-Output "No network interfaces were found on this VM."
    }

    # ==============================
    # Delete the VM
    # ==============================

    Write-Output "Deleting VM $($vm.Name)..."
    $vm | Remove-AzVM -Force | Out-Null

    $vm = Get-AzVM | Where-Object { $_.Name -eq $virtualMachine }
    if ($null -ne $vm) {
        Write-Output "VM was not deleted successfully. Please complete this action manually in the portal."
        exit 1
    } else {
        Write-Output "Virtual Machine '$($virtualMachine)' deleted successfully!"
        $message = "Virtual Machine - *$($virtualMachine)* - deleted successfully!"
        Send-SlackMessage ":success: *### NOTIFICATION ###* :success:`n$($message)"
    }

    # ==============================
    # Delete dependent network interfaces
    # ==============================

    foreach ($nic in $nicToDelete) {
        $resourceToDelete = Get-AzNetworkInterface | Where-Object { $_.Name -eq $nic }
        if ($resourceToDelete) {
            Write-Output "Network interface $($resourceToDelete.Name) found... deleting now..."
            $resourceToDelete | Remove-AzNetworkInterface -Force | Out-Null
        } else {
            Write-Output "Network interface '$nic' has already been deleted."
        }
    }

    # ==============================
    # Delete dependent disks
    # ==============================

    foreach ($disk in $diskToDelete) {
        $resourceToDelete = Get-AzDisk | Where-Object { $_.Name -match $disk }
        if ($resourceToDelete) {
            Write-Output "Disk $($resourceToDelete.Name) found... deleting now..."
            $resourceToDelete | Remove-AzDisk -Force | Out-Null
        } else {
            Write-Output "Disk '$disk' has already been deleted."
        }
    }

    # ==============================
    # Clean up and exit
    # ==============================

    Write-Output "Disconnecting from Azure..."
    Disconnect-AzAccount | Out-Null
    Write-Output "Script has finished running."
}
catch {
    Write-Output "Script failed."
    Write-Output "Error: $($_.Exception.Message)"
}