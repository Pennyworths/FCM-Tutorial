# 如何查看所有用户的 user_id

有几种方法可以查看所有注册用户的 user_id：

## 方法 1: 从数据库查询（推荐 - 仅显示已注册设备的用户）

从 `devices` 表中查询所有唯一的 `user_id`：

### 使用 AWS RDS Query Editor 或 psql

```sql
SELECT DISTINCT user_id 
FROM devices 
ORDER BY user_id;
```

### 使用 AWS CLI 通过 Lambda 查询

如果你已经部署了 `list_users` API 端点：

```bash
# 获取 API Gateway URL
API_URL=$(cd infra/API_Gateway && terraform output -raw api_gateway_url)

# 获取 ID Token（需要先登录）
ID_TOKEN="your-cognito-id-token"

# 调用 API
curl -X GET "$API_URL/users" \
  -H "Authorization: Bearer $ID_TOKEN"
```

## 方法 2: 从 Cognito User Pool 查询（显示所有注册用户）

### 使用 AWS CLI

```bash
# 获取 User Pool ID
USER_POOL_ID=$(cd infra/Cognito && terraform output -raw user_pool_id)

# 列出所有用户
aws cognito-idp list-users \
  --user-pool-id $USER_POOL_ID \
  --query 'Users[*].Username' \
  --output table
```

### 获取用户详细信息（包括 sub/user_id）

```bash
# 列出所有用户及其属性
aws cognito-idp list-users \
  --user-pool-id $USER_POOL_ID \
  --query 'Users[*].[Username,Attributes[?Name==`sub`].Value|[0]]' \
  --output table
```

### 使用 AWS Console

1. 打开 AWS Console
2. 进入 Cognito → User Pools
3. 选择你的 User Pool
4. 点击 "Users" 标签
5. 查看所有用户列表

## 方法 3: 使用新的 API 端点（需要部署）

我已经创建了 `GET /users` API 端点，但需要：

1. 运行 `sqlc generate` 生成数据库查询代码
2. 重新构建和部署 Lambda 函数
3. 在 API Gateway 中添加新的端点

### 部署步骤

```bash
# 1. 生成 sqlc 代码（需要安装 sqlc）
cd backend/Lambda/API
sqlc generate

# 2. 重新构建和推送 Docker 镜像
cd ../../..
./scripts/build-and-push-backend.sh

# 3. 更新 Terraform 配置（需要添加 list_users lambda）
cd infra/Lambdas
terraform apply

# 4. 更新 API Gateway 配置（需要添加 /users 端点）
cd ../API_Gateway
terraform apply
```

## 注意事项

- **方法 1（数据库查询）**：只显示已经注册设备的用户
- **方法 2（Cognito查询）**：显示所有注册用户，包括未注册设备的用户
- **方法 3（API端点）**：需要部署，但提供编程式访问

## 快速查看（最简单）

如果你只是想快速查看，使用 AWS Console 是最简单的方法：

1. AWS Console → Cognito → User Pools
2. 选择你的 User Pool
3. Users 标签页
4. 每个用户的 `sub` 字段就是 `user_id`

