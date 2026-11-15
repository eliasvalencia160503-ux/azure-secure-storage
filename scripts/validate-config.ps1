$account = terraform -chdir=terraform output -raw storage_account_name
$resourcegroup = terraform -chdir=terraform output -raw resource_group_name


$TLSversioncheck = az storage account show -n $account -g $resourcegroup --query minimumTlsVersion -o tsv

if ($TLSversioncheck -eq "TLS1_2"){
    Write-Host "PASS: Minimum TLS is met"
} else {
    Write-Host "FAIL: TLS is $TLSversioncheck"
}

$httpstraffic = az storage account show -n $account -g $resourcegroup --query enableHttpsTrafficOnly -o tsv

if ($httpstraffic -eq "true"){
    Write-Host "PASS: Only HTTPS traffic is enabled"
} else {
    Write-Host "FAIL: HTTPStrafficonly is $httpstraffic"
}

$sharedaccesskey = az storage account show -n $account -g $resourcegroup --query allowSharedKeyAccess -o tsv

if ($sharedaccesskey -eq "false"){
    Write-Host "PASS: shared access key is disabled"
} else {
    Write-Host "FAIL: shared access key is $sharedaccesskey"
}

$publicaccess = az storage account show -n $account -g $resourcegroup --query allowBlobPublicAccess -o tsv

if ($publicaccess -eq "false"){
    Write-Host "PASS: Public blob access is disabled"
} else {
    Write-Host "FAIL: allowBlobPublicAccess is $publicaccess"
}

$firewall = az storage account show -n $account -g $resourcegroup --query networkRuleSet.defaultAction -o tsv

if ($firewall -eq "Deny"){
    Write-Host "PASS: Firewall default action is Deny"
} else {
    Write-Host "FAIL: Firewall default action is $firewall"
}


