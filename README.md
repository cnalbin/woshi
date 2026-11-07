# 轻记 · iOS 热量账本

原生 SwiftUI 首版（iOS 17+），图标采用用户选定的“碗＋对勾”。

## 已实现

- 本机个人资料、Mifflin–St Jeor 静息代谢估算。
- 独立 AI 代谢分析，公式值 / AI 值 / 综合值并列展示。
- 综合参考规则为公式 80% + AI 20%，**未经临床验证**。AI 失败、资料变化或两值差异超过 20% 时退回公式值。公式结果不作为摄入目标。
- 手动记餐、补记日期、食物及克数/热量编辑、实际摄入比例、修改和删除。
- 相机和系统选图；上传前归一化、去除原始照片元数据并压缩。
- DeepSeek 图片分析；校验后的结果先进入草稿，由用户确认后入账。
- SSE 真实阶段通知、计时、取消、超时、保留照片草稿并重试。
- 展示简短估算依据与假设，**不转发或模拟内部思维链**。
- HealthKit 每日活动能量只读导入、按日替换汇总、后台变化通知及前台刷新，不重复加训练或步数热量。
- 记录/照片仅存本机、文件保护、排除自动备份，访问令牌保存在 Keychain。

## 目录

```text
ios/App/            SwiftUI 界面、网络、持久化、HealthKit、资源
ios/Core/           无 UI 依赖的模型、代谢与份量计算
ios/CoreTests/      公式、融合、输入、比例和跨日测试
server/             Node.js 22 后端，无第三方运行依赖
deploy/             Nginx / systemd 示例
scripts/            Xcode 工程生成、打包和 IPA 校验
.github/workflows/  macOS 编译、测试及 IPA Artifact
```

## 获取 IPA

在 GitHub Actions 的 **Build iOS IPA** 成功运行中下载 `QingJi-unsigned-IPA`，解压后得到 `QingJi-unsigned.ipa` 和 SHA-256 文件。也可在 Actions 页面手动运行 workflow。

**此 IPA 没有签名，不能直接安装。** 请使用自己的合法签名工具、证书和 provisioning profile。Bundle ID 默认 `com.cnalbin.qingji`，重签时可按工具要求修改。

HealthKit 需要签名身份 / App ID / provisioning profile 支持对应能力。请保留 `com.apple.developer.healthkit` 和 `com.apple.developer.healthkit.background-delivery` 权利；个人重签工具或签名方式可能无法提供这些能力。若不可用，手动和 AI 记餐仍可使用，但需要在真机验证活动读取。

本项目不包含签名证书、Apple 账号或 DeepSeek 密钥。

## 本地 Xcode 构建（Mac）

```bash
python3 scripts/generate_project.py
open ios/QingJi.xcodeproj
swift test
bash scripts/build-ipa.sh
```

项目无需 CocoaPods、SPM 外部依赖或 XcodeGen。编译脚本生成真实 ARM64 iPhoneOS 可执行程序，再将 `.app` 打包为 IPA，并检查 Mach-O、平台及资源。

## 部署 AI 服务

需要 Node.js 22。将 `server/.env.example` 复制成 `server/.env` 后，在服务器上填写：

```dotenv
DEEPSEEK_API_KEY=你的模型服务密钥
APP_ACCESS_TOKEN=自定义的至少32字符随机访问令牌
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_VISION_MODEL=deepseek-flash
DEEPSEEK_TEXT_MODEL=deepseek-flash
HOST=127.0.0.1
PORT=8787
```

可用 `node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"` 在你自己的服务器生成服务令牌。不要将密钥或 `.env` 提交到 GitHub。

```bash
cd server
npm test
npm start
```

使用已有域名和 HTTPS 反向代理到本机 8787。参考 `deploy/nginx.conf.example`，必须关闭代理响应缓冲，否则 AI 等待进度会滞后。Node 服务不要直接裸露到公网。systemd 模板中的路径、用户及 Node 路径需要按实际机器调整。

也可以 Docker 部署：

```bash
docker build -t qingji-api server
docker run -d --name qingji-api --restart unless-stopped --env-file server/.env -p 127.0.0.1:8787:8787 -e HOST=0.0.0.0 qingji-api
```

在 App 的 **我的 → AI 服务设置** 中输入后端 HTTPS 地址和 `APP_ACCESS_TOKEN`。这里不填写 DeepSeek 的 Key。首次调用前需要同意 AI 数据处理说明。配置后端前，公式计算和手动记录可离线使用。

服务为私人自用单用户设计，使用共享访问令牌、全局每小时限额和并发上限；公开多用户运营前应另行增加用户身份、分用户限额、滥用控制和部署地隐私说明。

模型名以 DeepSeek 官方 API 实际可用能力为准，均可由环境变量替换。此项目通过模型响应模拟测试验证协议；**没有模型凭据时不会声称已完成真实 DeepSeek 联调或精度验证**。

## API

- `GET /healthz`：服务存活，不调用模型。
- `POST /v1/analyze/meal`：`{imageBase64, note}`，JPEG/PNG 压缩后不超过 4 MB。
- `POST /v1/analyze/metabolism`：`{sex, age, heightCM, weightKG}`。
- POST 请求需 `Authorization: Bearer <APP_ACCESS_TOKEN>`。
- 成功请求返回 SSE：`progress`（received/analyzing/validating）→ `result`；失败为 JSON 错误或流中的 `error`。
- 没有食物、空结果、截断结果或非法数值不会保存为饮食。
- 请求取消会中止上游请求；默认 120 秒分析超时，10 秒保活。
- 后端不持久化照片和个人资料，不记录请求体、Authorization、模型内部推理或模型原始错误。

## 数据与估算边界

Mifflin–St Jeor 严格说是静息能量消耗估算；食物热量也可能受克数、用油、糖及烹饪影响。AI 没有取得额外测量数据时，并不比公式更准确。饮食目标由用户填写，App 不自动生成减重处方或计算“已实现缺口”。

本版没有云备份。卸载 App 可能丢失本机记录，请保留重要数据。HealthKit 返回空数据时无法判断是没有记录还是未获读取权限，界面不会伪装成 0 消耗或断言权限已授权。

## 验证范围

```bash
node --test server/test/server.test.mjs
python3 scripts/generate_project.py
# Mac / CI:
swift test
bash scripts/build-ipa.sh
```

测试覆盖服务鉴权、请求脱敏、真实 SSE 阶段、AI 结果校验、非食物、超时、取消、限流、公式、异常融合回退、份量、持久化编码和跨 DST 日期。

安装后的真机验收：首次资料保存 → 手动记餐 → 修改与删除 → 切换历史日期 → 配置服务 → 同意 AI 上传 → 拍照/相册分析 → 修改份量并确认 → AI 代谢分析 → 修改体重确认旧 AI 不再融合 → 连接健康并对照活动能量 → 杀进程重启检查记录。

真实模型调用、相机、HealthKit 读取与重签安装需要相应凭据及真机，CI 通过不等于这些项目已验证。

## 参考

- [DeepSeek Vision](https://api-docs.deepseek.com/guides/vision/)
- [DeepSeek JSON Output](https://api-docs.deepseek.com/guides/json_mode/)
- [代谢公式原始研究](https://pubmed.ncbi.nlm.nih.gov/2305711/)
- [HealthKit 授权](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
