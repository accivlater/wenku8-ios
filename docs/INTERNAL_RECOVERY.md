# 轻小说文库：iPhone / iPad 迁移、恢复与验收手册

> 本文是项目的**单文件恢复入口**。目标不是介绍宣传页面，而是让下一个 Agent 即使只看到这一份 README，也能从 Android 参照源码重新建立 Flutter iOS/iPadOS 工程、恢复关键能力、执行测试并完成真机交付。
>
> 当前项目已经完成 Android → Flutter → iPhone 迁移，并在 iPhone 和 iPad mini 第六代上实际使用。**不要重做整个迁移，不要把现有工作树当成空壳。**
>
> 文档对应版本：`0.4.8+192`，更新于 2026-10-29。

## 0. 先读：恢复时必须遵守的边界

### 0.1 项目身份

这是用于 iPhone 和 iPad 的第三方轻小说阅读器，0.7.0 起按上游作者要求只保留本地能力，支持：

- 本机书架、阅读进度、书签、分类和历史。
- 本地书籍导入、离线缓存、横排、竖排、滚动和宽屏对页。
- 自然在线听书（Edge TTS 等语音接口）、Apple 系统语音、自定义语音。
- 局域网续读、文件同步、备份恢复。
- Files、照片、Spotlight、快捷指令、触感、深浅色和 iPad 横竖屏。

在线实现（文库账号、云书架、在线书目/搜索/正文、书评、在线封面）**不在本仓库**：界面对应入口保留并显示“在线功能不可用”，源码中只有占位实现，详见第 5、6 节。

本项目不运营在线书库，不自行发布小说资源，安装包不附带小说文件。小说、封面和插图的权利属于各自权利人；不要绕过付费、版权或 DRM 限制。

### 0.2 数据与账号安全

- 不读取、输出、复制到日志或提交密码、Cookie、令牌、钥匙串内容。
- 本仓库不含在线实现，因此不再产生账号会话与续期凭据；LAN 配对密钥仍只放 Keychain。
- 不卸载 App，不清除书籍、缓存、设置或阅读记录。
- 同一 Bundle ID 原地升级，不用“先卸载再安装”的方式处理升级。
- 备份和恢复必须显式排除密码、Cookie、令牌及 LAN 配对秘密。

### 0.3 工作树与依赖

- 不使用 `git reset`、`git clean`，不提交或推送，除非用户另行明确要求。
- 不擅自升级 Flutter、Dart、Xcode、CocoaPods 或项目依赖。
- 不重改已经验证的转场性能、快捷指令和阅读器逻辑，除非有新的实测回归。
- 不把模拟器、测试装配成功、截图非空白或进程存活冒充真机功能通过。
- 不把“代码已存在”写成“功能已验收”；每个结论必须注明证据和限制。

## 1. 当前工程与恢复所需来源

### 1.1 当前路径

```text
工作区：
/Users/<you>/DSH仓库镜像/study-thinking-2026

项目根：
/Users/<you>/DSH仓库镜像/study-thinking-2026/程序类/Wenku8_Flutter-iOS迁移-20261025

Flutter App：
/Users/<you>/DSH仓库镜像/study-thinking-2026/程序类/Wenku8_Flutter-iOS迁移-20261025/app

Android 参照源码：
/Users/<you>/DSH仓库镜像/study-thinking-2026/程序类/Wenku8_Flutter-iOS迁移-20261025/reference-android

固定 Flutter SDK：
/Users/<you>/DSH仓库镜像/study-thinking-2026/程序类/Wenku8_Flutter-iOS迁移-20261025/.toolchain/flutter
```

本文中的所有相对路径，除特别说明外，均相对 `app/`。

### 1.2 如果项目丢失，先恢复这些来源

1. 找回当前归档中的 `source/`，它是已验证 iOS 实现的直接源码，不需要重新迁移。
2. 只有当前源码也丢失时，才从 Android 参照源码重新迁移：
   - 上游 Android 项目：`MewX/light-novel-library_Wenku8_Android`。
   - 本次参照的主体是 `studio-android/LightNovelLibrary/`。
   - 重点读取 `app/src/main/java/org/mewx/wenku8/` 和对应测试，不要从已经停止维护的 Eclipse 版本开始。
3. 获取相同 Flutter 工程依赖时，以 `pubspec.yaml`、`pubspec.lock`、`third_party/` 为准；不要用最新依赖重新猜测组合。
4. 恢复 `assets/`、`shaders/`、`third_party/` 和字体/图标许可文件。仅复制 Dart 文件无法得到可运行的 App。
5. 恢复测试与证据目录，以便区分“已验证行为”和“重新实现后待验证行为”。

**README 能指导恢复流程，但不替代源码、签名身份、外部服务和用户数据。** Apple 签名、真实账号、密码、Cookie 和用户书籍不应写在 README 中。

### 1.3 当前可恢复归档

编写本文时，最近的完整二进制基准为：

```text
/Users/<you>/.ios-workflow/archive/com.zhujinyu.wenku8flutter/20261029-090229-b192/
```

其中包含 `Runner.app`、`Runner.dSYM`、`source/`、`evidence/`、`manifest.json` 和 SHA-256。README 专项归档路径记录在本文件末尾及 `../续迁移进度-20261026.md` 最新一节。

## 2. 固定构建与设备信息

