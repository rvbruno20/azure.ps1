<#
.SYNOPSIS
    Register an Azure Virtual Desktop session host.
.DESCRIPTION
    Connects to the specified session host over WinRM, installs the required AVD
    agent packages, and uses the provided registration token to enroll the host.
.NOTES
    This script must run from a device that can communicate with the session
    host over WinRM. The remote host must be reachable by name or IP and must
    allow remote PowerShell connections.
#>

# Parameters
param(
    [Parameter(Mandatory=$true)]
    [string]$vmName,

    [Parameter(Mandatory=$true)]
    [string]$registrationToken
)

# ==============================
# Remote connection credentials
# ==============================

# Local administrator credentials used to connect to the remote session host.
# Replace these placeholders with the actual account credentials prior to use.
$username = "<local-admin-username>"
$password = "<local-admin-password>"

# Secure the password before creating the PSCredential object.
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

Write-Output "Connecting to session host '$vmName' to install AVD agents..."

Invoke-Command -ComputerName $vmName -Credential $credential -ArgumentList $registrationToken -ScriptBlock {
    param(
        [string]$registrationToken
    )

    # ==============================
    # Prepare working directory on remote host
    # ==============================
    $workingDirectory = "C:\Scripts"

    if (-not (Test-Path -Path $workingDirectory)) {
        Write-Output "Working directory not found. Creating $workingDirectory..."
        New-Item -Type Directory -Path $workingDirectory | Out-Null
    } else {
        Write-Output "Working directory already exists: $workingDirectory"
    }

    Set-Location $workingDirectory

    # ==============================
    # Remove any existing AVD agent artifacts
    # ==============================
    $checkItem = Get-ChildItem -Path $workingDirectory -Name "*rd*" -Recurse -Force

    if ($checkItem.Count -gt 0) {
        Write-Output "Removing old agent artifacts from the working directory..."
        $checkItem | Remove-Item -Recurse -Force
    } else {
        Write-Output "No old agent artifacts found in the working directory."
    }

    # ==============================
    # Download AVD agent installers
    # ==============================
    $uris = @(
        "https://go.microsoft.com/fwlink/?linkid=2310011",
        "https://go.microsoft.com/fwlink/?linkid=2311028"
    )

    $installers = @()
    foreach ($uri in $uris) {
        Write-Output "Resolving download URL for $uri..."
        $expandedUri = (Invoke-WebRequest -MaximumRedirection 0 -UseBasicParsing -Uri $uri -ErrorAction SilentlyContinue).Headers.Location
        $fileName = ($expandedUri).Split('/')[-1]

        Write-Output "Downloading $fileName..."
        Invoke-WebRequest -Uri $expandedUri -UseBasicParsing -OutFile $fileName
        $installers += $fileName
    }

    foreach ($installer in $installers) {
        Write-Output "Unblocking downloaded installer: $installer"
        Unblock-File -Path $installer
    }

    Write-Host "`nDownloaded installer files:`n"
    $installers

    # ==============================
    # Install AVD agent packages
    # ==============================
    Write-Output "Installing AVD agent package..."
    msiexec.exe /i "$($installers[0])" /passive REGISTRATIONTOKEN=$registrationToken

    Start-Sleep -Seconds 120

    Write-Output "Installing AVD supporting package..."
    msiexec.exe /i "$($installers[1])" /passive

    Start-Sleep -Seconds 120

    # ==============================
    # Verify installation and service state
    # ==============================
    $expectedPackageCount = 4
    do {
        $packages = Get-Package | Where-Object { $_.Name -like "*Remote Desktop*" }
    } while ($packages.Count -ne $expectedPackageCount)

    $rdAgentName = "RDAgentBootLoader"
    $service = Get-Service -Name $rdAgentName -ErrorAction SilentlyContinue

    if ($null -eq $service) {
        Write-Output "Error: AVD service '$rdAgentName' was not found after installation."
        throw "Service not found."
    }

    if ($service.Status -eq "Running") {
        Write-Output "Service [$($service.DisplayName)] is running. Restarting the host to finalize installation."
        Restart-Computer -Force
    }
    elseif ($service.Status -ne "Running") {
        Write-Output "Service [$($service.DisplayName)] is not running. Attempting to restart the service..."
        Restart-Service -InputObject $service

        $service = Get-Service -Name $rdAgentName
        if ($service.Status -ne 'Running') {
            Write-Output "Service restart failed for '$rdAgentName'."
            throw "Unable to restart service."
        }
    }
}
