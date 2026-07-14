#Initial Banner
Write-Host "`n"
Write-Host "                    -------------------------------------------------            " -ForegroundColor DarkBlue
Write-Host "                    |                                               |            " -ForegroundColor DarkBlue
Write-Host "                    |             Manage User Permissions           |            " -ForegroundColor DarkBlue
Write-Host "                    |                  Version 1.0                  |            " -ForegroundColor DarkBlue
Write-Host "                    |                                               |            " -ForegroundColor DarkBlue
Write-Host "                    |              Author rbruno20                  |            " -ForegroundColor DarkBlue
Write-Host "                    |                                               |            " -ForegroundColor DarkBlue
Write-Host "                    -------------------------------------------------            " -ForegroundColor DarkBlue
Write-Host "`n"

# Variables
. .\variables.ps1
# Log file path - replace with a safe location before running
$logFile = "<file-path>"

# Connect to Microsoft Graph (uses app registration in variables.ps1)
Connect-MgGraph -TenantId $tenantID -ClientId $clientID -CertificateThumbprint $certificateThumbprint -NoWelcome
Get-MgContext | Out-Null

#Get all groups
$groupAll = Get-MgGroup -All
$total = 0
#Get group member and count using Measure-Object
foreach ($group in $groupAll) {
    $count = Get-MgGroupMember -GroupId $group.Id | Measure-Object | Select-Object Count

    if ($group.OnPremisesSyncEnabled -eq $true) {
        Write-Host "Group $($group.DisplayName) of ID $($group.Id) cannot be removed because it is sync with Active Directory!" -ForegroundColor Blue
    }
    else {
        if ($count.Count -eq 1) {
            Write-Host "Going to remove Group $($group.DisplayName) of ID $($group.Id) and Group Type $($group.GroupTypes)" -ForegroundColor Red
            Write-Output "Going to remove Group $($group.DisplayName) of ID $($group.Id) and Group Type $($group.GroupTypes)"| Out-File -Path "<file-path>" -Append
            #Remove-MgGroup -GroupId $group.Id -Verbose -ErrorAction Stop
            $total ++
        }
        else {
            Write-Host "Group $($group.DisplayName) of ID $($group.Id) and Group Type $($group.GroupTypes) has $($count.Count) users" -ForegroundColor Green
            Write-Output "Keep $($group.DisplayName) of ID $($group.Id) and Group Type $($group.GroupTypes)"| Out-File -Path $logFile -Append
        }
    }
}
Write-Host "A total of $($total) groups have been removed!" -ForegroundColor White -BackgroundColor Black