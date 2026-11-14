# 1. Same token request as before (Azure Files uses the same storage resource)
TOKEN=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
echo "Token length: ${#TOKEN}"

# 2. List files in the share -- note: .file. instead of .blob.
curl -s -w "\nHTTP status: %{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-ms-version: 2022-11-02" \
  -H "x-ms-file-request-intent: backup" \
  "https://securestg62hq6ups.file.core.windows.net/sharefile?restype=directory&comp=list"