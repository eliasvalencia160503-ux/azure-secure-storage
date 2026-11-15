$account = terraform -chdir=terraform output -raw storage_account_name
$response = curl.exe -s  "https://$account.blob.core.windows.net/privatecont?restype=container&comp=list"

if ($response -match "PublicAccessNotPermitted"){
    Write-Host "PASS: anonymous access is blocked"    
} else {
    Write-Host "FAIL: $response"
}

# Test 2: shared key access should be blocked
$keyresponse = az storage container list --account-name $account --auth-mode key 2>&1

if ($keyresponse -match "KeyBasedAuthenticationNotPermitted"){
    Write-Host "PASS: shared key access is blocked"
} else {
    Write-Host "FAIL: shared key request was not blocked as expected: $keyresponse"
}