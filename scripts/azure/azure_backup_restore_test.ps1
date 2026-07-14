<#
.SYNOPSIS
    Validates an Azure VM backup and restore workflow.
.DESCRIPTION
    This script authenticates to Azure, restores a virtual machine from Azure Backup, and removes the temporary restore resources afterward.
#>

# ==============================
# Configuration
# ==============================

$virtualMachineName = "<virtual-machine-name>"
$vaultName = "<vault-name>"
$vaultResourceGroup = "<vault-resource-group>"
$Type = "AzureVM"
$storageAccountName = "<storage-account-name>"
$storageAccountRG = "<storage-account-rg>"
$destinationRG = "<destination-rg>"
$location = "<location>"
$subscriptionName = "<subscription-name>"

# ==============================
# Authentication settings
# ==============================

$applicationID = "<application-id>"
$tenantID = "<tenant-id>"
$secretValue = "<secret-value>"

# ==============================
# Script preferences
# ==============================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ==============================
# Slack notification helper
# ==============================

$SlackWebhookURL = "<slack-webhook-url>"
function Send-SlackMessage {
    param([Parameter(Mandatory = $true)][string]$Message)

    $body = @{ text = $Message } | ConvertTo-Json
    Invoke-RestMethod -Uri $SlackWebhookURL -Method Post -Body $body -ContentType "application/json" | Out-Null
}

# ==============================
# Main execution
# ==============================

