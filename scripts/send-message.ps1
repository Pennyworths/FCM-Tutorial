# PowerShell 脚本：从后端发送消息给用户

param(
    [Parameter(Mandatory=$true)]
    [string]$UserEmail,
    
    [Parameter(Mandatory=$true)]
    [string]$Title,
    
    [Parameter(Mandatory=$true)]
    [string]$Body,
    
    [string]$Data = "",
    
    [string]$AwsProfile = "terraform",
    
    [string]$Region = "us-east-1"
)

# 颜色输出函数
function Write-Info { Write-Host $_ -ForegroundColor Cyan }
function Write-Success { Write-Host $_ -ForegroundColor Green }
function Write-Error { Write-Host $_ -ForegroundColor Red }
function Write-Warning { Write-Host $_ -ForegroundColor Yellow }

Write-Info "=== 后端发送消息工具 ===" ""
Write-Info "目标用户邮箱: $UserEmail"
Write-Info "消息标题: $Title"
Write-Info "消息内容: $Body"
Write-Info ""

# 步骤 1: 获取 Cognito 配置
Write-Info "步骤 1: 获取 Cognito 配置..."

$cognitoDir = Join-Path $PSScriptRoot "..\infra\Cognito"
if (-not (Test-Path $cognitoDir)) {
    Write-Error "错误: 找不到 infra/Cognito 目录"
    exit 1
}

Push-Location $cognitoDir

try {
    $USER_POOL_ID = terraform output -raw user_pool_id 2>$null
    if (-not $USER_POOL_ID) {
        Write-Error "错误: 无法获取 USER_POOL_ID，请先部署 Cognito"
        exit 1
    }
    
    $CLIENT_ID = terraform output -raw user_pool_client_id 2>$null
    if (-not $CLIENT_ID) {
        Write-Error "错误: 无法获取 CLIENT_ID"
        exit 1
    }
    
    Write-Success "  ✓ User Pool ID: $USER_POOL_ID"
    Write-Success "  ✓ Client ID: $CLIENT_ID"
} catch {
    Write-Error "错误: 获取 Cognito 配置失败: $_"
    exit 1
} finally {
    Pop-Location
}

# 步骤 2: 获取 API Gateway URL
Write-Info ""
Write-Info "步骤 2: 获取 API Gateway URL..."

$apiGatewayDir = Join-Path $PSScriptRoot "..\infra\API_Gateway"
if (-not (Test-Path $apiGatewayDir)) {
    Write-Error "错误: 找不到 infra/API_Gateway 目录"
    exit 1
}

Push-Location $apiGatewayDir

try {
    $API_BASE_URL = terraform output -raw api_base_url 2>$null
    if (-not $API_BASE_URL) {
        Write-Error "错误: 无法获取 API Gateway URL，请先部署 API Gateway"
        exit 1
    }
    
    Write-Success "  ✓ API Base URL: $API_BASE_URL"
} catch {
    Write-Error "错误: 获取 API Gateway URL 失败: $_"
    exit 1
} finally {
    Pop-Location
}

# 步骤 3: 查询目标用户的 user_id
Write-Info ""
Write-Info "步骤 3: 查询用户 user_id..."

