---
id: doc-1
title: 把本地 Web 服务暴露到公网并配置认证
type: guide
created_date: '2026-06-17 02:35'
tags:
  - cloudflare
  - tunnel
  - access
  - authentication
  - devops
---
# 把本地 Web 服务暴露到公网并配置认证

使用 Cloudflare Tunnel + Cloudflare Access，将本地临时 web 服务（如 backlog.md web server）映射到公网域名，并配置用户认证。

本方案特点：
- 无需公网 IP，无需开放入站端口
- 免费（Zero Trust 免费层支持最多 50 用户）
- 支持多项目、多服务
- 认证支持 Google OAuth 和 Email OTP

---

## 一、安装并初始化 cloudflared（一次性）

```bash
# 安装（Ubuntu/Debian）
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
sudo dpkg -i cloudflared.deb

# 登录（打开浏览器，授权你的域名，生成 ~/.cloudflared/cert.pem）
cloudflared tunnel login

# 创建隧道（生成 ~/.cloudflared/<tunnel-id>.json）
cloudflared tunnel create <tunnel-name>

# 绑定 DNS（在 Cloudflare DNS 自动创建 CNAME 记录）
cloudflared tunnel route dns <tunnel-name> <subdomain>.<domain>
```

示例：

```bash
cloudflared tunnel create baime
cloudflared tunnel route dns baime baime.hwang.men
```

---

## 二、启动隧道（每次服务启动后运行）

```bash
nohup cloudflared tunnel \
  --credentials-file ~/.cloudflared/<tunnel-id>.json \
  run --protocol http2 --url http://localhost:<port> <tunnel-name> \
  > /tmp/cloudflared.log 2>&1 &
```

示例：

```bash
nohup cloudflared tunnel \
  --credentials-file ~/.cloudflared/a406029c-894d-40e6-80a9-ec6b0e5ae6d6.json \
  run --protocol http2 --url http://localhost:6422 baime \
  > /tmp/cloudflared.log 2>&1 &
```

验证连通（出现 4 条 connIndex=0~3 即正常）：

```bash
grep "Registered tunnel connection" /tmp/cloudflared.log
```

---

## 三、配置 Cloudflare Access 认证（一次性，全 API 操作）

### 准备凭证

在 `dash.cloudflare.com → My Profile → API Tokens` 创建 Token：

- 权限：`Cloudflare Zero Trust: Edit` + `Access: Apps and Policies: Edit`
- Account ID：从 dash URL 获取，或用以下命令查询：

```bash
curl -s "https://api.cloudflare.com/client/v4/accounts" \
  -H "Authorization: Bearer $CF_TOKEN" | jq '.result[0].id'
```

**注意：不要在聊天对话或版本控制中明文粘贴 Token。**

### 创建 Access Application

```bash
export CF_TOKEN="..."
export CF_ACCOUNT_ID="..."

curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/access/apps" \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "<app-name>",
    "domain": "<subdomain>.<domain>",
    "type": "self_hosted",
    "policies": [{
      "name": "Allow owner",
      "decision": "allow",
      "include": [{"email": {"email": "<your-email>"}}]
    }]
  }'
```

示例：

```bash
curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/access/apps" \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "baime",
    "domain": "baime.hwang.men",
    "type": "self_hosted",
    "policies": [{
      "name": "Allow owner",
      "decision": "allow",
      "include": [{"email": {"email": "calvino.huang@gmail.com"}}]
    }]
  }'
```

### 认证方式

创建 Application 后，登录页自动提供：

- **Email OTP**：输入邮箱，收验证码登录，无需额外配置
- **Google OAuth**：如果账号下已配置 Google IdP，自动可用

Google IdP 配置是账号级别的，一次配置对所有 Application 生效。

---

## 四、验证

```bash
curl -sI https://<subdomain>.<domain> | head -5
# 预期：HTTP/2 302 + Location: cloudflareaccess.com/... → 认证拦截生效
```

浏览器访问后，选择登录方式，通过认证后进入服务。

---

## 注意事项

- `--protocol http2` 必须显式指定，避免 UDP/QUIC 在某些网络环境下不稳定
- `--credentials-file` 必须显式指定，cloudflared 不会自动查找凭证文件
- API Token 只在创建时显示一次，立即保存到安全位置
- `CF_ACCOUNT_ID`（32位hex）和 `CF_TOKEN`（`cfut_` 前缀）格式不同，注意区分
- 多项目只需重复第一步创建新隧道，Access Application 可复用同一 IdP 配置
