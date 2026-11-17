# 代码来源与改动说明（CODE ORIGIN）

本文说明本仓库与上游项目的关系、相对上游的全部改动，以及这些改动已经过哪些验证、哪些还没有。凡是写"已验证"的，都以本仓库 `0.7.0+195` 工作树的真实记录为依据；凡是写"未覆盖"的，不因为措辞而视为通过。

## 1. 上游基线

- 上游项目：`mikufoxxx/Wenku8_Flutter`（GitHub）。
- 基线提交：`f2272e8`，对应上游 `v0.4.8`（2026-10-23）。
- 上游许可证：GPL-2.0-or-later（`LICENSE` 为 GPL v2 全文，含 "either version 2 of the License, or (at your option) any later version"；GitHub 识别为 GPL-2.0）。
- 本仓库整体按 **GPL-3.0** 分发：`README.md` 徽章、`NOTICE`、`docs/THIRD_PARTY.md`、`assets/licenses/GPL-3.0.txt` 均声明整体组合版为 GPL v3，原因是组合中包含 LGPLv3 组件（如 libmobi）与 Edge TTS 适配，GPLv2 与 LGPLv3 不兼容。LICENSE 正文与 NOTICE 需同时保留。
- 本仓库不是上游 0.5.x 源码快照的副本；没有使用上游 0.5.x 公开树中缺失的任何模块（局域网续读、听书增强、本地扫描、阅读小组件/报告等）。
- 本仓库版本 `0.7.0+195`。0.6.0 / 0.6.1 只调整版本号与文档。**0.7.0 按上游作者要求移除在线实现，与上游源码预览边界一致**：在线中转与登录会话持久化两个 Dart 模块已删除；`lib/legacy_transport.dart`、`lib/legacy_wenku_repository.dart`、`lib/wenku_account.dart`、`lib/wenku_reviews.dart`、`lib/legacy_cover.dart` 五个文件恢复为上游 `f2272e8` 的占位版本（在线方法统一抛"此源码构建未包含在线组件"）；删除依赖在线实现的测试；界面保留在线入口并显示"在线功能不可用"。第 5 节的自动化数字对应 0.7.0 工作树；真机记录中涉及账号、云书架、在线搜索的条目来自 `0.4.8+192` 在线版历史，已按实际情况标注。

## 2. 相对基线的改动总量

基线 `f2272e8` → 本仓库 `0.7.0+195`，共改动 **174 个文件**：

| 类型 | 数量 | 分布 |
|---|---|---|
| 新增 | 77 | `lib/` 8、`ios/` 33、`test/` 24、`integration_test/` 5、`test_driver/` 1、`docs/` 4、根目录 2（`CONTRIBUTING.md`、`LICENSE-GPL-2.0.txt`） |
| 修改 | 94 | `lib/` 31、`ios/` 6、`test/` 25、`integration_test/` 23、`docs/` 2、根目录 7（`pubspec.yaml`、`pubspec.lock`、`.gitignore`、`README.md`、`CHANGELOG.md`、`LICENSE`、`NOTICE`） |
| 删除 | 3 | 上游 CI 工作流 2（`flutter-ci.yml`、`sign-distribution.yml`）、`test/public_source_preview_test.dart` |

## 3. 新增模块（本项目自行实现）

### 3.1 Dart 业务模块（lib/，8 个）

| 文件 | 用途 |
|---|---|
| `lib/apple_capabilities.dart` | Spotlight 索引、快捷动作、`NSUserActivity` 的 Dart 侧桥接 |
| `lib/apple_reading_coordinator.dart` | Apple 原生阅读状态与 Flutter 阅读器的协调 |
| `lib/local_document_converter.dart` | 本地文档导入的格式分发入口 |
| `lib/local_document_encoding.dart` | 文本编码检测与解码 |
| `lib/local_epub_builder.dart` | 将导入内容生成为 EPUB |
| `lib/local_mobi_converter.dart` | MOBI / AZW / AZW3 / PRC 解析 |
| `lib/local_rtf_converter.dart` | RTF 转换 |
| `lib/route_transition_effects.dart` | 页面转场效果 |

