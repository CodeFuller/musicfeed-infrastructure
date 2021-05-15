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
if ($null -eq $ExistingConnections)
{
    Write-Host "Service connection '$ConnectionName' does not exist, exiting ..."
    exit 0
}

if ($ExistingConnections -is [array])
{
    Write-Error "Multiple service connections '$ConnectionName' exist"
    exit 1
}

$ConnectionId = $ExistingConnections.id
$ApiUrl = "${OrganizationUrl}_apis/serviceendpoint/endpoints/{$ConnectionId}?projectIds={$ProjectId}&api-version=6.1-preview.4"

Write-Host "Deleting service connection '$ConnectionName' ..."
Invoke-RestMethod -Method "Delete" -Uri $ApiUrl -Headers $AuthenicationHeader
if (-not $?) {
    Write-Error "Failed to delete service connection"
    exit 1
}

Write-Host "Service connection '$ConnectionName' was deleted successfully"
