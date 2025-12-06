# 用户名注册配置说明

## 概述

已将 Cognito 用户池配置从**必须使用邮箱注册**改为**只使用用户名注册**（邮箱可选）。

## 主要更改

### 1. Cognito 配置 (`infra/Cognito/main.tf`)

- ✅ 将 `email` 属性改为可选：`required = false`
- ✅ 移除了 `auto_verified_attributes = ["email"]`
- ✅ 移除了 `account_recovery_setting`（因为它依赖邮箱）

### 2. Android 注册代码 (`CognitoAuth.kt`)

- ✅ `register()` 函数参数从 `email` 改为 `username`
- ✅ 移除了注册请求中的 `UserAttributes`（不再发送邮箱）
- ✅ `RegisterResult` 数据类字段从 `email` 改为 `username`

### 3. Android UI (`MainActivity.kt`)

- ✅ 注册变量名从 `registerEmail` 改为 `registerUsername`
- ✅ 注册表单标签改为 "Username"
- ✅ 登录表单标签改为 "Username"

## 部署步骤

### 步骤 1: 重新部署 Cognito

由于 Cognito 配置已更改，需要重新应用 Terraform 配置：

```bash
cd infra/Cognito
terraform apply
```

⚠️ **注意**：这可能会影响现有的用户。如果已有用户注册，建议：
- 备份现有用户数据
- 或者创建一个新的测试环境

### 步骤 2: 重新编译 Android 应用

```bash
cd android
./gradlew clean build
```

或在 Android Studio 中：
1. Build → Clean Project
2. Build → Rebuild Project

## 使用说明

### 注册新用户

用户现在可以：
1. 点击 "Register" 按钮
2. 输入**用户名**（不需要邮箱格式）
3. 输入密码
4. 确认密码
5. 注册成功后自动登录

### 登录

用户可以使用注册时使用的用户名登录。

## 密码要求

密码仍然需要满足以下要求：
- 至少 8 个字符
- 包含大写字母
- 包含小写字母
- 包含数字
- 包含特殊符号

## 注意事项

1. **邮箱现在是可选的**：如果以后需要邮箱，用户可以在个人资料中添加
2. **账户恢复**：由于不再使用邮箱，账户恢复功能已被移除。如果需要恢复功能，可以考虑：
   - 使用安全问题
   - 使用手机号（需要额外配置）
3. **现有用户**：如果已有用户使用邮箱注册，他们仍然可以使用邮箱作为用户名登录

## 测试

注册测试用户：

```bash
# 获取 User Pool ID
USER_POOL_ID=$(cd infra/Cognito && terraform output -raw user_pool_id)

# 创建测试用户（使用用户名）
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username testuser \
  --user-attributes Name=email,Value=testuser@example.com \
  --temporary-password "TempPassword123!" \
  --message-action SUPPRESS \
  --profile terraform \
  --region us-east-1

# 设置永久密码
aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username testuser \
  --password "TestPassword123!" \
  --permanent \
  --profile terraform \
  --region us-east-1
```

现在可以使用 `testuser` 和 `TestPassword123!` 登录。

