<#
.SYNOPSIS
    Audits app registrations for expiring or expired secrets.
.DESCRIPTION
    This script connects to Microsoft Graph, reviews application registrations for password credential expiry, and sends Slack alerts when issues are found.
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

    # Retrieve all application registrations to inspect their secret metadata.
    Write-Output "Fetching all application registrations..."
    $apps = Get-MgApplication -All

    $now = Get-Date

    foreach ($app in $apps) {
        # Normalize the password credential collection so the logic works for one or many secrets.
        $secrets = @($app.PasswordCredentials)
        $confirmTrue = @()

        if ($secrets.Count -gt 1) {
            Write-Output "$($app.DisplayName) has multiple secrets. Checking each one..."

            foreach ($secret in $secrets) {
                $secretEndDate = $secret.EndDateTime
                $diffDays = [int](($secretEndDate - $now).TotalDays)

                if ($diffDays -lt 0) {
                    Write-Output "$($app.DisplayName) has an expired secret."

                    $expiredMessage = "- *$($app.DisplayName)* (AppID: $($app.AppId)) - Secret *($($secret.KeyId)) has expired!`n"
                    Send-SlackMessage ":rotating_light: *EXPIRED APPLICATION SECRET FOUND* :rotating_light:`n$($expiredMessage)"
                }
                elseif ($diffDays -le $DayThreshold) {
                    Write-Output "$($app.DisplayName) has a secret that is about to expire."

                    $soonToExpireMessage = "- *$($app.DisplayName)* (AppID: $($app.AppId)) - Secret *($($secret.KeyId)) will expire in $($diffDays) day(s)!`n"
                    Send-SlackMessage ":warning: *SECRET EXPIRING WITHIN $($DayThreshold) DAYS* :warning:`n$($soonToExpireMessage)"
                }
                else {
                    $confirmTrue += $secret.KeyId
                }
            }

            if ($confirmTrue.Count -eq $secrets.Count) {
                Write-Output "$($app.DisplayName) has $($secrets.Count) valid secrets."
            }
        }
        elseif ($secrets.Count -eq 1) {
            $secret = $secrets[0]
            $secretEndDate = $secret.EndDateTime
            $diffDays = [int](($secretEndDate - $now).TotalDays)

            if ($diffDays -lt 0) {
                Write-Output "$($app.DisplayName) has an expired secret."

                $expiredMessage = "- *$($app.DisplayName)* (AppID: $($app.AppId)) - Secret *($($secret.KeyId)) has expired!`n"
                Send-SlackMessage ":rotating_light: *EXPIRED APPLICATION SECRET FOUND* :rotating_light:`n$($expiredMessage)"
            }
            elseif ($diffDays -le $DayThreshold) {
                Write-Output "$($app.DisplayName) has a secret that is about to expire."

                $soonToExpireMessage = "- *$($app.DisplayName)* (AppID: $($app.AppId)) - Secret *($($secret.KeyId)) will expire in $($diffDays) day(s)!`n"
                Send-SlackMessage ":warning: *SECRET EXPIRING WITHIN $($DayThreshold) DAYS* :warning:`n$($soonToExpireMessage)"
            }
            else {
                Write-Output "$($app.DisplayName) has no secrets that are expiring soon."
            }

            Start-Sleep -Seconds 5
        }
        else {
            Write-Output "$($app.DisplayName) does not have any secrets. Skipping to the next application..."
        }
    }
}
catch {
    Write-Output "The script failed while auditing application registration secrets."
    Write-Output "Error: $($_.Exception.Message)"
}
finally {
    # Ensure the Microsoft Graph connection is closed even if an error occurs.
    Write-Output "Disconnecting from Microsoft Graph..."
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Write-Output "Script completed."
}