| 项目 | 当前值 |
|---|---|
| Flutter | 3.41.5 |
| Dart | 3.11.3 |
| Xcode | 27.1 |
| iOS 最低目标 | 15.0 |
| App 版本 | 0.4.8+192 |
| Bundle ID | `com.zhujinyu.wenku8flutter` |
| Apple Team | 上游工程曾使用的 Team ID，已从工程文件移除 |
| 设备族 | `TARGETED_DEVICE_FAMILY=1,2` |
| iPad 真机 | iPad mini 第六代，`iPad14,2`，iOS 27.2 |
| iPad UDID | `<UDID>` |
| iPhone 参照真机 | iPhone 17 Pro |
| iPhone UDID | `<UDID>` |

UDID 只用于复现本次环境。之后执行真机操作时必须重新运行 `xcrun devicectl list devices`，不要猜设备，也不要把 iPad 模拟器当成 mini 第六代。

环境初始化：

```bash
cd "/Users/<you>/DSH仓库镜像/study-thinking-2026/程序类/Wenku8_Flutter-iOS迁移-20261025/app"
export FLUTTER_ROOT="/Users/<you>/DSH仓库镜像/study-thinking-2026/程序类/Wenku8_Flutter-iOS迁移-20261025/.toolchain/flutter"
export PATH="$FLUTTER_ROOT/bin:/opt/homebrew/bin:$PATH"
flutter --version
flutter pub get
```

如果从其他目录或归档恢复，把 `FLUTTER_ROOT` 改为实际的同版本 SDK 路径。不要通过全局 `flutter upgrade` 解决构建问题。

### 2.1 直接依赖的锁定版本

恢复工程时以 `pubspec.lock` 为最终准绳。当前直接依赖的锁定版本如下，不要用各包最新版本代替：

| 依赖 | 锁定版本 | 依赖 | 锁定版本 |
|---|---:|---|---:|
| cupertino_icons | 1.0.9 | shared_preferences | 2.5.5 |
| material_color_utilities | 0.13.0 | path_provider | 2.1.6 |
| xml | 7.0.1 | audio_service | 0.18.19 |
| audio_session | 0.2.4 | just_audio | 0.10.6 |
| crypto | 3.0.7 | objective_c | 9.5.0 |
| archive | 4.5.2 | html | 0.15.7 |
| csslib | 1.0.2 | tategaki | 0.6.4 |
| characters | 1.4.1 | cryptography | 2.9.0 |
| diff_match_patch | 0.4.1 | flutter_markdown_plus | 1.0.12 |
| markdown | 7.3.1 | url_launcher | 6.3.3 |
| vm_service（开发） | 15.3.0 | flutter_lints（开发） | 6.0.0 |

`liquid_glass_easy` 使用 `third_party/liquid_glass_easy` 本地路径，`pubspec.lock` 锁定 5.0.0，不改成 pub 版本。`shared_preferences_platform_interface` 2.4.2 与 `path_provider_platform_interface` 2.1.3 也保留在开发依赖中。

## 3. 总体架构与启动流程

### 3.1 架构分层

```text
Android Java 参照实现
        │ 行为、API、数据含义、边界用例
        ▼
Flutter Dart 共享层
        ├─ catalog / repository / LibraryState
        ├─ 页面、阅读器、听书、同步与本地格式
        ▼
Flutter MethodChannel / EventChannel
        ▼
iOS Swift 原生层
        ├─ Keychain、Files、Photos、PDFKit、AVSpeech
        ├─ Bonjour、NWPathMonitor、Spotlight、AppIntents
        └─ SceneDelegate / 系统生命周期
```

原则：

- API 语义、书籍 ID、章节 ID、阅读锚点和同步行为优先保持跨平台一致。
- UI 可以按 iPhone/iPad 重排，但不能改变数据含义。
- Android 专属文件路径、JNI、共享存储、系统 TTS 和通知机制不能直接照搬到 iOS。
- iOS 专属能力通过 Swift 插件接入，不在 Dart 中伪造系统结果。

### 3.2 `lib/main.dart` 启动顺序

1. 初始化 Flutter binding、许可、触摸采样和系统 UI。
2. `LibraryState.load()` 恢复偏好、书架、阅读位置、书签和样式。
3. 加载系统配色、语言、字体和 `NetworkStatus`。
4. 创建 `WenkuAccount`、`LegacyWenkuRepository`。
5. 在 iOS/Android 上创建 `OfflineNovelRepository`，组合：
   - 远程 `LegacyWenkuRepository`；
   - `OfflineCacheStore.forApp()`；
   - `LocalBookStore.forApp()`；
   - 原生网络状态。
6. 恢复本地系列关系。
7. 创建 `WenkuFeatures`，其中包含账号、出版文库和 `WenkuShelfSync`。
8. 创建听书控制器与音频缓存。
9. `runApp(NovelApp(...))`。
10. 后台注册听书服务并调用 `account.initialize()`，不让账号恢复阻塞首帧。
11. `NovelApp` 继续初始化 LAN、Apple 阅读协调器及系统入口。

修改启动逻辑时，保持“首屏先显示、账号异步恢复”，不要在首帧前串行等待所有网络请求。

## 4. Android → Flutter/iOS 模块映射

