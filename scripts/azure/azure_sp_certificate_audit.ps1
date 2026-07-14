<#
.SYNOPSIS
    Audits app registrations for expiring or expired certificates.
.DESCRIPTION
    This script connects to Microsoft Graph, reviews application registrations for certificate expiry, and sends Slack alerts when issues are found.
#>

# ==============================
# Configuration
# ==============================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$tenantID = "<tenant-id>"
$clientID = "<client-id>"
$secretValue = "<secret-value>"
$SlackWebhookURL = "<slack-webhook-url>"
$DayThreshold = 30

# ==============================
# Helper functions
# ==============================

function Send-SlackMessage {
    param([Parameter(Mandatory = $true)][string]$Message)

    $body = @{ text = $Message } | ConvertTo-Json
    Invoke-RestMethod -Uri $SlackWebhookURL -Method Post -Body $body -ContentType "application/json" | Out-Null
}

# ==============================
# Main execution
# ==============================

try {
    # Authenticate to Microsoft Graph using the service principal credentials.
    Write-Output "Authenticating with Microsoft Entra ID using a service principal..."

    $secureSecret = ConvertTo-SecureString $secretValue -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential($clientID, $secureSecret)

    Connect-MgGraph -TenantId $tenantID -ClientSecretCredential $Credential -NoWelcome
    Write-Output "Authentication successful."

    # Retrieve all application registrations to inspect their certificate metadata.
    Write-Output "Fetching all application registrations..."
    $apps = Get-MgApplication -All

    $now = Get-Date

    foreach ($app in $apps) {
        # Normalize the collection of key credentials so the logic is consistent for one or many certificates.
        $certificates = @($app.KeyCredentials)
        $confirmTrue = @()

        if ($certificates.Count -gt 1) {
            Write-Output "$($app.DisplayName) has multiple certificates. Checking each one..."

            foreach ($certificate in $certificates) {
                $certificateEndDate = $certificate.EndDateTime
                $diffDays = [int](($certificateEndDate - $now).TotalDays)

                if ($diffDays -lt 0) {
                    Write-Output "$($app.DisplayName) has an expired certificate."

                    $expiredMessage = "- *$($app.DisplayName)* (AppID: $($app.AppId)) - Certificate *($($certificate.KeyId)) has expired!`n"
                    Send-SlackMessage ":rotating_light: *EXPIRED APPLICATION CERTIFICATE FOUND* :rotating_light:`n$($expiredMessage)"
                }
                elseif ($diffDays -le $DayThreshold) {
                    Write-Output "$($app.DisplayName) has a certificate that is about to expire."

                    $soonToExpireMessage = "- *$($app.DisplayName)* (AppID: $($app.AppId)) - Certificate *($($certificate.KeyId)) will expire in $($diffDays) day(s)!`n"
                    Send-SlackMessage ":warning: *CERTIFICATE EXPIRING WITHIN $($DayThreshold) DAYS* :warning:`n$($soonToExpireMessage)"
                }
                else {
                    $confirmTrue += $certificate.KeyId
                }
            }

            if ($confirmTrue.Count -eq $certificates.Count) {
                Write-Output "$($app.DisplayName) has $($certificates.Count) valid certificates."
            }
        }
        elseif ($certificates.Count -eq 1) {
            $certificate = $certificates[0]
            $certificateEndDate = $certificate.EndDateTime
            $diffDays = [int](($certificateEndDate - $now).TotalDays)

            if ($diffDays -lt 0) {
                Write-Output "$($app.DisplayName) has an expired certificate."

                $expiredMessage = "- *$($app.DisplayName)* (AppID: $($app.AppId)) - Certificate *($($certificate.KeyId)) has expired!`n"
                Send-SlackMessage ":rotating_light: *EXPIRED APPLICATION CERTIFICATE FOUND* :rotating_light:`n$($expiredMessage)"
            }
            elseif ($diffDays -le $DayThreshold) {
                Write-Output "$($app.DisplayName) has a certificate that is about to expire."

                $soonToExpireMessage = "- *$($app.DisplayName)* (AppID: $($app.AppId)) - Certificate *($($certificate.KeyId)) will expire in $($diffDays) day(s)!`n"
                Send-SlackMessage ":warning: *CERTIFICATE EXPIRING WITHIN $($DayThreshold) DAYS* :warning:`n$($soonToExpireMessage)"
            }
            else {
                Write-Output "$($app.DisplayName) has no certificates that are expiring soon."
            }

            Start-Sleep -Seconds 5
        }
        else {
            Write-Output "$($app.DisplayName) does not have any certificates. Skipping to the next application..."
        }
    }
}
catch {
    Write-Output "The script failed while auditing application registration certificates."
    Write-Output "Error: $($_.Exception.Message)"
}
finally {
    # Ensure the Microsoft Graph connection is closed even if an error occurs.
    Write-Output "Disconnecting from Microsoft Graph..."
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Write-Output "Script completed."
}

