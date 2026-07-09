# Connect to Azure using the current signed-in identity.
Connect-AzAccount

# Inspect the active Azure context and subscription.
$context = Get-AzContext

# Configuration values for the target VM and desired size.
$subscriptionName = "<subscription-name>"
$virtualMachineName = "<virtual-machine-name>"
$newVMSize = "<new-vm-size>"

# Ensure the correct subscription is selected before making changes.
if ($context.Subscription.Name -ne $subscriptionName) {
    Set-AzContext -Subscription $subscriptionName | Out-Null
    $context = Get-AzContext
}

# Retrieve the VM details and status once.
$vm = Get-AzVM -Name $virtualMachineName -Status -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Warning "VM '$virtualMachineName' was not found in subscription '$subscriptionName'."
    exit 1
}

# Determine the current power state from the retrieved VM object.
$powerState = $vm.PowerState

# Deallocate the VM before resizing if it is currently running.
if ($powerState -like '*running*') {
    Write-Output "Deallocating Azure VM '$($vm.Name)' before resizing."
    Stop-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Force -ErrorAction Stop | Out-Null
}

# Reload the VM model and update the size.
$vmToUpdate = Get-AzVM -Name $virtualMachineName -ResourceGroupName $vm.ResourceGroupName -ErrorAction Stop
$vmToUpdate.HardwareProfile.VmSize = $newVMSize

# Apply the VM size change.
Update-AzVM -ResourceGroupName $vm.ResourceGroupName -VM $vmToUpdate -ErrorAction Stop

# Start the VM after the resize completes.
Start-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $virtualMachineName -ErrorAction Stop | Out-Null
Write-Output "Resize completed for VM '$virtualMachineName'. New size: $newVMSize"