| Android 参照 | 当前实现 | 迁移要点 |
|---|---|---|
| `MyApp.java`、Activity/Fragment | `lib/main.dart`、`lib/pages.dart`、`lib/my_page.dart` | 改为声明式路由和状态监听，不复制 Activity 生命周期 |
| `global/api/Wenku8API.java` | `lib/legacy_transport.dart`（上游占位版） | 在线请求实现不随源码发布，占位方法直接返回“不可用” |
| `global/api/*Parser*.java` | `lib/legacy_wenku_repository.dart`、`lib/wenku_account.dart`、`lib/wenku_reviews.dart`（均上游占位版） | 仅保留 `Novel`、章节、账号和书评模型定义，在线解析已移除 |
| `NovelItemMeta`、`ChapterInfo`、`VolumeList` | `lib/catalog.dart`、`lib/book_navigation.dart` | 保留 aid/cid/vid 和目录关系 |
| 阅读 Activity、Paginator | `lib/pages.dart`、`lib/reader_*.dart` | 分页、滚动、竖排、插图、书签和位置恢复分别实现 |
| `LightCache`、设置存档 | `lib/library_state.dart`、`lib/offline_cache.dart`、`lib/local_books.dart` | 改为偏好、JSON 元数据与文件正文分层，不照搬 SD 卡路径 |
| `BookshelfSync` | `lib/wenku_shelf_sync.dart` | 合并算法保留，但在线实现移除后不会执行，入口显示不可用 |
| Android 文件选择/JNI | `lib/book_documents.dart`、`ios/Runner/BookDocumentsPlugin.swift` | 改用 UIDocumentPicker、安全作用域资源与应用沙盒 |
| Android 系统 TTS | `lib/listening/`、`ios/Runner/SystemSpeechPlugin.swift` | 改用 AVSpeech；在线语音随在线实现移除 |
| Android 本地广播 | `lib/lan_*`、`ios/Runner/LanDiscoveryPlugin.swift` | 改用 Bonjour/NWBrowser 和本地网络权限 |
| Android 桌面/搜索能力 | `lib/apple_*.dart`、`ios/Runner/AppleCapabilitiesPlugin.swift` | 改用 Spotlight、NSUserActivity、AppIntents |

重新迁移时，先完成模型、协议和数据，再接 UI。不要先画一套外观相似但数据不兼容的壳。

## 5. 在线协议（已按上游作者要求移除）

0.7.0 起本仓库不包含任何在线协议实现：请求编码、签名算法、中转端点、会话凭据与云书架同步都不随源码发布，本文也不再保留其示例值。原始在线实现只存在于 0.6.1 及更早的版本，相关历史已被重写并弃用。

界面侧保留在线入口；点击后由 `lib/online_component.dart` 的统一占位返回“此源码构建未包含在线组件，可继续使用本地导入与阅读”（`unavailableOnline()`）。`lib/legacy_transport.dart`、`lib/legacy_wenku_repository.dart`、`lib/wenku_account.dart`、`lib/wenku_reviews.dart`、`lib/legacy_cover.dart` 均为上游 v0.4.8 的占位版本，在线方法直接抛不可用。**不要在维护时补回任何请求实现**；确需在线能力时，先取得上游作者授权，并同步更新本文与 `docs/CODE_ORIGIN.md` 的边界说明。

### 5.1 核心数据模型（本地仍在使用）

`lib/catalog.dart` 中的 `Novel` 至少保留：

- `id`：在线书籍 aid；本地书使用保留 ID 区间。
- `title`、`author`、`genre`、`summary`。
- `chapters`：每章含稳定 `id`、`volumeId`、`volumeTitle`。
- `chapterCount`、`coverUrl`、`lastUpdate`、`isComplete`。
- `navigation`：作者目录与阅读资源之间的映射。

本地书从 `localBookIdStart = 0x60000000` 开始分配。在线 ID 与本地 ID 不得混用。

阅读位置不能只保存屏幕像素。`ReadingPosition` 包含：

- 章节索引、稳定章节 ID、offset、fraction、fontSize、width、updatedAt。
- 段索引、段内比例、原段落 UTF-16 `textOffset`。
- 字体、排版和内容修订标识。

恢复时优先使用稳定章节 ID 和原文锚点，再根据当前屏幕重新排版。否则旋转、字体变化或跨设备同步后会跳错位置。

## 6. 账号与云书架（在线实现已移除）

0.7.0 起账号登录、会话续期与云书架同步都不在本仓库中：

- `lib/wenku_account.dart` 为上游占位版，登录、续期与资料接口直接返回不可用；界面“账号”入口保留并提示在线功能不可用。
- 会话持久化实现已随 `ios/Runner/WenkuSessionPlugin.swift` 一并删除（含 Xcode 工程引用与 AppDelegate 注册）；本仓库不再包含在线登录或会话持久化代码。
- `lib/wenku_shelf_sync.dart` 的合并算法仍在上游代码中，但没有可用的账号与云端接口，实际不会执行；`LibraryState.applyCloudShelf` 与 `shelfRevisions` 保留，供将来（在获得授权的前提下）重新接入时使用。
- 退出账号、切换账号等入口保留为界面占位；不会清空本机书架、阅读进度、书签与缓存——本地数据的归属始终是本机。

若将来重新接入在线能力，必须由上游作者授权后另行实现，并同时更新本文与 `docs/CODE_ORIGIN.md`；不要从旧历史、归档或二进制产物里恢复端点与密钥。

## 7. 本地数据、备份与同步文件

### 7.1 `LibraryState` 的主要偏好键

| 键 | 内容 |
|---|---|
| `shelf` | 书架 ID 字符串列表（历史键名保留；云端书架入口已不可用） |
| `chapter_<id>` | 旧章节索引/历史 |
| `shelf_added_<id>` | 加入书架时间 |
| `novel_meta_<id>` | 书籍快照 JSON |
| `reading_position_<id>` | 阅读位置 JSON |
| `reader_bookmarks_<id>` | 书签列表 JSON |
| `illustration_layout_<id>` | 插图布局 JSON |
| `reader_style_<id>` | 每书阅读样式 |
| `reading_history_hidden` | 隐藏历史 |
| `local_shelf_hidden` | 已移出的本地书 |
| `recentSearches` | 最近搜索 |