try {
    $userInfoJson = aws cognito-idp admin-get-user `
        --user-pool-id $USER_POOL_ID `
        --username $UserEmail `
        --profile $AwsProfile `
        --region $Region `
        --output json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "错误: 查询用户失败: $userInfoJson"
        exit 1
    }
    
    $userInfo = $userInfoJson | ConvertFrom-Json
    $userId = ($userInfo.UserAttributes | Where-Object { $_.Name -eq "sub" }).Value
    
    if (-not $userId) {
        Write-Error "错误: 无法获取用户 ID"
        exit 1
    }
    
    Write-Success "  ✓ User ID: $userId"
} catch {
    Write-Error "错误: 查询用户失败: $_"
    exit 1
}

# 步骤 4: 准备消息数据
Write-Info ""
Write-Info "步骤 4: 准备消息数据..."

$messageData = @{
    user_id = $userId
    title = $Title
    body = $Body
}

# 如果有自定义 data，添加它
if ($Data -ne "") {
    try {
        $customData = $Data | ConvertFrom-Json
        $messageData.data = $customData
    } catch {
        Write-Warning "  ! 警告: Data 不是有效的 JSON，将被忽略"
    }
}

$messageBody = $messageData | ConvertTo-Json -Depth 10 -Compress

Write-Success "  ✓ 消息数据准备完成"

# 步骤 5: 提示需要认证 Token
Write-Info ""
Write-Warning "注意: 当前 API 需要 Cognito 认证"
Write-Warning "你需要提供管理员用户的登录 Token"
Write-Info ""
Write-Info "选项 1: 使用管理员账号登录获取 Token"
Write-Info "选项 2: 直接调用 Lambda 函数（需要 AWS CLI 配置）"
Write-Info ""
$choice = Read-Host "请选择 (1/2) [默认: 2]"

if ($choice -eq "1" -or $choice -eq "") {
    # 选项 1: 通过 API Gateway 发送（需要 Token）
    Write-Info ""
    Write-Info "=== 方式 1: 通过 API Gateway 发送 ==="
    Write-Info "需要提供管理员用户的登录信息"
    Write-Info ""
    
    $adminEmail = Read-Host "管理员邮箱"
    $adminPassword = Read-Host "管理员密码" -AsSecureString
    $adminPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPassword)
    )
    
    # 获取 Token
    Write-Info ""
    Write-Info "正在登录获取 Token..."
    
    $authEndpoint = "https://cognito-idp.$Region.amazonaws.com/"
    $authBody = @{
        AuthFlow = "USER_PASSWORD_AUTH"
        ClientId = $CLIENT_ID
        AuthParameters = @{
            USERNAME = $adminEmail
            PASSWORD = $adminPasswordPlain
        }
    } | ConvertTo-Json
    
    $authHeaders = @{
        "X-Amz-Target" = "AWSCognitoIdentityProviderService.InitiateAuth"
        "Content-Type" = "application/x-amz-json-1.1"
    }
    
    try {
        $authResponse = Invoke-RestMethod -Uri $authEndpoint -Method Post -Body $authBody -Headers $authHeaders
        $idToken = $authResponse.AuthenticationResult.IdToken
        
        Write-Success "  ✓ 登录成功"
    } catch {
        Write-Error "错误: 登录失败: $_"
        exit 1
    }
    
    # 发送消息
    Write-Info ""
    Write-Info "正在发送消息..."
    
    $sendHeaders = @{
        "Authorization" = "Bearer $idToken"
        "Content-Type" = "application/json"
    }
    
    try {
        $sendResponse = Invoke-RestMethod `
            -Uri "$API_BASE_URL/messages/send" `
            -Method Post `
            -Body $messageBody `
            -Headers $sendHeaders
        
        Write-Success ""
        Write-Success "========================================"
        Write-Success "消息发送成功！"
        Write-Success "========================================"
        Write-Success ""
        Write-Success "响应: $($sendResponse | ConvertTo-Json -Depth 10)"
    } catch {
        Write-Error ""
        Write-Error "========================================"
        Write-Error "消息发送失败"
        Write-Error "========================================"
        Write-Error ""
        Write-Error "错误: $_"
        
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Error "响应内容: $responseBody"
        }
        
        exit 1
    }
} else {
    # 选项 2: 直接调用 Lambda 函数
    Write-Info ""
    Write-Info "=== 方式 2: 直接调用 Lambda 函数 ==="
    Write-Warning "注意: 这需要修改 Lambda 函数以支持无认证调用，或者创建新的 Admin Lambda"
    Write-Info ""
    Write-Info "当前实现需要 Cognito 认证，直接调用 Lambda 将失败"
    Write-Info "建议使用方式 1，或者创建一个专门的 Admin Lambda 函数"
    Write-Info ""
    Write-Info "Lambda 函数调用格式（参考）:"
    Write-Info 'aws lambda invoke --function-name <LAMBDA_NAME> --payload "{\"body\":\"...\",\"requestContext\":{...}}" response.json'
}

