# 智能打卡助手

面向远程团队和个人习惯场景的无定位打卡系统。项目使用 Flutter 构建移动端、Rust/Axum 提供 API，并以 PostgreSQL 作为状态真源、Redis 作为限流与状态镜像。

当前版本实现上班/下班闭环、生物识别、设备登记、服务器校时、触控行为采集、幂等状态机、近七日工时和 GitHub Actions 编译。活体拍照、GeoIP/ASN 风险引擎及通知任务保留为后续能力。

## 工程结构

```text
.
├── backend/              # Axum、SQLx、Redis、迁移与单元测试
├── client/               # Flutter Android/iOS/Web 客户端
├── docs/                 # 设计依据与安全边界
├── compose.yaml          # PostgreSQL、Redis、后端本地环境
└── .github/workflows/    # 后端集成测试与 Flutter APK 编译
```

## 快速预览前端

未提供 `API_BASE_URL` 时，客户端自动进入演示数据模式，但点击打卡仍会调用真实系统生物识别。

在线 Web Demo：[myweb.mczihan.link/Check-in-tool](https://myweb.mczihan.link/Check-in-tool/)。Web 端用于界面预览，不提供浏览器生物识别打卡。

```sh
cd client
flutter pub get
flutter run
```

Android 最低 API 为 24，iOS 最低版本为 13。Android 使用 `FlutterFragmentActivity` 并声明 `USE_BIOMETRIC`，iOS 已配置 Face ID 用途说明。

## 启动完整环境

需要带 Compose 插件的 Docker 环境。

```sh
cp .env.example .env
docker compose up --build
```

本地配置默认开启开发令牌接口并允许模拟器，所有默认密钥仅可用于本机开发。生产环境必须替换密钥、关闭 `ALLOW_DEV_AUTH`、开启 `REJECT_EMULATORS`，并通过正式身份系统签发 JWT。

取得开发 JWT：

```sh
curl -X POST \
  -H "x-dev-auth-secret: local-dev-auth-secret-change-me-00000000" \
  http://127.0.0.1:8080/api/v1/auth/dev-token
```

启动客户端时传入 API 地址和返回的 `data.token`：

```sh
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1 \
  --dart-define=AUTH_TOKEN=YOUR_TOKEN
```

Android 模拟器使用 `10.0.2.2` 访问宿主机；iOS 模拟器可使用 `127.0.0.1`。首次连接时安全卡片会显示设备未登记，点击“登记此设备”，输入 `.env` 中的 `DEVICE_ENROLLMENT_TOKEN`。令牌只用于当前请求，不会被客户端持久化。

## API

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/health/live` | 进程存活状态 |
| GET | `/health/ready` | PostgreSQL/Redis 就绪状态 |
| GET | `/api/v1/time` | 服务器 UTC 时间 |
| GET | `/api/v1/dashboard` | 当前状态与近七日工时 |
| POST | `/api/v1/attendance/clock` | 幂等上班/下班打卡 |
| POST | `/api/v1/devices/trust` | 受控设备登记 |
| POST | `/api/v1/auth/dev-token` | 仅开发模式的 JWT 签发 |

除时间与健康检查外，业务接口从 `Authorization: Bearer ...` 的签名 JWT 提取用户身份，不接受 body 中的 `user_id`。

## 状态与并发

PostgreSQL 事务会先建立用户状态行，再通过 `SELECT ... FOR UPDATE` 串行化同一用户的状态流转。`request_id` 在用户维度唯一；网络重试使用相同请求内容时返回当前 Dashboard，不会重复落卡。Redis 中的 `user:{id}:state` 只在事务提交后刷新，因此缓存故障不会改变已提交结果。

合法状态流转：

```text
OffDuty --clock_in--> OnDuty --clock_out--> OffDuty
OnBreak ----------------clock_out---------> OffDuty
```

## Material 3 Expressive

Flutter 3.44.6 官方尚未原生提供完整 Material 3 Expressive 组件。本项目精确锁定 `m3e_core 0.1.2`，只通过局部组件使用其弹簧 Floating Toolbar、按钮和扩展形状；配色使用 Flutter 稳定版的 `DynamicSchemeVariant.expressive`，波形进度和加载态由本项目包装。这样可以获得 Expressive 体验，同时限制早期 `0.1.x` API 的迁移范围。

首页设计聚焦以下层级：

- Hero 时间卡：服务器校准时间、当前状态和当日实时工时。
- 近七日图表：`fl_chart` 工时柱状图，当前日使用更高色彩强调。
- 安全卡片：生物识别与信任设备状态，不只依赖颜色表达。
- Floating Toolbar：状态文案与打卡 FAB 配对，提交时切换形状加载动效。

详见 [`docs/design.md`](docs/design.md)。

## 验证

前端：

```sh
cd client
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test --concurrency=1
```

后端：

```sh
cd backend
CARGO_BUILD_JOBS=1 cargo fmt --all -- --check
CARGO_BUILD_JOBS=1 cargo clippy --locked --all-targets -- -D warnings
CARGO_BUILD_JOBS=1 cargo test --locked
```

`Backend CI` 额外启动 PostgreSQL 与 Redis，执行迁移、开发 JWT、设备登记、上班、幂等重试和下班烟雾测试。`Flutter CI` 使用 Flutter 3.44.6 执行格式检查、分析、Widget 测试并生成 debug APK artifact。

## 安全边界

本地生物识别只能证明系统在客户端放行了操作，不能向服务端提供不可伪造的证明；设备信息和触控轨迹也属于风险信号，不是认证因子。高风险生产场景还应接入 Play Integrity/App Attest、短期设备登记凭据、密钥轮换、GeoIP/ASN 数据和人工申诉流程。

服务器时间是考勤绝对基准，客户端校时只用于发现过期或异常请求。当前日界线和连续天数按 UTC 计算；面向跨时区正式使用前，应在用户模型加入 IANA 时区并定义工时归属规则。

完整威胁模型见 [`docs/security.md`](docs/security.md)。
