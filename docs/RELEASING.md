# 构建与分发

本仓库只维护 iOS / iPadOS，不提供 Android 构建，也不发布 APK。当前发布版本为 `0.7.0+195`。

本仓库与上游源码预览边界一致：在线实现（文库账号、云书架、搜索、书评、在线封面）不随源码发布，构建时**不需要也不应注入任何端点或密钥**；界面对应入口显示“在线功能不可用”。发布前请确认仓库内没有在线实现、relay 配置或签名密钥。

## 环境

macOS、Xcode 27.1、Flutter 3.41.5（Dart 3.11.3）、CocoaPods，iOS 部署目标 15.0。

## 构建

```sh
flutter pub get
cd ios && pod install && cd ..
flutter build ios --release --no-codesign
```

## 生成未签名 IPA

```sh
cd build/ios/iphoneos
mkdir Payload
cp -R Runner.app Payload/
zip -r Wenku8-unsigned.ipa Payload
```

## 签名与安装

仓库不绑定任何开发者 Team。用 Xcode 打开 `ios/Runner.xcworkspace`，在 Runner target 的 Signing & Capabilities 中选择自己的 Team；也可以直接用免费 Apple ID 自签。项目没有 App Group、推送、iCloud 等需要付费开发者账号的能力。

## 分发方式

- 只通过源码仓库分发，不通过 App Store（GPL 与 FairPlay DRM、iOS 安装限制冲突）；
- 如需发布未签名 IPA，同时提供本仓库完整对应源码；
- 不提供预编译安装包，也不提供 Android 版本。

## 许可

整树按 GPL-3.0-or-later 分发，保留 `LICENSE`、`NOTICE`、`docs/THIRD_PARTY.md`、`assets/licenses/GPL-3.0.txt`。修改后的版本继续按 GPL 分发，不附加额外限制。