损坏的单条缓存不能导致整个书架或其他阅读记录被删除。提交书架、位置和书签时使用串行写入队列及恢复屏障，避免中断造成半写入状态。

### 7.2 在线离线缓存

`OfflineCacheStore.forApp()` 位于 Application Support 的 `wenku8-offline-v1/`：

```text
b<aid>/
  c<cid>.txt             正文
  <图片摘要文件>          插图
  元数据/目录快照         按当前实现保存
```

要求：

- 单章正文与插图均有大小限制；网络返回 generations 过期时不得覆盖新内容。
- 缓存章数与插图数分开报告。
- 失败插图可单独重试；正文缓存成功不等于全部插图成功。
- 删除缓存不能顺带删除书架、进度或书签。

### 7.3 本地备份

`LibraryBackup` 的 JSON 外层：

```json
{
  "format": "wenku8-local-backup",
  "version": 1,
  "createdAt": 0,
  "records": {}
}
```

- 最大 4 MiB。
- 恢复前必须预览并显式确认。
- 支持合并、非法记录隔离、写入前副本和中断恢复。
- 不包含密码、Cookie、令牌、Keychain 或 LAN 配对秘密。

### 7.4 `.wenku8sync` 文件

`book_sync.dart` 使用 ZIP，包含：

```text
manifest.json       format=wenku8-book-sync，version 1 或 2
library.json        LibraryBackup
books/<n>/original  原始书文件
books/<n>/decoded.txt 可选解码正文
book-info.json      可选书籍元数据
```

同步文件最大 256 MiB，最多 200 本书，读取时限制展开大小和条目大小。系统云文档同步必须处理冲突、写后回读和恢复副本，不能直接覆盖较新的记录。

## 8. 本地书籍与格式迁移

### 8.1 支持范围

| 格式 | 单文件上限 |
|---|---:|
| EPUB / PDF / DOCX / ZIP | 512 MiB |
| MOBI / AZW / AZW3 / PRC | 256 MiB |
| TXT / FB2 / RTF / DOC | 128 MiB |
| HTML / HTM / XHTML / Markdown | 32 MiB |
| ZIP 展开合计 | 1 GiB |

ZIP 最多 200 本书，支持逐项失败而保留其他成功项。不要把损坏 ZIP 当成全部书籍导入成功。

### 8.2 实现分层

- `local_document_converter.dart`：格式识别、ZIP、安全限制和转换调度。
- `local_epub_builder.dart`：把其他格式重建为 EPUB，保留原文件于 `META-INF/wenku8-original/`。
- `local_mobi_converter.dart`：Kindle 本地解析，不解密 DRM。
- `local_rtf_converter.dart`：RTF/DOC 兼容分支。
- `local_books.dart`：TXT/EPUB 解析、内容摘要、章节与资源索引。
- `ios/Runner/PdfImportPlugin.swift`：PDFKit 文本与大页面图片提取。
- `ios/Runner/BookDocumentsPlugin.swift`：Files、读取、释放和安全作用域。

本地 ID 由原内容 SHA-256 派生，使同一本书跨设备保持身份；完整 digest 还用于处理截断 ID 碰撞。

### 8.3 iOS 与 Android 的差异

- iOS 使用复制到应用沙盒的方式，不沿用 Android“关联共享存储原文件”的模式。
- Files 授权只在用户主动操作时申请，取消不产生导入。
- 外部文件删除或权限变化不能影响已经完整导入的书籍。
- 临时 staging 必须释放；成功导入不依赖临时文件继续存在。
- 大文本解码和转换放到后台，保持 UI 心跳。

真机已覆盖 TXT、EPUB、MOBI、AZW、AZW3、PRC、DOC、DOCX、FB2、HTML、Markdown、RTF、PDF 的导入、正文和重开。后续改代码仍需重新验证，不能永久沿用旧结论。

## 9. 书架、阅读器与听书

### 9.1 书架与阅读历史

相关文件：

```text
lib/pages.dart
lib/library_workspace.dart
lib/library_toolbar.dart
lib/local_library_page.dart
lib/local_library_preferences.dart
lib/reading_history.dart
```

必须保持：

- 书架筛选与排序不修改原始收藏（云端书架入口已不可用，本地书架行为不变）。
- 移出收藏不删除进度、书签或缓存。
- 撤销恢复加入时间和位置。
- 本地分类、系列合并和隐藏书记录重开后保持。
- 搜索范围明确区分发现、书架和本地；快捷搜索先切到发现范围。

### 9.2 阅读器

主要组件：

- `reader_pagination.dart`、`reader_paged_view.dart`：横排分页。
- `reader_scroll_stream.dart`、`reader_scroll_sliver.dart`：连续滚动与跨章。
- `reader_vertical_text.dart`、`reader_embedded_vertical.dart`：竖排。
- `reader_book_layout.dart`：宽屏对页、铰链/折叠区域。
- `reader_catalogue.dart`、`reader_book_progress.dart`：目录与进度。
- `reader_annotations.dart`、`reader_find.dart`：书签、选句和查找。
- `reader_illustrations.dart`、`reader_rich_content.dart`：插图和富文本。

行为要求：

