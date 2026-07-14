# =============================================
# Password generator using Genratr public API
# =============================================

# Stop on any unexpected errors.
$ErrorActionPreference = 'Stop'

# ==============================
# Configuration
# ==============================

# Desired password length.
$passwordLength = 32

# Include types of characters in the generated password.
$upperCase = $true
$specialCase = $true
$numbers = $true

# ==============================
# Build URI parameters
# ==============================

# Always include lowercase characters.
$queryParams = @{
    length    = $passwordLength
    lowercase = $true
}

if ($upperCase) {
    $queryParams.uppercase = $true
}

if ($specialCase) {
    $queryParams.special = $true
}

if ($numbers) {
    $queryParams.numbers = $true
}

# Format the query string and build the request URI.
$queryString = ($queryParams.GetEnumerator() | ForEach-Object {
    "{0}={1}" -f $_.Key, $_.Value.ToString().ToLower()
}) -join '&'

$URI = "https://api.genratr.com/?$queryString/json"

Write-Output "Request URI:`n$URI"

# ==============================
# Generate a new password
# ==============================

try {
    $response = Invoke-WebRequest -Uri $URI -UseBasicParsing
    $json = $response.Content | ConvertFrom-Json
    $secretValue = $json.password
}
catch {
    Write-Error "An error occurred while generating the password:`n$($_.Exception.Message)"
    throw
}

# ==============================
# Export secretValue for Azure DevOps pipelines
# ==============================

Write-Output "##vso[task.setvariable variable=secretValue;isOutput=true;isSecret=true]$secretValue"
