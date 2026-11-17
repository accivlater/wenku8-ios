import 'release_notices.dart';

class ReleaseSection {
  const ReleaseSection(this.title, this.items);
  final String title;
  final List<String> items;
}

const inAppCommunityNotice = r'''**交流群：1131397088**\
遇到问题或有功能建议，欢迎进群反馈。''';
const releaseFreeNotice = "**本项目完全免费、开源，无任何赞助、打赏或付费渠道。**";
const releaseReadingNotice =
    "**本项目仅为第三方阅读客户端，提供阅读界面与本地书籍管理，不运营在线书库、不自行发布小说资源。在线内容及可读状态一切以 Wenku8 为准；不提供因版权限制而停止开放的在线书籍阅读。**";

const _freeHeading = '### ⚠️ 免费开源，请勿付费';
const _freeFraudNotice =
    '不出售会员、激活码或功能解锁服务。任何以本项目或开发者名义收费、募捐、索要赞助的行为均与本项目无关，请勿付款。';
const _downloadNotice = '请通过**项目仓库或 App 内更新**获取安装包。';
const _freeNoticeBody =
    '$_freeHeading\n\n$releaseFreeNotice\n\n$_freeFraudNotice\n\n$_downloadNotice';
const _iosRelease =
    '仓库整理为独立的 iOS / iPadOS 项目，版本号进入 0.7.0（构建号 195），不再提供 Android 构建与 APK。';
const _onlineDrop = '移除在线实现（文库账号、云书架、搜索、发现、书评、封面），与上游源码预览边界一致。';
const _uiNotice = '界面保留在线入口并显示在线功能不可用；阅读器、本地书库、导入、备份与离线缓存继续可用。';
const _teamDrop = '移除工程内写死的上游 Team，签名由使用者在 Xcode 中选择。';

const _releaseChanges =
    '### iOS / iPadOS 发行\n\n- $_iosRelease\n- $_onlineDrop\n- $_uiNotice\n- $_teamDrop';

// Keep the in-app opening intact. Public announcements omit contact information.
const publicReleaseNotes =
    '$_freeNoticeBody\n\n$releaseReadingNotice\n\n**$currentReleaseSourcePolicy**\n\n$_releaseChanges';
const currentReleaseNotes = '$inAppCommunityNotice\n\n$publicReleaseNotes';

const currentReleaseSummary = [
  inAppCommunityNotice,
  releaseFreeNotice,
  releaseReadingNotice,
  currentReleaseSourcePolicy,
  '仓库整理为独立 iOS / iPadOS 项目，版本进入 0.7.0。',
  '移除在线实现，与上游源码预览边界一致。',
  '界面保留在线入口并显示在线功能不可用。',
  '移除写死的上游 Team，签名由使用者完成。',
];

const currentReleaseSections = [
  ReleaseSection("重要说明 · 请务必阅读", [
    inAppCommunityNotice,
    _freeHeading,
    releaseFreeNotice,
    _freeFraudNotice,
    _downloadNotice,
    releaseReadingNotice,
    currentReleaseSourcePolicy,
  ]),
  ReleaseSection("iOS / iPadOS 发行", [
    _iosRelease,
    _onlineDrop,
    _uiNotice,
    _teamDrop,
  ]),
];
