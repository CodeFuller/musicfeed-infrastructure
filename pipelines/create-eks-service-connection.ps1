param (
    [Parameter(mandatory)] $PersonalToken,
    [Parameter(mandatory)] $OrganizationUrl,
    [Parameter(mandatory)] $ProjectId,
    [Parameter(mandatory)] $ProjectName,
    [Parameter(mandatory)] $ClusterName
)

$ConnectionName = "AWS EKS - $ClusterName"

$AuthenicationHeader = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($PersonalToken)")) }

Write-Host "Loading existing service connections ..."
$ApiUrl = "${OrganizationUrl}${ProjectName}/_apis/serviceendpoint/endpoints?api-version=6.1-preview.4"
$Result = Invoke-RestMethod -Method "Get" -Uri $ApiUrl -Headers $AuthenicationHeader
$ExistingConnections = $Result.Value | Where-Object { $_.Type -eq "kubernetes" -and $_.Name -eq $ConnectionName }
if ($ExistingConnections) {
    Write-Host "Service connection '$ConnectionName' already exists, exiting ..."
    exit 0
}

Write-Host "Service connection '$ConnectionName' does not exist and will be created"

Write-Host "Configuring kubectl ..."
& aws eks update-kubeconfig --name $ClusterName
if (-not $?) {
    Write-Error "Failed to configure kubectl"
    exit 1
}

Write-Host "Creating pipelines service account ..."
& kubectl apply -f pipelines-service-account.yaml
if (-not $?) {
    Write-Error "Failed to configure create pipelines service account"
    exit 1
}

Write-Host "Extracting server URL ..."
$ServerUrl = kubectl config view --minify -o jsonpath="{.clusters[0].cluster.server}"
if (-not $?) {
    Write-Error "Failed to extract server URL"
    exit 1
}
else {
    Write-Host "Extracted server URL: '$ServerUrl'"
}

Write-Host "Extracting service account token name ..."
$TokenName = kubectl get serviceAccounts pipelines-robot -o=jsonpath="{.secrets[*].name}"
if (-not $?) {
    Write-Error "Failed to extract service account token name"
    exit 1
}

Write-Host "Extracting service account token ..."
$SecretJson = kubectl get secret $TokenName -o json | ConvertFrom-Json
if (-not $?) {
    Write-Error "Failed to extract service account token"
    exit 1
}

$ApiToken = $SecretJson.data.token;
$ServiceAccountCertificate = $SecretJson.data."ca.crt";

$RequestBody = @{
    data = @{
        authorizationType   = "ServiceAccount"
    }
    name = $ConnectionName
    type = "kubernetes"
    url = $ServerUrl
    authorization = @{
        parameters = @{
            apiToken = $ApiToken
            serviceAccountCertificate = $ServiceAccountCertificate
            isCreatedFromSecretYaml = $true
        }
        scheme = "Token"
    }
    isShared = $false
    isReady = $true
    owner = "Library"
    serviceEndpointProjectReferences = @(
        @{
            projectReference = @{
                id = $ProjectId
                name = $ProjectName
            }
            name = $ConnectionName
        }
    )
}

$ApiUrl = "${OrganizationUrl}_apis/serviceendpoint/endpoints?api-version=6.1-preview.4"

Write-Host "Creating service connection '$ConnectionName' ..."
Invoke-RestMethod -Method "Post" -Uri $ApiUrl -Headers $AuthenicationHeader -Body ($RequestBody | ConvertTo-Json -Depth 3) -ContentType "application/json"
if (-not $?) {
    Write-Error "Failed to create service connection"
    exit 1
}

Write-Host "Service connection '$ConnectionName' was created successfully"
