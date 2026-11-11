# 轻记 0.8.0

本次安装包文件名为 `QingJi-v0.8.0-build10-unsigned.ipa`，桌面名称为「轻记新版」。注册页及「我的」页显示「版本 0.8.0 · 构建 10」。App 的 Bundle ID 为 `com.cnalbin.qingji`。已登录时会进入首页，可在「我的 → NAS 账号」管理登录状态。

原生 iOS 17+ 热量账本。个人资料、静息代谢估算、手动记餐和历史记录可离线使用。拍照和 AI 代谢分析调用自建 NAS 后端，界面显示分析进度、取消和结果依据。

0.7.0 拍照初步识别后，有待确认项时先弹窗收集答案，再结合原图重新估算。第二轮成功后才进入食物与份量核对；无待确认项时直接显示结果。使用新流程需同时更新 NAS 后端。

0.6.0 可在「我的 → AI 模型设置」编辑两套提示词、恢复默认，并用草稿配置调试文字或图片。正式分析保留 JSON 字段及单位约定。调试结果可查看原文、耗时及模型返回的用量。DeepSeek 官方地址可刷新个人 API 账户余额。这些功能需要同时更新 NAS 后端。

## 0.5.0 界面与响应优化

统一米白背景、紧凑导航、深绿按钮与卡片；今日页保留摄入圆环、代谢、活动及饮食列表。趋势采用后台一次性汇总与最近时段缓存，离开页面取消旧任务，图表固定最多 62 根柱形并支持点击查看明细。苹果健康历史一次批量保存，无变化的记录不重复写盘或发布快照；缩略图在后台解码并缓存。

AI 显示服务器真实返回的阶段、耗时和处理记录，支持取消、重试与配置入口。结果列出食物、份量、热量与估算依据，照片结果经用户确认才保存。显示的是处理进度与结果依据。

自动化增加 730 天历史记录账号的连续周/月/年与底部标签切换、照片分析取消后重试和未确认不保存检查；核心汇总包含一万条记录性能测量、闰年、夏令时、缺失与零值语义检查。模拟模型用于自动化，不替代真机模型与健康权限验证。后端接口兼容 0.4.0，此次无需重新部署 NAS。

## 在飞牛 NAS 部署

后端使用 Python 3.13、FastAPI、SQLAlchemy 和 PyMySQL。Compose 只启动轻记容器，连接 NAS 已有的 MySQL。首次启动在指定数据库中创建 `qingji_*` 表。照片保存到单独挂载的目录。

1. 在现有 MySQL 中准备独立数据库（例如 `qingji`，字符集 `utf8mb4`）及专用账户。首次建表需要该库的 CREATE 权限，运行需要 SELECT、INSERT、UPDATE、DELETE。将连接权限限制在 NAS 或 Docker 网络，不开放 MySQL 到公网。
2. 把根目录的 `.env.example` 复制为 `.env`。将 `QINGJI_PHOTO_PATH` 改为真实的 NAS 绝对路径。提前创建该目录，并允许容器用户写入。默认 UID/GID 为 10001，可用 `QINGJI_UID` 和 `QINGJI_GID` 匹配专用 NAS 用户。
3. 把 `server/.env.example` 复制为 `server/.env`，填写 MySQL 地址、库名、用户名和密码。可以稍后在同一文件配置 `DEEPSEEK_API_KEY`，账号和备份功能可独立使用。
4. 根据 MySQL 位置运行以下一种命令。Docker 绑定默认仅监听 NAS 本机回环端口。

| MySQL 位置 | 配置与启动 |
|---|---|
| NAS 主机或局域网其他主机 | `MYSQL_HOST` 填容器可访问的地址。Linux NAS 主机也可用 `host.docker.internal`，前提是 MySQL 监听相应地址。执行 `docker compose up -d --build` |
| 另一个 Docker 容器 | 在根目录 `.env` 中设置 `QINGJI_MYSQL_NETWORK` 为现有自定义网络名，`MYSQL_HOST` 填 MySQL 在该网络的容器名或别名。执行 `docker compose -f compose.yaml -f compose.mysql-network.yaml up -d --build` |

NAS 本机执行 `curl --fail http://127.0.0.1:8787/healthz` 可验证服务和 MySQL 连接。若用宿主机 Nginx 提供 HTTPS，可参考 `deploy/nginx.conf.example`。如果反向代理也运行在容器里，将其加入后端可达的 Docker 网络并转发到轻记容器的 8787 端口。关闭反代响应缓冲以保留 AI 实时进度。手机端填写能访问、且证书受信任的 HTTPS 地址。

数据库密码和 DeepSeek Key 由 NAS 管理员配置。请勿提交真实 `.env` 文件。

## 创建和管理用户

在 NAS 的 Compose 项目目录执行。账号名使用 3–64 位小写英文字母、数字、点、下划线或连字符，首位为字母或数字。终端会提示输入至少 12 字符的密码。

```sh
docker compose exec qingji python -m qingji.manage create alice
docker compose exec qingji python -m qingji.manage create bob
docker compose exec qingji python -m qingji.manage reset-password alice
```

如果启动时指定了 `-p woshiqingji` 或多个 Compose 文件，运行管理命令时使用相同选项。App 内支持注册、登录和退出，也可由管理员创建账号。每个账号的资料、饮食、照片、代谢和活动备份相互隔离。重置密码会撤销该账号的现有会话。会话有效期为 30 天，过期后退出并重新登录以恢复 NAS 访问。

