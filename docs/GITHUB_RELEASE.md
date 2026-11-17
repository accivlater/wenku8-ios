# GitHub 发布文案

推送到 GitHub 时，按下面填写仓库设置与 Release 描述，保持与 README、NOTICE 口径一致。

## 仓库描述（Description）

推荐：

> 非官方轻小说文库 iOS/iPadOS 客户端，基于 Wenku8_Flutter v0.4.8 修改；支持 TXT/EPUB/MOBI 等 13 种格式，Flutter + Swift，GPL-3.0 开源。

备选（更短）：

> 非官方 Wenku8 轻小说阅读器 iOS/iPadOS 版，Flutter + Swift，GPL-3.0。

## Topics

```
flutter
ios
ipados
wenku8
light-novel
novel-reader
ebook-reader
chinese
dart
gpl-3-0
```

## Release 文案（v0.7.0）

标题：`v0.7.0 · 移除在线实现，与上游源码预览边界一致`

正文：

```markdown
本版本按上游作者要求移除在线实现，与上游公开版的源码预览边界保持一致。

首个独立版本：从 Wenku8_Flutter v0.4.8 分叉，仅面向 iPhone / iPad。

- 移除在线实现（文库账号、云书架、搜索、发现、书评、在线封面），本仓库不再包含在线请求、端点或签名密钥
- 界面保留在线入口并显示“在线功能不可用”；本地书库、阅读器、导入、备份与离线缓存继续可用
- 完整 iOS / iPadOS 适配：原生全屏、横竖屏、iPad 分栏与对页、系统语音听书、Spotlight、快捷指令、局域网续读
- 本地文档导入：TXT、EPUB、MOBI、AZW、AZW3、PRC、DOC、DOCX、FB2、HTML、Markdown、RTF、PDF
- 备份恢复、离线缓存
- 12 个 iOS 原生插件
- 非官方项目，与上游作者无隶属关系

本仓库只提供源码，不提供 App Store 版本、Android 构建或预编译安装包。
许可：GPL-3.0-or-later，上游为 GPL-2.0-or-later；来源与改动见 docs/CODE_ORIGIN.md。
```

## 其他设置

- Social preview：上传 1280×640 的仓库预览图（可用书架截图裁切）；
- 不要开启 Actions 自动构建（仓库没有 runner，且不需要 CI 产物）；
- 不发布上游 APK / HAP。
