
param (
    [bool]$DryRun = $false
)

# ==============================
# CONFIGURATION
# ==============================
$Subscription = "<subscription-name>"

$VmResizePlan = @(
    @{
        ResourceGroup = "<resource-group-name>"
        VMName        = "<vm-name>"
        TargetSize    = "<target-size>"
    }
)

Write-Output "=== Azure VM Resize Script (Interactive Login) ==="
Write-Output "             DryRun mode: $DryRun"
Write-Output "=================================================="

# ==============================
# AUTHENTICATION
# ==============================
Connect-AzAccount -Identity
Write-Output "Setting Subscription"
Set-AzContext -Subscription $Subscription

# ==============================
# PROCESS EACH VM
# ==============================
foreach ($vmPlan in $VmResizePlan) {

    Write-Output "---------------------------------------------"
    Write-Output "VM Name        : $($vmPlan.VMName)"
    Write-Output "Resource Group : $($vmPlan.ResourceGroup)"
    Write-Output "Target Size    : $($vmPlan.TargetSize)"
    Write-Output "---------------------------------------------"

    $vm = Get-AzVM `
        -ResourceGroupName $vmPlan.ResourceGroup `
        -Name $vmPlan.VMName `
        -Status

    $currentSize = $vm.HardwareProfile.VmSize
    $powerState  = $vm.PowerState

    Write-Output "Current Size   : $currentSize"
    Write-Output "Power State    : $powerState"

    if ($currentSize -eq $vmPlan.TargetSize) {
        Write-Output "VM already at desired size. Skipping."
        continue
    }

    if ($DryRun) {
        Write-Output "[DRY-RUN] VM would be stopped (if running)"
        Write-Output "[DRY-RUN] VM would be resized to $($vmPlan.TargetSize)"
        Write-Output "[DRY-RUN] VM would be started again"
        continue
    }

    if ($powerState -ne "VM deallocated") {
        Write-Output "Stopping VM..."
        Stop-AzVM `
            -ResourceGroupName $vmPlan.ResourceGroup `
            -Name $vmPlan.VMName `
            -Force
    }

    Write-Output "Resizing VM..."
    $vm.HardwareProfile.VmSize = $vmPlan.TargetSize
    Update-AzVM `
        -ResourceGroupName $vmPlan.ResourceGroup `
        -VM $vm

    Write-Output "Starting VM..."
    Start-AzVM `
        -ResourceGroupName $vmPlan.ResourceGroup `
        -Name $vmPlan.VMName
}

Write-Output ""
Write-Output "=== Script completed ==="
