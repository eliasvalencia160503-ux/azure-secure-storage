ACCOUNT=$1

# 0. DNS check: inside the VNet the blob hostname should resolve to the private endpoint IP
BLOB_IP=$(getent hosts ${ACCOUNT}.blob.core.windows.net | awk '{print $1}')

if [ "$BLOB_IP" = "10.0.2.4" ]; then
    echo "PASS: blob hostname resolves to private endpoint $BLOB_IP"
else
    echo "FAIL: blob hostname resolves to '$BLOB_IP' (expected 10.0.2.4)"
fi
# 1. Ask IMDS for a token for Azure Storage, as the VM's managed identity
TOKEN=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
echo "Token length: ${#TOKEN}"

# 2. Use the token to list blobs in the container
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-ms-version: 2021-08-06" \
  "https://${ACCOUNT}.blob.core.windows.net/privatecont?restype=container&comp=list")

if [ "$STATUS" = "200" ]; then
    echo "PASS: VM managed identity can list blobs"
elif [ "$STATUS" = "403" ]; then
    echo "FAIL: AUTHORIZATION ERROR (RBAC)"
elif [ "$STATUS" = "401" ]; then
    echo "FAIL: AUTHENTICATION ERROR (TOKEN)"
else
    echo "FAIL: unexpected HTTP status $STATUS"
fi