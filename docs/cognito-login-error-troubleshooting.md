# Cognito 登录错误排查指南

## 错误 1: `UnknownOperationException`

### 问题描述

```
{"Output":{"__type":"com.amazon.coral.service#UnknownOperationException"},"Version":"1.0"}
```

这个错误表示 AWS API 无法识别请求的操作。

### 原因

AWS Cognito API 需要使用特定的 `Content-Type` header：
- ❌ 错误：`application/json`
- ✅ 正确：`application/x-amz-json-1.1`

### 解决方案

✅ **已修复**：代码已经更新为使用正确的 Content-Type (`application/x-amz-json-1.1`)。

请重新编译并运行应用。如果问题仍然存在，检查：
1. 确保应用已重新编译
2. 检查 Logcat 中的完整请求和响应
3. 确认 `X-Amz-Target` header 正确设置为 `AWSCognitoIdentityProviderService.InitiateAuth`

---

## 错误 2: `UnknownOperationException`

### 问题描述

```
{"Output":{"__type":"com.amazon.coral.service#UnknownOperationException"},"Version":"1.0"}
```

这个错误表示 AWS API 无法识别请求的操作。

### 原因

AWS Cognito API 需要使用特定的 `Content-Type` header：
- ❌ 错误：`application/json`
- ✅ 正确：`application/x-amz-json-1.1`

### 解决方案

代码已经更新，现在使用正确的 Content-Type。请重新编译并运行应用。

---

## 错误 2: `No value for AuthenticationResult`

### 问题描述

当你尝试登录时，可能会遇到以下错误：

```
org.json.JSONException: No value for AuthenticationResult
at com.example.fcmplayground.CognitoAuth$login$2.invokeSuspend(CognitoAuth.kt:140)
```

这个错误表示 Cognito 返回了 200 状态码，但响应中没有 `AuthenticationResult` 字段。

### 常见原因

1. **挑战响应（Challenge Response）**
   - Cognito 要求额外的验证步骤（如设置新密码、MFA 等）
   - 响应中包含 `ChallengeName` 而不是 `AuthenticationResult`

2. **用户不存在或密码错误**
   - 用户 "123" 可能不是一个有效的 Cognito 用户
   - 密码可能不正确

3. **用户状态问题**
   - 用户账户可能需要验证
   - 用户可能被禁用

### 解决方法

#### 方法 1: 检查日志中的完整响应

应用现在会记录完整的 Cognito 响应（前 500 个字符）。查看 Logcat 中的 `CognitoAuth` 标签，查找类似以下内容：

```
D/CognitoAuth: Cognito response (code=200): {"ChallengeName":"NEW_PASSWORD_REQUIRED",...}
```

这将帮助你了解 Cognito 返回了什么。

#### 方法 2: 创建一个有效的测试用户

使用 AWS CLI 创建一个测试用户：

```bash
# 获取 User Pool ID
USER_POOL_ID=$(cd infra/Cognito && terraform output -raw user_pool_id)

# 创建用户
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username testuser@example.com \
  --user-attributes Name=email,Value=testuser@example.com Name=email_verified,Value=true \
  --temporary-password "TempPassword123!" \
  --message-action SUPPRESS \
  --profile terraform \
  --region us-east-1

# 设置永久密码
aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username testuser@example.com \
  --password "TestPassword123!" \
  --permanent \
  --profile terraform \
  --region us-east-1
```

然后使用这个邮箱和密码登录。

#### 方法 3: 使用应用内的注册功能

1. 在应用中点击 "Register" 按钮
2. 输入邮箱和密码
3. 检查邮箱中的验证码
4. 输入验证码确认注册
5. 使用注册的邮箱和密码登录

### 改进的错误处理

代码已经更新，现在会：

1. **记录完整的响应内容**以便调试
2. **检测挑战响应**并提供清晰的错误消息
3. **提供更友好的错误提示**

### 查看 Cognito 用户列表

```bash
# 获取 User Pool ID
USER_POOL_ID=$(cd infra/Cognito && terraform output -raw user_pool_id)

# 列出所有用户
aws cognito-idp list-users \
  --user-pool-id $USER_POOL_ID \
  --profile terraform \
  --region us-east-1 \
  --query 'Users[*].[Username,UserStatus]' \
  --output table
```

### 常见挑战类型

- **NEW_PASSWORD_REQUIRED**: 用户需要设置新密码（通常是临时密码）
- **SOFTWARE_TOKEN_MFA**: 需要多因素认证（软件令牌）
- **SMS_MFA**: 需要 SMS 验证码
- **EMAIL_VERIFICATION**: 需要验证邮箱

### 下一步

如果问题仍然存在：

1. 检查 Logcat 中的完整响应
2. 确认用户是否存在且状态正常
3. 尝试使用应用内的注册功能创建新用户
4. 查看 AWS Cognito Console 中的用户状态