- 横排、竖排、滚动之间切换后恢复原阅读位置。
- 显隐控件不能无意义地跳段；正文重排以原文锚点为准。
- 宽屏对页要求有效区域至少满足当前 720/220/300 阈值，文字不跨铰链。
- 目录使用稳定章节 ID；显示标题不能错误套用到另一资源。
- 插图失败不能阻塞可读正文。

### 9.3 听书

`ListeningController` 统一协调：

- 自然在线音色和既有 SSML/Edge 协议。
- Apple 系统语音 `AVSpeechSynthesizer`。
- 自定义语音接口。
- 预缓存、语段进度、暂停/继续/停止、跳转、睡眠定时。
- 后台与锁屏媒体控制。

注意：

- 音频时间戳不能直接驱动整页或书架重建。
- 暂停、换音色或跳章后取消旧的待播内容。
- Apple 系统语速范围是 0.5～2.0；其他音源可沿用各自范围，不要把 3.0 传给 Apple。
- iOS 的 `getTemporaryDirectory()` 对应 `Library/Caches`，原生插件必须接受该路径，不能只允许 `tmp`。
- 耳机、来电/Siri/其他 App 音频中断仍需独立真机验证。

## 10. 云书架之外的同步：LAN 与系统云文档

### 10.1 LAN 续读

相关文件：

```text
lib/lan_reading_sync.dart
lib/lan_discovery.dart
lib/lan_pairing.dart
lib/lan_transfer_cipher.dart
lib/library_incremental_sync.dart
lib/lan_book_handoff.dart
ios/Runner/LanDiscoveryPlugin.swift
```

协议和约束：

- Bonjour 服务：`_wenkuread._tcp`。
- 默认端口：38762。
- 私网地址校验覆盖 IPv4/IPv6，拒绝公网目标。
- 首次配对需要双方确认六位数字；最多 8 台设备。
- AES-GCM 256 加密，密钥只来自显式配对并存入 Keychain。
- 请求带时间戳，允许的设备时间误差为 5 分钟。
- 后台停止服务，前台恢复；每 15 秒轮询，变更后 700ms 防抖。
- 阅读进度按更新时间和稳定书籍身份合并。
- 书签和分类通过增量 journal 同步，冲突由用户选择。
- 缺书时经确认传书；已有同一本书时只传续读位置。

**云账号同步与 LAN 是独立路径。** 登录账号不会自动完成 LAN 配对，LAN 开关也不能证明云书架正常。本轮云书架真机通过不代表双机 LAN 已通过；双机 LAN 仍需两台真实设备验收。

### 10.2 系统云文档

`BookSyncDocuments.swift` 与 `cloud_book_sync_panel.dart` 负责 Files 提供方中的同步文件：

- 使用安全作用域书签。
- 比较修改时间和内容，冲突不覆盖较新版本。
- 写入后回读。
- 保留上次完整副本和写入前副本。
- 断开连接只移除连接，不删除本机书籍。

## 11. iOS 原生插件清单

`AppDelegate.didInitializeImplicitFlutterEngine` 注册全部插件。新增插件时，Dart channel、Swift 注册和测试必须同时更新。

| Channel / 插件 | 用途 |
|---|---|
| `org.mewx.wenku8/session` | 网页登录、Keychain 会话和续期凭据 |
| `org.mewx.wenku8/book_documents` | Files、文档读取、暂存、释放、外部打开 |
| `org.mewx.wenku8/pdf_import` | PDFKit 正文和页面图片 |
| `org.mewx.wenku8/cloud_sources` | 网盘凭据的 Keychain 存储 |
| `org.mewx.wenku8/system_speech` | Apple 音色、合成、缓存与设置入口 |
| `org.mewx.wenku8/network_status` + `network_events` | NWPathMonitor 当前状态与事件 |
| `org.mewx.wenku8/frame_rate` | 屏幕帧率能力与内存偏好；不强制高刷 |
| `org.mewx.wenku8/local_tools` | 分享、照片、备份 Files、亮屏等 |
| `org.mewx.wenku8/reader_controls` | 阅读器系统控制与窗口行为 |
| `org.mewx.wenku8/reader_status` | 原生时间和电量 |
| `org.mewx.wenku8/lan_reading_config` | LAN 配对配置 Keychain 与旧值迁移 |
| `org.mewx.wenku8/lan_discovery` + 事件 channel | Bonjour 发现与广播 |
| `org.mewx.wenku8/apple_capabilities` | Spotlight、快捷动作、NSUserActivity |
| `org.mewx.wenku8_flutter/haptics` | UIKit 触感与强度 |

`SceneDelegate` 负责冷启动和运行中的 `NSUserActivity` 交付。快捷动作需要去重，不能因冷启动队列和后续回调重复执行。

## 12. iOS 工程配置与权限

### 12.1 `Info.plist` 当前关键点

- Scene 配置使用 `SceneDelegate`，不启用多 Scene。
- 后台模式只声明实际需要的 `audio`。
- 打开文档：`UIFileSharingEnabled`、`LSSupportsOpeningDocumentsInPlace`。
- 本地网络：`NSLocalNetworkUsageDescription` 和 `_wenkuread._tcp`。
- 照片只添加：`NSPhotoLibraryAddUsageDescription`，不读取旧照片。
- iPad 支持竖屏、倒置竖屏和两种横屏。

### 12.2 快捷动作 activity 类型

```text
org.mewx.wenku8.open-book
org.mewx.wenku8.continue-reading
org.mewx.wenku8.search-books
org.mewx.wenku8.start-listening
org.mewx.wenku8.pause-listening
```

四个用户快捷指令为继续阅读、搜索书籍、开始听书、暂停听书。暂停指令需要 `openAppWhenRun = true`，才能把暂停交付给 Flutter 控制器。

