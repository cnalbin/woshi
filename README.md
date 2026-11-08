# 轻记 0.3.0

原生 iOS 17+ 热量账本。个人资料、静息代谢估算、手动记餐和历史记录可离线使用。拍照和 AI 代谢分析调用自建 NAS 后端，界面显示分析进度、取消和结果依据。

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

如果启动时指定了 `-p woshiqingji` 或多个 Compose 文件，运行管理命令时使用相同选项。NAS 管理员创建账号，App 内提供登录和退出。每个账号的资料、饮食、照片、代谢和活动备份相互隔离。重置密码会撤销该账号的现有会话。会话有效期为 30 天，过期后退出并重新登录以恢复 NAS 访问。

### 从 0.2 升级

保留原有 MySQL 配置和照片挂载，先备份数据库与照片目录，再重建容器。升级会自动创建账号和会话表。旧备份保留在原来的归属下。若有旧版数据，给原持有人创建第一个账号时运行以下命令，将原备份交给该账号。此选项只能成功使用一次。

```sh
docker compose exec qingji python -m qingji.manage create alice --legacy-owner
```

旧手机升级后，首次登录使用原持有人的账号。如果旧数据只在该手机，在填写新的个人资料前通过「管理 NAS 账号 → 导入此手机的旧记录」复制资料和照片。已有 NAS 备份时可直接选择恢复。旧版共享令牌默认停用，旧版客户端需要升级后才能连接账号备份。

## 手机备份与换机恢复

- 在首次录入页或「我的 → NAS 账号」使用 NAS 地址、用户名和密码登录。在「我的 → NAS 备份与恢复」启用备份或点击「立即备份」，确认成功后再换机。
- 新手机登录同一 NAS 的同一账号，再点击「从 NAS 恢复」。App 先校验并下载照片，恢复前保留本机副本。恢复后可以继续开启自动备份。
- NAS 保存个人资料、已确认的饮食及照片、代谢结果和已读取的每日活动汇总。AI 同意状态留在本机。HealthKit 权限需在新设备上重新授予，原始 HealthKit 样本不会存入备份。
- 本版支持前台自动备份和手动恢复，采用版本检查。旧设备检测到新版本后停止上传，保留本机数据供检查。不会自动合并两台设备独立修改的记录。
- 备份 NAS 本身时，同时保存 MySQL 的应用数据库和照片目录。已从饮食记录移除的照片内容仍可能留在 NAS 照片目录，当前版本没有自动清理。

## 签名和测试

在 GitHub Actions 的 `Build iOS IPA` 下载 `QingJi-unsigned-IPA`。IPA 需自行签名，默认 Bundle ID 为 `com.cnalbin.qingji`。要在真机使用活动能量读取，签名和描述文件须支持 HealthKit。

后端测试使用模拟 DeepSeek 响应。Windows 可在 `server` 中执行 `python -m pip install -r requirements-dev.txt` 和 `python -m pytest -q`。CI 使用独立 MySQL 容器，并构建 Python 后端镜像。iOS 构建可执行 `bash scripts/build-ipa.sh`，模拟器端到端测试执行 `bash scripts/test-ui.sh`（需预先安装 `server/requirements.txt`）。

## 参考

- [FastAPI 容器部署](https://fastapi.tiangolo.com/deployment/docker/)
- [SQLAlchemy MySQL 驱动](https://docs.sqlalchemy.org/en/20/dialects/mysql.html)
- [DeepSeek 图片输入](https://api-docs.deepseek.com/guides/vision/)
- [Mifflin–St Jeor 公式原始研究](https://pubmed.ncbi.nlm.nih.gov/2305711/)