try {
    # Authenticate to Azure so the script can manage backup and restore resources.
    Write-Output "Authenticating with Microsoft Entra ID using the service principal."

    $secureSecret = ConvertTo-SecureString $secretValue -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential($applicationID, $secureSecret)

    Connect-AzAccount -Tenant $tenantID -ServicePrincipal -Credential $Credential | Out-Null

    Write-Output "Switching context to subscription '$subscriptionName'."
    Set-AzContext -Subscription $subscriptionName | Out-Null

    $confirmContext = Get-AzContext
    if ($confirmContext.Subscription.Name -eq $subscriptionName) {
        Write-Output "Authentication successful. Active subscription: $($confirmContext.Subscription.Name)"
    }
    else {
        Write-Output "Unable to authenticate to subscription '$subscriptionName'."
        Write-Output "Exiting the script."
        Exit 1
    }

    # ==============================
    # Prepare temporary restore resources
    # ==============================

    New-AzResourceGroup -Name $destinationRG -Location $location | Out-Null
    $destinationRGObject = Get-AzResourceGroup -Name $destinationRG

    if ($destinationRGObject) {
        Write-Output "Resource group [$($destinationRGObject.ResourceGroupName)] was created successfully."
    }
    else {
        Write-Output "Resource group [$destinationRG] was not found. Stopping the script."
        exit 1
    }

    New-AzResourceGroup -Name $storageAccountRG -Location $location | Out-Null
    $restoreStorageAccountObject = Get-AzResourceGroup -Name $storageAccountRG

    if ($restoreStorageAccountObject) {
        Write-Output "Resource group [$($restoreStorageAccountObject.ResourceGroupName)] was created successfully."
    }
    else {
        Write-Output "Resource group [$storageAccountRG] was not found. Stopping the script."
        exit 1
    }

    # Create the temporary storage account used for the restore operation.
    New-AzStorageAccount `
        -ResourceGroupName $restoreStorageAccountObject.ResourceGroupName `
        -Name $storageAccountName `
        -Location $location `
        -SkuName Standard_LRS `
        -Kind StorageV2 `
        -AccessTier Hot `
        -EnableHttpsTrafficOnly $true `
        -MinimumTlsVersion TLS1_2 | Out-Null

    $storageAccount = Get-AzStorageAccount -StorageAccountName $storageAccountName -ResourceGroupName $restoreStorageAccountObject.ResourceGroupName

    if ($storageAccount) {
        Write-Output "Storage account [$($storageAccount.StorageAccountName)] was created successfully."
    }
    else {
        Write-Output "Storage account [$storageAccountName] was not found. Stopping the script."
        exit 1
    }

    # ==============================
    # Restore the VM from Recovery Services
    # ==============================

    # Locate the Recovery Services vault that contains the backup data for the target VM.
    $targetVault = Get-AzRecoveryServicesVault -ResourceGroupName $vaultResourceGroup -Name $vaultName

    if ($null -eq $targetVault) {
        Write-Output "Recovery Services vault [$vaultName] was not found. Stopping the script."
        exit 1
    }
    else {
        Write-Output "Recovery Services vault [$($targetVault.Name)] was found. Starting the restore workflow."

        Set-AzRecoveryServicesVaultContext -Vault $targetVault

        $namedContainer = Get-AzRecoveryServicesBackupContainer -ContainerType $Type `
            -FriendlyName $virtualMachineName `
            -VaultId $targetVault.ID

        $backupItem = Get-AzRecoveryServicesBackupItem -Container $namedContainer `
            -WorkloadType $Type `
            -VaultId $targetVault.ID

        $date = Get-Date
        $recoveryPoint = Get-AzRecoveryServicesBackupRecoveryPoint -Item $backupItem `
            -StartDate $date.AddDays(-7).ToUniversalTime() `
            -EndDate $date.ToUniversalTime() `
            -VaultId $targetVault.ID

        # Use the most recent recovery point within the last 7 days for the restore operation.
        $recoveryPointObjective = $recoveryPoint[0]

        # Start the restore job and wait for it to complete before proceeding.
        $restoreJob = Restore-AzRecoveryServicesBackupItem -RecoveryPoint $recoveryPointObjective `
            -StorageAccountName $storageAccount.StorageAccountName `
            -StorageAccountResourceGroupName $storageAccount.ResourceGroupName `
            -TargetResourceGroupName $destinationRGObject.ResourceGroupName `
            -VaultId $targetVault.ID

        Wait-AzRecoveryServicesBackupJob -Job $restoreJob -Timeout 43200

        $jobStatus = Get-AzRecoveryServicesBackupJob -Job $restoreJob -VaultId $targetVault.ID
        $details = Get-AzRecoveryServicesBackupJobDetail -Job $jobStatus -VaultId $targetVault.ID

        $manageDisks = Get-AzResource -ResourceGroupName $destinationRGObject.ResourceGroupName | Select-Object ResourceType
        $status = $manageDisks[0]

        if ($status -match "Microsoft.Compute/disks") {
            Write-Output "Backup job completed successfully."
            $message = "*[NBSE-Automation]* - Monthly Backup Test has completed successfully."
            Send-SlackMessage $message
        }
        else {
            $message = "*[NBSE-Automation]* - Monthly Backup Test has failed"
            Send-SlackMessage $message
        }
    }

    # ==============================
    # Clean up temporary restore resources
    # ==============================

    # Remove the temporary storage account and resource group created for the restore test.
    Write-Output "Removing storage account: $($storageAccount.StorageAccountName)"
    Remove-AzStorageAccount -StorageAccountName $storageAccount.StorageAccountName -ResourceGroupName $storageAccount.ResourceGroupName -Force | Out-Null

    Write-Output "Removing resource group: $($restoreStorageAccountObject.ResourceGroupName)"
    Remove-AzResourceGroup -ResourceGroupName $restoreStorageAccountObject.ResourceGroupName -Force | Out-Null

    # Remove any managed disks and the destination resource group created during the restore.
    $manageDisks = Get-AzResource -ResourceGroupName $destinationRGObject.ResourceGroupName

    if ($manageDisks) {
        foreach ($disk in $manageDisks) {
            Write-Output "Removing managed disk: $($disk.Name)"
            Remove-AzResource -ResourceID $disk.ID -Force | Out-Null
        }

        Write-Output "Removing resource group: $($destinationRGObject.ResourceGroupName)"
        Remove-AzResourceGroup -ResourceGroupName $destinationRGObject.ResourceGroupName -Force | Out-Null
    }
    else {
        Write-Output "No resources were found inside resource group [$($destinationRGObject.ResourceGroupName)]."
    }
}
catch {
    Write-Output "Authentication or restore workflow failed."
    Write-Output "Error: $($_.Exception.Message)"
}

# ==============================
# Finalize script
# ==============================

Write-Output "Disconnecting from Azure."
Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null

Write-Output "Script completed."