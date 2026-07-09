# Connect using the managed identity of the host (VM/VMSS/Automation)
Connect-AzAccount

# Current context (subscription, tenant)
$context = Get-AzContext

# Map: subscriptionName -> array of VM names
$subscriptionName = "<subscription-name>"
$virtualMachineName = "<virtual-machine-name>"

# Desired VM size
$newVMSize = "<new-vm-size>"

# Ensure we are in the correct subscription by name
if ($context.Subscription.Name -ne $subscriptionName) {
    Set-AzContext -Subscription $subscriptionName | Out-Null
    $context = Get-AzContext
}

# Get VM including status info
$vm = Get-AzVM -Name $virtualMachineName -Status -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Warning "VM '$virtualMachineName' not found in subscription '$subscriptionName'. Skipping."
    exit 1
}

# Determine current power state (Code like 'PowerState/running' or 'PowerState/deallocated')
$powerState = (Get-AzVM -Name $virtualMachineName -Status -ErrorAction SilentlyContinue).PowerState

# If running, deallocate first (required to change size)
if ($powerState -like '*running*') {
    Write-Output "Stopping (deallocating) Azure VM - $($vm.Name)"
    Stop-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Force -ErrorAction Stop | Out-Null

}

# Reload VM model (fresh) and set new size
$vmToUpdate = Get-AzVM -Name $virtualMachineName -ResourceGroupName $vm.ResourceGroupName -ErrorAction Stop
$vmToUpdate.HardwareProfile.VmSize = $newVMSize

# Apply the change
Update-AzVM -ResourceGroupName $vm.ResourceGroupName -VM $vmToUpdate -ErrorAction Stop

# Start the VM after resize
Start-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $virtualMachineName -ErrorAction Stop | Out-Null
Write-Output "Resize and restart complete for VM - $($virtualMachineName) (New size: $newVMSize)"