### 12.3 平台差异不要误判

- Android 的 APK 自动更新流程不适用于 iOS；iOS 的 `updates` 为 null。
- Android 旧版记录导入、音量键等不应默认写成 iOS 已支持。
- iOS 不提供原插件所用的按 App 强制 120Hz/锁帧 API；mini 6 是 60Hz。
- FrameTiming 的 build/raster 时间不能直接换算真实屏幕 FPS。

## 13. 性能与 iPad 适配原则

### 13.1 自适应

`test/adaptive_ui_test.dart` 包含 mini 6 的真实逻辑尺寸：

- 744×1133 竖屏。
- 1133×744 横屏。
- 两种方向各自的 2 倍字体。

检查首页、书架、发现、搜索、详情、阅读器、听书面板和设置二级页，覆盖横竖屏、深浅色和大字体。没有实测布局问题不要预先大改。

### 13.2 mini 6 的实际性能结论

原始 mini 6 详情返回存在超时帧。逐项 A/B 后：

- 只降低材质、只取消封面飞行、只取消详情内容入场均不足以解决。
- 最终通过现有 `LibraryState.setPerformance(enabled: true)` 在 mini 6 保存全轻量偏好。
- 详情返回 p95 从约 32.13–37.18ms 降至 11.35–12.00ms。
- 设置+详情超时帧从 19/170 降至 3/41。

这不是强制所有设备关闭动画，也不是宣称真实屏幕稳定 60 FPS。之后不要为了“统一外观”清掉用户的轻量设置。

## 14. 关于页与项目文档

`lib/updates/update_page.dart` 只保留本项目内容：

- 当前产品说明与版本。
- 重要使用说明。
- 本项目贡献者署名和第三方许可入口。

不要把原“本版更新”卡片、原交流群、原作者/原项目下载入口重新加入关于页。`CurrentReleaseCard` 可服务其他更新流程，但不属于关于页。

本 README 是恢复手册，不是 Android 宣传页。修改功能、命令或边界时，必须同步更新本文，不要让它继续描述已经过时的平台和行为。

## 15. 测试体系与标准命令

### 15.1 Dart 静态检查与完整测试

```bash
cd "/Users/<you>/DSH仓库镜像/study-thinking-2026/程序类/Wenku8_Flutter-iOS迁移-20261025/app"
export FLUTTER_ROOT="/Users/<you>/DSH仓库镜像/study-thinking-2026/程序类/Wenku8_Flutter-iOS迁移-20261025/.toolchain/flutter"
export PATH="$FLUTTER_ROOT/bin:/opt/homebrew/bin:$PATH"
flutter analyze
flutter test
```

当前关于页交付基线（0.7.0+195，2026-11-18）：

```text
flutter analyze：No issues found!
完整 Dart：1153 通过，13 平台跳过，0 失败
关于/更新定向：69 通过
原生 XCTest：12 项通过（Apple 5、同步 2、PDF 5）
```

平台跳过不是通过；后续数字以新日志为准。0.7.0 删除了依赖在线实现的测试（网络探测、传输层、在线仓库、中继、云书架同步、源码预览边界），因此通过数低于 0.6.1，这是预期变化。

### 15.2 重点测试文件

| 范围 | 文件 |
|---|---|
| iPad 自适应 | `test/adaptive_ui_test.dart` |
| LAN 双端与传书 | `test/lan_reading_sync_test.dart` |
| 备份恢复 | `test/offline_backup_test.dart` 及相关备份测试 |
| 格式导入 | `test/local_document_converter_test.dart`、`test/mobi_import_test.dart` |
| 关于页 | `test/release_highlights_test.dart`、`test/app_updates_test.dart` |
| 阅读器 | `test/reader_*_test.dart` |
| 性能 | `integration_test/tablet_performance_test.dart`、`route_transition_device_test.dart` |
| 在线入口不可用 | `test/offline_features_ui_test.dart`（占位提示断言） |

修改测试期望只能因为需求确实改变。不得为了消除红项删除反向断言或放宽功能条件。

### 15.3 模拟器原生 XCTest

先通过 `xcrun simctl list devices available` 选择模拟器 UDID，再串行运行：

```bash
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -parallel-testing-enabled NO \
  '-only-testing:RunnerTests/PdfImportTests' \
  '-only-testing:RunnerTests/AppleCapabilitiesTests' \
  '-only-testing:RunnerTests/BookSyncDocumentsTests' \
  -resultBundlePath artifacts/native.xcresult \
  FLUTTER_TARGET=lib/main.dart ONLY_ACTIVE_ARCH=YES
```

不要与其他 Flutter 集成构建并发，避免 listener/Generated 配置竞争。

### 15.4 真机 XCTest

统一使用 `RunnerDeviceUITests`、Release、禁并行：

```bash
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme RunnerDeviceUITests \
  -configuration Release \
  -destination 'platform=iOS,id=<DEVICE_UDID>' \
  -parallel-testing-enabled NO \
  '-only-testing:RunnerUITests/DeviceWorkflowTests/testAboutShowsProductDescription' \
  -resultBundlePath artifacts/about-device.xcresult \
  -allowProvisioningUpdates \
  FLUTTER_TARGET=lib/main.dart ONLY_ACTIVE_ARCH=YES
```

其他现有真机用例位于 `ios/RunnerUITests/`，覆盖阅读器、设置、听书、离线和快捷指令。账号与云书架用例属 0.4.8+192 在线版历史，0.7.0 下这些入口只应断言“在线功能不可用”。

