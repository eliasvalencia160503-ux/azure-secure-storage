# 1. Ask IMDS for a token for Azure Storage, as the VM's managed identity
TOKEN=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
echo "Token length: ${#TOKEN}"

# 2. Use the token to list blobs in the container
curl -s -w "\nHTTP status: %{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-ms-version: 2021-08-06" \
  "https://securestg62hq6ups.blob.core.windows.net/privatecont?restype=container&comp=list"