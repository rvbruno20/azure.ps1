<#
.SYNOPSIS
    Create an emergency isolation NSG and apply it to all VMs in each subscription.
.DESCRIPTION
    Logs in to Azure, iterates through all subscriptions the signed-in user can access,
    creates an isolation NSG in each subscription, attaches it to each VM network interface,
    and restarts the VMs to apply the changes.
.NOTES
    This script makes broad changes across subscriptions and will affect VM connectivity.
    Use with caution and validate the target environment before execution.
#>

# ==================================================
# CONFIGURATION
# ==================================================

# DryRun toggles whether the script only outputs planned changes or performs them.
$DryRun = $true   # TRUE = output only | FALSE = execute changes

# NSG rule names and common description used for emergency isolation.
$InboundRuleName  = "Deny-All-Inbound-Emergency"
$OutboundRuleName = "Deny-All-Outbound-Emergency"
$RuleDescription  = "Emergency deny-all rule"

# ==================================================
# AUTHENTICATION
# ==================================================

# Authenticate interactively using the current user context.
Connect-AzAccount

# Get all subscriptions accessible to the signed-in identity.
$Subscriptions = Get-AzSubscription

foreach ($Sub in $Subscriptions) {
    $NSGName = "Isolation-$($Sub.Name)"
    $ResourceGroupName = "Isolation-RG-$($Sub.Name)"
    $Location = "westeurope"

    Write-Host "`n=============================================="
    Write-Host "Subscription: $($Sub.Name)"
    Write-Host "=============================================="

    Set-AzContext -SubscriptionId $Sub.Id | Out-Null

    # Create or update the resource group and NSG used for isolation.
    if ($DryRun) {
        Write-Host "[DryRun] Create resource group: $ResourceGroupName in $Location"
        Write-Host "[DryRun] Create NSG: $NSGName"
    } else {
        New-AzResourceGroup -ResourceGroupName $ResourceGroupName -Location $Location | Out-Null
        New-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $ResourceGroupName -Location $Location | Out-Null
    }

    $NSG = Get-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $ResourceGroupName

    # Add deny-all inbound and outbound rules to the NSG.
    if ($DryRun) {
        Write-Host "[DryRun] Adding inbound deny-all rule: $InboundRuleName"
        Write-Host "[DryRun] Adding outbound deny-all rule: $OutboundRuleName"
    } else {
        $NSG | Add-AzNetworkSecurityRuleConfig `
            -Name $InboundRuleName `
            -Description $RuleDescription `
            -Access Deny `
            -Protocol "*" `
            -Direction Inbound `
            -Priority 100 `
            -SourceAddressPrefix "*" `
            -SourcePortRange "*" `
            -DestinationAddressPrefix "*" `
            -DestinationPortRange "*" | Out-Null

        $NSG | Add-AzNetworkSecurityRuleConfig `
            -Name $OutboundRuleName `
            -Description $RuleDescription `
            -Access Deny `
            -Protocol "*" `
            -Direction Outbound `
            -Priority 100 `
            -SourceAddressPrefix "*" `
            -SourcePortRange "*" `
            -DestinationAddressPrefix "*" `
            -DestinationPortRange "*" | Out-Null
    }

    # Apply the NSG to all virtual machine network interfaces in the subscription.
    $virtualMachines = Get-AzVM
    foreach ($vm in $virtualMachines) {
        $NetworkInterfaceName = $vm.NetworkProfile.NetworkInterfaces[0].Id.Split("/")[-1]
        $nic = Get-AzNetworkInterface -Name $NetworkInterfaceName -ResourceGroupName $vm.ResourceGroupName

        if ($DryRun) {
            Write-Host "[DryRun] Updating NIC $($nic.Name) to use NSG $NSGName"
        } else {
            # Remove any existing NSG assignment, then assign the emergency isolation NSG.
            if ($nic.NetworkSecurityGroup) {
                Write-Host "Removing existing NSG from NIC $($nic.Name)..."
                $nic.NetworkSecurityGroup = $null
                $nic | Set-AzNetworkInterface | Out-Null
            }

            $nic = Get-AzNetworkInterface -Name $NetworkInterfaceName -ResourceGroupName $vm.ResourceGroupName
            $nic.NetworkSecurityGroup = $NSG
            $nic | Set-AzNetworkInterface | Out-Null

            Write-Host "Stopping VM $($vm.Name) to apply NSG changes..."
            Stop-AzVM -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Force | Out-Null
        }
    }

    foreach ($vm in $virtualMachines) {
        if ($DryRun) {
            Write-Host "[DryRun] Starting VM $($vm.Name)"
        } else {
            Write-Host "Starting VM $($vm.Name)..."
            Start-AzVM -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName | Out-Null
        }
    }
}