> 0.7.0 之前另有两个自行实现的在线模块（在线中转与登录会话持久化），已按上游作者要求删除：本仓库不包含在线实现，也不描述其协议、端点或密钥。

### 3.2 iOS 原生插件（ios/Runner/，11 个）

`BookDocumentsPlugin.swift`（Files 文档读写）、`BookSyncDocuments.swift`（系统云文档同步）、`CloudSourcePlugin.swift`（网盘凭据）、`FrameRatePlugin.swift`（屏幕帧率能力）、`LanDiscoveryPlugin.swift`（Bonjour 局域网发现）、`LocalToolsPlugin.swift`（分享/照片/备份入口）、`NetworkStatusPlugin.swift`（NWPathMonitor）、`PdfImportPlugin.swift`（PDFKit 正文与页面图）、`ReaderStatusPlugin.swift`（原生时间/电量）、`SystemSpeechPlugin.swift`（AVSpeechSynthesizer 音色）、`AppleCapabilitiesPlugin.swift`（Spotlight/快捷动作/NSUserActivity）。

0.7.0 已删除 `WenkuSessionPlugin.swift`（网页登录/Keychain 会话）及其 Xcode 工程引用与 AppDelegate 注册；本仓库不再包含任何在线登录、会话或凭据实现。

### 3.3 测试体系（本项目新增）

- `test/`：163 个 Dart 测试文件 + 9 个格式 fixture（DOC/HTML/AZW3 等）；0.7.0 删除了 6 个依赖在线实现的测试文件（网络探测、传输层、在线仓库、中继、云书架同步，以及上游的源码预览边界测试），原先只有在线实现才能通过的用例一并移除；
- `integration_test/`：44 个集成测试文件；
- `ios/RunnerTests/`：`AppleCapabilitiesTests`、`BookSyncDocumentsTests`、`PdfImportTests`；
- `ios/RunnerUITests/`：15 个真机 UI 用例（阅读器、设置、听书、离线、导入、iPad、局域网、性能、快捷指令、工作流等；账号与云书架用例为 0.4.8+192 在线版历史）；
- `test_driver/integration_test.dart`。

## 4. 修改范围（按功能）

- **入口与外壳**：`lib/main.dart`、`lib/pages.dart`、`lib/app_ui.dart`；
- **书架与备份**：`lib/library_state.dart`、`lib/library_backup.dart`、`lib/backup_page.dart`；
- **阅读器**：`lib/reader_content.dart`、`lib/reader_status.dart`、`lib/reader_tools.dart`；
- **听书**：`lib/listening/controller.dart`、`models.dart`、`store.dart`、`widgets.dart`、`custom_tts.dart`；
- **本地导入**：`lib/local_book_importer.dart`、`lib/local_platform.dart`、`lib/local_import_settings_page.dart`；
- **离线**：`lib/offline_cache.dart`、`lib/offline_repository.dart`、`lib/offline_widgets.dart`；
- **书评页面**：`lib/review_pages.dart`（在线书评数据已随在线实现移除，页面入口保留并显示不可用）；
- **其他**：`lib/easy_glass.dart`、`lib/native_effects.dart`、`lib/network_status.dart`、`lib/novel_feed_controller.dart`、`lib/updates/app_updates.dart`、`lib/updates/current_release_content.dart`、`lib/updates/update_page.dart`、`lib/book_documents.dart`、`lib/lan_discovery.dart`、`lib/lan_reading_sync.dart`；
- **iOS 工程**：`ios/Podfile`、`ios/Runner.xcodeproj/project.pbxproj`、`ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`、`ios/Runner/AppDelegate.swift`、`ios/Runner/SceneDelegate.swift`、`ios/Runner/Info.plist`。

## 5. 验证状态

### 5.1 自动化测试（0.7.0+195 工作树）

