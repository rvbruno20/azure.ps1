<#
.SYNOPSIS
    Stops a list of Azure virtual machines.
.DESCRIPTION
    This script is intended for Azure Automation Accounts and stops a set of virtual machines across one or more subscriptions using the managed identity.
#>

# ==============================
# Configuration
# ==============================

$VirtualMachineList = [ordered]@{
    "<subscription-name>" = @("<virtual-machine-name-1>", "<virtual-machine-name-2>")
}

# ==============================
# Script preferences
# ==============================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ==============================
# Main execution
# ==============================

try {
    # Authenticate to Azure using the Automation Account managed identity.
    Write-Output "Authenticating with Managed Identity..."
    Connect-AzAccount -Identity | Out-Null
    Write-Output "Authentication successful."

    foreach ($sub in $VirtualMachineList.Keys) {

        $confirmContext = Get-AzContext
        if ($confirmContext.Subscription.Name -ne $sub) {
            # Switch context to the subscription that contains the VMs for this iteration.
            Write-Output "Switching context to subscription '$sub'..."
            Set-AzContext -Subscription $sub | Out-Null
        }

        Write-Output "Active subscription: $($confirmContext.Subscription.Name)"

        foreach ($server in $VirtualMachineList[$sub]) {
            # Look up the VM directly by name in the current subscription.
            Write-Output "Stopping VM '$server'..."
            $virtualMachineObject = Get-AzVM -Name $server -ErrorAction SilentlyContinue

            if ($virtualMachineObject) {
                Write-Output "VM '$($virtualMachineObject.Name)' found. Stopping it now..."
                Stop-AzVM -ResourceGroupName $virtualMachineObject.ResourceGroupName -Name $virtualMachineObject.Name -Force | Out-Null

                # Give the VM a moment to transition to the stopped state before checking.
                Start-Sleep -Seconds 15

                $virtualMachineStatus = (Get-AzVM -Name $server -Status -ErrorAction SilentlyContinue).PowerState

                if ($virtualMachineStatus -like "*stopped*" -or $virtualMachineStatus -like "*deallocated*") {
                    Write-Output "VM '$($virtualMachineObject.Name)' is stopped or deallocated."
                }
                else {
                    Write-Output "VM '$($virtualMachineObject.Name)' is still running."
                    Write-Output "Please review the Azure portal if the VM does not stop successfully."
                }
            }
            else {
                Write-Output "VM '$server' was not found in subscription '$sub'."
                Write-Output "Please review the subscription mapping and confirm the VM exists."
            }
        }
    }
}
catch {
    Write-Output "The script failed while stopping one or more virtual machines."
    Write-Output "Error: $($_.Exception.Message)"
}

# ==============================
# Finalize script
# ==============================

Write-Output "Disconnecting from Azure."
Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null

Write-Output "Script completed."