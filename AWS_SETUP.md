# AWS 配置总结

## ✅ 当前 AWS 配置状态

### 1. AWS CLI 配置
- **状态**: ✅ 已配置
- **区域**: `us-east-1`
- **凭证**: ✅ 已设置（access_key 和 secret_key）

### 2. 验证命令
```powershell
# 查看当前配置
aws configure list

# 验证凭证是否有效
aws sts get-caller-identity

# 查看区域
aws configure get region
```

---

## 📋 项目所需的 AWS 服务

根据 Terraform 配置，项目需要以下 AWS 服务：

### 核心服务
1. **VPC** - 虚拟私有云
   - 创建 VPC、子网、路由表
   - 安全组配置

2. **RDS** - 关系型数据库服务
   - PostgreSQL 15.4
   - 私有子网部署
   - 安全组：仅 Lambda 可访问

3. **Lambda** - 无服务器计算
   - 4 个函数：registerDevice, sendMessage, testAck, testStatus
   - 容器镜像部署（ECR）
   - VPC 访问（连接 RDS）

4. **API Gateway** - REST API
   - 4 个端点：
     - POST /devices/register
     - POST /messages/send
     - POST /test/ack
     - GET /test/status

5. **ECR** - 容器镜像仓库
   - 存储 Lambda 容器镜像

6. **Secrets Manager** - 密钥管理
   - FCM 服务账户凭证
   - RDS 密码

7. **IAM** - 身份和访问管理
   - Lambda 执行角色
   - 权限策略

8. **CloudWatch Logs** - 日志服务
   - Lambda 函数日志

---

## 🔐 所需的 AWS 权限

你的 AWS 账户需要以下权限来部署此项目：

### Terraform 需要的权限
- `ec2:*` - 创建 VPC、子网、安全组
- `rds:*` - 创建和管理 RDS 实例
- `lambda:*` - 创建和管理 Lambda 函数
- `apigateway:*` - 创建和管理 API Gateway
- `ecr:*` - 创建和管理容器镜像仓库
- `secretsmanager:*` - 创建和管理密钥
- `iam:*` - 创建 IAM 角色和策略
- `logs:*` - 创建 CloudWatch Logs
- `sts:GetCallerIdentity` - 验证身份

### 推荐策略
如果你使用的是 IAM 用户，建议附加以下策略：
- `PowerUserAccess` (推荐用于开发)
- 或自定义策略包含上述权限

---

## 📝 下一步：创建 .env 文件

在部署之前，需要创建 `.env` 文件：

```powershell
# 复制模板
Copy-Item env.example .env

# 编辑 .env 文件，填写以下信息：
# 1. DB_USERNAME - 数据库用户名
# 2. DB_PASSWORD - 数据库密码
# 3. FCM_SERVICE_ACCOUNT_JSON_FILE - FCM 服务账户 JSON 文件路径（或放在项目根目录的 service-account.json）
```

### .env 文件示例
```env
# 数据库凭证
DB_USERNAME=fcm_admin
DB_PASSWORD=your_secure_password_here

# FCM 服务账户（推荐：放在项目根目录的 service-account.json）
# FCM_SERVICE_ACCOUNT_JSON_FILE=service-account.json

# AWS 配置（可选，已通过 aws configure 设置）
# AWS_REGION=us-east-1
# AWS_PROFILE=default
```

---

## 🚀 部署流程

### 1. 准备环境变量
```powershell
# 创建 .env 文件
Copy-Item env.example .env
# 编辑 .env 文件，填写数据库凭证和 FCM 凭证
```

### 2. 准备 FCM 服务账户文件
- 从 Firebase Console 下载 `service-account.json`
- 放在项目根目录，或设置 `FCM_SERVICE_ACCOUNT_JSON_FILE` 环境变量

### 3. 运行部署脚本
```powershell
# 使用 Git Bash 或 WSL
./deploy.sh
```

---

## ✅ 验证 AWS 配置

运行以下命令验证配置：

```powershell
# 1. 验证 AWS 凭证
aws sts get-caller-identity

# 2. 验证区域
aws configure get region

# 3. 测试权限（列出 S3 buckets，验证基本权限）
aws s3 ls

# 4. 检查 Terraform 是否安装
terraform version
```

---

## 🔧 故障排除

### 问题 1: AWS 凭证无效
```powershell
# 重新配置 AWS 凭证
aws configure
# 输入 Access Key ID
# 输入 Secret Access Key
# 输入默认区域（us-east-1）
# 输入默认输出格式（json）
```

### 问题 2: 权限不足
- 检查 IAM 用户/角色是否有足够权限
- 确保附加了 `PowerUserAccess` 或自定义策略

### 问题 3: 区域不匹配
```powershell
# 设置区域
aws configure set region us-east-1
```

---

## 📚 相关文档

- [AWS CLI 配置指南](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [项目 README](./README.md)

