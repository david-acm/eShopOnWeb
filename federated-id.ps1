$appName = 'eShopOnWeb'
$location = 'eastus'
$env = 'dev'
$ghAccount = 'david-acm'

function Get-GitHubRepoName {
    param(
        [string]$url
    )

    $urlParts = $url `
        -split "/"
    $lastPart = $urlParts[-1]
    $repoName = $lastPart.Replace(".git", "")
    return $repoName
}

function Cyan {
   process {Write-Host `
        -ForegroundColor Cyan}
}

# az ad app delete `
# --id $appId

$repoName = Get-GitHubRepoName `
    -url $(git remote get-url origin)

'1. Creating app registration...'  | Cyan
$appId = az ad app create `
--display-name $("$appName-GitHub") `
--query '{appId:appId}' `
-o tsv
 
$appObjectId = az ad app show `
--id $appId `
--query '[id]' `
-o tsv

"Created with appId $appId and appObjectId $appObjectId" | Cyan

'2. Creating service principal...'  | Cyan

$objectId = az ad sp create `
--id $appId `
--query '{objectId:id}'`
-o tsv

$objectId = az ad sp show `
--id $appId `
--query '{objectId:id}'`
-o tsv

"Created with objectId $objectId" | Cyan

'3. Creating resource group...' | Cyan
$rgName = az group create `
--name $("rg-$appName-$env-$location") `
--query '[name]' `
--location eastus `
-o tsv

"Created with name $rgName" | Cyan

$subscriptionId = az account show `
--query '[id]' `
-o tsv

'3. Creating role assigment...' | Cyan

az role assignment create `
--role contributor `
--subscription $subscriptionId `
--assignee-object-id  $objectId `
--assignee-principal-type ServicePrincipal `
--scope /subscriptions/$subscriptionId/resourceGroups/$rgName 

'Role assigment created' | Cyan

$tenantId = az account show `
--query '[tenantId]' `
-o tsv

$content = $("{
    ""name"": ""fedid-$appName-$env-$location"",
    ""issuer"": ""https://token.actions.githubusercontent.com"",
    ""subject"": ""repo:$ghAccount/${repoName}:ref:refs/heads/main"",
    ""description"": ""Testing"",
    ""audiences"": [
        ""api://AzureADTokenExchange""
    ]
}")

$credenialFile = 'credential.json'
$path = (ni $credenialFile -Force).FullName
$content | Out-File `
    -FilePath $path `
    -Encoding ascii

'4. Creating federated credential...' | Cyan

az ad app federated-credential create `
--id $appObjectId `
--parameters $credenialFile

'Federated credential created' | Cyan

'5. Setting secrets in GitHub...' | Cyan

gh secret set AZURE_CLIENT_ID `
    -b $appId
gh secret set AZURE_TENANT_ID `
    -b $tenantId
gh secret set AZURE_SUBSCRIPTION_ID `
    -b $subscriptionId

'Success!' | Cyan