### 从 0.2 升级

保留原有 MySQL 配置和照片挂载，先备份数据库与照片目录，再重建容器。升级会自动创建账号和会话表。旧备份保留在原来的归属下。若有旧版数据，给原持有人创建第一个账号时运行以下命令，将原备份交给该账号。此选项只能成功使用一次。

```sh
docker compose exec qingji python -m qingji.manage create alice --legacy-owner
```

旧手机升级后，首次登录使用原持有人的账号。如果旧数据只在该手机，在填写新的个人资料前通过「管理 NAS 账号 → 导入此手机的旧记录」复制资料和照片。已有 NAS 数据会在登录后自动同步。旧版共享令牌默认停用，旧版客户端需要升级后才能连接账号备份。

## 账号自动同步与趋势

首次打开显示注册页，服务器默认为 `https://www.u2483924.nyat.app:63314`，可以修改。已有账号切换到登录。注册后进入首页，个人资料可后补，手动记录可直接使用。
App 在前台保存后自动同步，每30秒检查远端更新，换机登录自动加载记录与照片。离线修改留在本机，重新联网后重试。独立新增与删除按记录 ID 合并，同一记录同时修改时在「我的 → 数据同步」选择服务器或本机版本。旧版的备份 API 仍保持兼容。

「趋势」支持周、月、年。周/月按每天展示，年按月计算日均，可点月份和日期查看饮食。摄入和消耗分别按各自有数据的日期计算日均，缺失记录留空。活动能量从苹果健康读取，首次授权会导入最近730天可读取的汇总，健康权限需在每部手机独立授权。总消耗是当前综合代谢加活动能量的估算，修改资料会重新估算历史总消耗。

## 会员、额度和外观

新版「我的」提供会员中心、内置 DeepSeek、自定义模型及外观入口。免费账号累计有 100 次内置 AI 分析，订阅账号每个 Apple 订阅周期有 100 次。拍照待确认和补充后的最终估算合计一次。失败或取消可重试，重复提交同一已完成的请求复用结果。自定义模型走会员自己的 API 账户。

更新后端时保留原 MySQL 及照片目录。将 `server/.env` 中的 `MEMBERSHIP_ENABLED` 设为 `true` 可启用免费额度及会员权限。订阅准备完成前保持 Apple 验证配置为空，此时可查看页面和体验免费额度。已有的自定义模型配置在开通后可以继续使用。米白经典皮肤及系统、浅色和深色模式可直接使用，橙色、蓝色皮肤可预览，应用皮肤需要会员。

正式开通前，在 App Store Connect 为 `com.cnalbin.qingji` 创建月度自动续期订阅。默认商品 ID 为 `com.cnalbin.qingji.membership.monthly`，计划月费 ¥5.90，实际价格以 StoreKit 返回为准。在 `server/.env` 设置 `APPLE_APP_ID`、`APPLE_ROOT_CERTIFICATES` 和商品 ID（如与默认值不同）。证书路径使用容器内可读的绝对路径。通过 Apple PKI 获取根证书。在 App Store Connect 将服务端通知版本设为 V2，通知地址指向 `<后端 HTTPS 地址>/v1/membership/apple/notifications`。测试用后端设 `APPLE_ENVIRONMENT=Sandbox`，使用独立测试数据库。用与 App Store Connect 匹配的 App 签名和 Bundle ID 测试购买、恢复、续期及退款。

## 账号独立 AI 配置

在「我的 → 自定义模型」填写服务地址、API Key、文字模型、照片模型。保存后可设为当前模型，可编辑两套提示词、调试文字或图片，并查看 DeepSeek 余额。调试使用自己的 API Key，可能产生费用。
默认允许 `api.deepseek.com` 和 `api.openai.com`，可在服务器环境变量 `AI_ALLOWED_HOSTS` 配置其他管理员信任的域名（逗号分隔）。仅接受 HTTPS 默认443端口，不跟随跳转。模型配置为空的旧账号继续使用管理员的原配置。

API Key 使用 Fernet 加密存入 MySQL。加密密钥首次使用时自动保存在挂载照片根目录的隐藏文件 `.ai-encryption-key`。备份 NAS 时必须同时保存数据库、照片和这个隐藏密钥文件，否则无法解密已存的 API Key。读取配置接口只返回是否存在 Key。

## 签名和测试

在 GitHub Actions 的 `Build iOS IPA` 下载 `QingJi-unsigned-IPA`。IPA 需自行签名，默认 Bundle ID 为 `com.cnalbin.qingji`。要在真机使用活动能量读取，签名和描述文件须支持 HealthKit。

后端测试使用模拟 DeepSeek 响应。Windows 可在 `server` 中执行 `python -m pip install -r requirements-dev.txt` 和 `python -m pytest -q`。CI 使用独立 MySQL 容器，并构建 Python 后端镜像。iOS 构建可执行 `bash scripts/build-ipa.sh`，模拟器端到端测试执行 `bash scripts/test-ui.sh`（需预先安装 `server/requirements.txt`）。

## 参考

- [FastAPI 容器部署](https://fastapi.tiangolo.com/deployment/docker/)
- [SQLAlchemy MySQL 驱动](https://docs.sqlalchemy.org/en/20/dialects/mysql.html)
- [DeepSeek 图片输入](https://api-docs.deepseek.com/guides/vision/)
- [Mifflin–St Jeor 公式原始研究](https://pubmed.ncbi.nlm.nih.gov/2305711/)