XCTest 若遇到锁屏、`testmanagerd` 或 `Timed out while enabling automation mode`，不得写成产品功能失败。先解决设备状态；必要时使用已经验证的 Flutter 集成 target 通道。

### 15.5 Flutter 真机集成 target

本地功能示例（文档导入）：

```bash
flutter build ios --release --target=integration_test/document_import_test.dart
xcrun devicectl device install app \
  --device <DEVICE_UDID> build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --terminate-existing \
  --device <DEVICE_UDID> com.zhujinyu.wenku8flutter
```

测试完成后按目标脚本写出的证据文件名读取（例如备份/导入的 JSON），流程与下面相同：

```bash
xcrun devicectl device copy from \
  --device <DEVICE_UDID> \
  --domain-type appDataContainer \
  --domain-identifier com.zhujinyu.wenku8flutter \
  --source Library/Caches/<evidence>.json \
  --destination artifacts/<evidence>.json
```

有效结果必须包含 `completed=true`。0.7.0 不含在线实现，`integration_test/cloud_shelf_device_test.dart` 仅作为在线版历史脚本保留，不再作为验收依据；需要验收云书架时只能断言入口显示“在线功能不可用”。完成后必须重新构建并安装正式 `lib/main.dart`，不能把集成 target 留在设备上。

## 16. 签名 Release、安装与真机验收

### 16.1 干净构建

```bash
flutter clean
flutter pub get
flutter build ios --release --target=lib/main.dart
codesign --verify --deep --strict build/ios/iphoneos/Runner.app
plutil -extract CFBundleShortVersionString raw build/ios/iphoneos/Runner.app/Info.plist
plutil -extract CFBundleVersion raw build/ios/iphoneos/Runner.app/Info.plist
xcrun dwarfdump --uuid build/ios/iphoneos/Runner.app/Runner
xcrun dwarfdump --uuid build/ios/Release-iphoneos/Runner.app.dSYM
```

App 与 dSYM 的 UUID 必须一致。`flutter clean` 只清生成物，不等于 `git clean`。

### 16.2 真机安装

```bash
xcrun devicectl list devices
xcrun devicectl device info lockState --device <DEVICE_UDID>
xcrun devicectl device install app \
  --device <DEVICE_UDID> build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --terminate-existing \
  --device <DEVICE_UDID> com.zhujinyu.wenku8flutter
```

如果返回 `Locked` / `FBSOpenApplicationErrorDomain error 7`，解锁设备后重试。不要通过卸载 App 绕过锁屏或签名问题。

### 16.3 最小真机验收清单

iPhone/iPad 修改后按影响范围选择，不要把旧证据直接复制为新结果：

- 原生全屏显示，非 iPhone 兼容缩放页面。
- 横竖屏旋转、深浅色、大字体和返回状态。
- 搜索《荷莉的手记》，进入详情和正文。
- 目录切章、三种阅读模式。
- 听书开始/暂停，必要时停止测试播放。
- 主要设置与重启后持久化。
- 云书架同步后检查云端与本机 ID 集合，不只看书架截图。
- 关于页包含本项目说明和许可入口，不包含原作者宣传/原项目入口。
- 书籍、账号、Cookie、缓存和设置未因安装被清除。

截图：

```bash
xcrun devicectl device capture screenshot \
  --device <DEVICE_UDID> --destination artifacts/device-page.png
```

必须实际看图。锁屏壁纸、过渡帧和其他 App 截图都不是功能证据。

## 17. 独立归档与回滚

每次成功交付建立新目录，不覆盖旧归档：

```text
/Users/<you>/.ios-workflow/archive/com.zhujinyu.wenku8flutter/<时间>-b<build>/
```

至少包含：

```text
Runner.app
Runner.dSYM
source/
evidence/
manifest.json
app.sha256
dsym.sha256
后续Agent接手说明.md
```

源码快照排除 `.git`、`.dart_tool`、构建输出、Pods、测试 artifacts 和秘密文件。证据保留修复前失败、修复后通过、真机结果及限制；失败日志不要删除来制造“全绿”。

校验：

```bash
ARCH=/Users/<you>/.ios-workflow/archive/com.zhujinyu.wenku8flutter/<时间>-b<build>
shasum -a 256 -c "$ARCH/app.sha256"
shasum -a 256 -c "$ARCH/dsym.sha256"
codesign --verify --deep --strict "$ARCH/Runner.app"
xcrun dwarfdump --uuid "$ARCH/Runner.app/Runner"
xcrun dwarfdump --uuid "$ARCH/Runner.dSYM"
```

回滚是用旧归档的 `Runner.app` 原地安装，不存在 iOS 系统级一键回滚：

```bash
xcrun devicectl device install app \
  --device <DEVICE_UDID> "$ARCH/Runner.app"
```

不要通过删除新数据来配合旧版本；先确认数据格式兼容。

## 18. 当前已验证结果与未覆盖边界

### 18.1 真实结果

- 0.7.0（2026-11-18）：`flutter analyze` 无问题；完整 Dart 1153 通过、13 平台跳过、0 失败；关于/更新定向 69 通过；界面在线入口显示“在线功能不可用”已有测试覆盖。
- iPhone 已验证账号、搜索、正文、听书、离线缓存、备份、主要设置和格式导入（账号与在线搜索为 0.4.8+192 在线版历史证据，0.7.0 已移除在线实现）。
- mini 6 已验证原生 iPad 全屏、横竖屏、详情、目录、三种阅读模式、听书开始/暂停和设置。
- mini 6 云书架：云端 7 本全部进入本机，主书架可见（0.4.8+192 在线版历史证据；0.7.0 云书架入口显示不可用）。
- mini 6 关于页：原作者宣传和原项目入口不存在，许可入口存在。
- 用户已确认 LAN 开关、Spotlight、锁屏听书和真实飞行模式跨章阅读可用。
- 四个快捷指令已在 iPhone 实测。
- mini 6 轻量偏好有 FrameTiming 改善证据。