```text
flutter analyze：No issues found!
完整 Dart：1153 通过，13 平台跳过，0 失败（2026-11-18 在 Flutter 3.41.5 / Dart 3.11.3 复跑）
关于/更新定向：69 通过
原生 XCTest：12 项通过（Apple 5、同步 2、PDF 5）
```

### 5.2 真机已验证（iPhone 17 Pro、iPad mini 6 / iPad14,2 / iOS 27.2；0.4.8+192 在线版历史证据）

- iPhone：账号、搜索、正文、听书、离线缓存、备份、主要设置、格式导入（账号与在线搜索为在线版历史证据，0.7.0 已移除在线实现）；
- iPad mini 6：原生 iPad 全屏、横竖屏、详情、目录、三种阅读模式、听书开始/暂停、设置；
- 云书架：云端 7 本全部进入本机，主书架可见（证据 `78-cloud-shelf-device.json`；在线版历史证据，0.7.0 云书架入口显示不可用）；
- 本地格式导入：TXT、EPUB、MOBI、AZW、AZW3、PRC、DOC、DOCX、FB2、HTML、Markdown、RTF、PDF 的导入、正文和重开；
- 用户确认可用：LAN 开关、Spotlight、锁屏听书、真实飞行模式跨章阅读、四个快捷指令（iPhone）；
- iPad mini 6 关于页：不含原作者宣传与原项目入口，许可入口存在；
- iPad mini 6 轻量偏好：有 FrameTiming 前后对比证据。

### 5.3 明确未覆盖（不得写成通过）

- 两台真实设备之间的完整 LAN 配对、传书和冲突恢复；
- 耳机插拔、来电、Siri、其他 App 抢占后的听书暂停与恢复；
- 真实屏幕 FPS 或完整 GPU 捕获；
- 部分 XCUITest 的搜索结果合成点击与系统自动化引导问题；
- 0.7.0 只验证了在线入口的"不可用"提示，未做任何在线请求验证（在线实现不在本仓库）；
- "验收矩阵中的每一行均完成真机验收"——矩阵逐项状态见归档 `evidence/全量功能验收矩阵.md`，其中标"待验收"的条目不属于通过。

### 5.4 证据归档

- `/Users/<you>/.ios-workflow/archive/com.zhujinyu.wenku8flutter/20261029-090229-b192/`：`Runner.app`、`Runner.dSYM`、`source/`（即 0.4.8+192 工作树历史快照，含当时 10 个新增 Dart 文件，其中 2 个在线模块已于 0.7.0 删除）、`evidence/`、`manifest.json`、SHA-256。

## 6. 来源声明

- 新增代码为本项目自行实现，未从任何 IPA / HAP / 二进制产物反编译、反汇编或解包获取。
- 格式解析与原生能力基于公开格式规范、Apple 公开框架（PDFKit、AVSpeechSynthesizer、NWPathMonitor、WidgetKit 等）以及 `docs/THIRD_PARTY.md` 列出的第三方组件。
- 未使用上游 0.5.x 公开源码快照中缺失的模块（该快照自身声明"包含未随快照提供的模块引用，不能独立构建"）；本仓库不声称与上游 0.5.x Release 二进制一一对应。
- Flutter AOT 产物不含可读 Dart 源码，无法从 `libapp.so` 还原业务实现。

## 7. 分发与许可

- 整树按 GPL-3.0-or-later 分发；保留 `LICENSE`、`NOTICE`、`docs/THIRD_PARTY.md`、`assets/licenses/GPL-3.0.txt`。
- 不添加禁止商用、禁止再分发或激活码等附加限制。
- 若分发二进制（如未签名 IPA），必须同时提供本仓库完整对应源码；修改后的版本继续按 GPL 分发。

## 8. 维护约定

后续任何代码改动都需要重新验证对应范围，不能沿用本文的旧结论。更新测试数字或验证范围时，同步更新本文件与 `README.md` 的相应章节。