### 18.2 仍不能写成通过的事项

- 两台真实设备之间的完整 LAN 配对、传书和冲突恢复。
- 耳机插拔、来电、Siri、其他 App 抢占后的听书暂停和恢复。
- 真实屏幕 FPS 或完整 GPU 捕获。
- 某些 XCUITest 搜索结果合成点击和系统自动化引导问题。
- 在线实现不在本仓库，因此没有任何在线请求、会话续期或云书架同步的验证。
- 验收矩阵中的每一行均完成真机验收。

这些限制不是失败，也不是可以通过措辞省略的完成项。

## 19. 常见问题与处理顺序

### 19.1 在线入口显示“在线功能不可用”

这是预期行为：0.7.0 按上游作者要求移除了在线实现，账号、云书架、在线搜索、书评和在线封面只有占位实现，点击后统一提示不可用。不要为了"修好"入口去补回请求实现、端点或密钥；确需在线能力时先取得作者授权。

### 19.2 搜索末页反复加载（历史问题）

在线搜索不可用，本仓库不含在线分页逻辑；此条只作为将来重新实现时的提醒：`NovelFeedController` 只有在服务端有后续页、当前页非空且合并后确有新增书籍时才保留 `hasMore`。空页或完全重复页应结束，不要靠隐藏骨架屏掩盖。

### 19.3 iPad 卡顿

先采集同负载 FrameTiming，区分转场、材质、排版和真实屏幕刷新。mini 6 使用 60Hz，不要强制 120Hz。已验证的全轻量偏好不要无故撤销。

### 19.4 快捷搜索进入书架结果

`HomeShellState.searchBooks` 必须先 `_selectTab(0)`。0.7.0 起在线搜索不可用，搜索入口只提示“在线功能不可用”；不要在书架结果页断言在线搜索结果。

### 19.5 快捷暂停没有暂停

检查 `WenkuPauseListeningIntent.openAppWhenRun` 和 SceneDelegate 交付。暂停断言必须在听书控制面板进行。

### 19.6 语音路径被拒绝

iOS 临时目录是 `Library/Caches`，原生语音插件不能只允许 `tmp`。同时检查 Apple 语速是否在 0.5～2.0。

### 19.7 签名与设备问题

- 开发者模式未开：先在系统设置开启并按要求重启。
- 锁屏：解锁后安装/启动。
- 签名：使用同一 Team 和 Bundle，允许自动 provisioning，不手改凭据。
- 测试 runner 也需要签名，但它不是最终 App。

## 20. 给下一个 Agent 的执行顺序

1. 阅读本 README，确认是在恢复还是修改既有项目。
2. 核对当前源码、固定工具链、设备、归档和未提交改动。
3. 若只需恢复，直接使用最新归档 `source/` 或 `Runner.app`，不要重新迁移。
4. 若必须重迁移，从第 4 节映射开始，先模型与本地数据，再阅读器，再原生插件，最后 UI；在线实现不在本仓库，不要按旧文档补回端点或密钥。
5. 每实现一个切片，先写能证明错误和正确的成对测试，再做最小实现。
6. 先跑定向测试，再 `flutter analyze`、完整 `flutter test`、必要 XCTest。
7. 模拟器布局验证后再做真机；真机最后集中进行。
8. 修改后构建干净签名 Release，原地安装并做真实功能验收。
9. 恢复正式 `lib/main.dart`，确认设备上没有测试 target。
10. 新建独立归档，包含 App、dSYM、源码、证据、manifest 和 SHA-256。
11. 同步更新本 README 和进度记录，明确真机结果与环境限制。

**完成标准不是“构建成功”，而是当前交付物通过相应测试、真实场景可用、用户数据保留、正式版已恢复且存在可验证的独立归档。**

## 21. 本 README 的专项交付记录

- 本次只重写文档，没有修改生产代码、依赖或设备上的正式 App，因此没有重复安装或把文档变更冒充功能变更。
- `92-readme-validation.log` 核对章节、代码块、38 个路径引用、Android 源码、Flutter SDK、归档、依赖版本和原宣传内容排除。
- `93-readme-release-policy.log` 通过，`94-readme-analyze.log` 无问题，`95-readme-diff-check.log` 通过。
- 后续复核将 `shared_preferences_platform_interface` 修正为锁文件实际的 2.4.2，并补充 `liquid_glass_easy` 5.0.0；`92-readme-analyze.log` 无问题，`94-readme-contract.log` 核对 25 个直接依赖与 16 个必需章节通过。0.7.0 移除在线实现后，`flutter analyze` 无问题、完整 Dart **1153 通过、13 平台跳过、0 失败**（2026-11-18）；0.6.1 及更早的数字（如 1160、1169）属于含在线实现的历史记录。
- 本 README 的首个专项归档包含对应源码、App、dSYM、验证日志、manifest 和 SHA-256；上述后续复核修正以当前工作区及进度文件最新记录为准：

```text
/Users/<you>/.ios-workflow/archive/com.zhujinyu.wenku8flutter/20261029-092524-b192/
```
