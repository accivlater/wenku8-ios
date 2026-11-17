import 'dart:convert';
import 'dart:typed_data';

import 'local_document_encoding.dart';
import 'local_epub_builder.dart';

class _RtfState {
  _RtfState({
    this.ignored = false,
    this.unicodeFallback = 1,
    this.pictureType,
    this.pictureHex,
  });
  bool ignored;
  int unicodeFallback;
  String? pictureType;
  StringBuffer? pictureHex;
  _RtfState copy() => _RtfState(
    ignored: ignored,
    unicodeFallback: unicodeFallback,
    pictureType: pictureType,
    pictureHex: pictureHex,
  );
}

void convertLocalRtf(Uint8List bytes, LocalEpubBuilder builder) {
  if (bytes.length < 5 ||
      ascii.decode(bytes.take(5).toList(), allowInvalid: true) != '{\\rtf') {
    throw const FormatException('RTF 文件头无效');
  }
  final prefix = latin1.decode(
    bytes.take(bytes.length < 2048 ? bytes.length : 2048).toList(),
  );
  final codePage =
      int.tryParse(
        RegExp(r'\\ansicpg(\d+)').firstMatch(prefix)?.group(1) ?? '',
      ) ??
      1252;
  var at = 0, fallback = 0;
  final stack = <_RtfState>[];
  var state = _RtfState();
  final text = StringBuffer(), ansi = <int>[];

  String decodeAnsi() => switch (codePage) {
    65001 => utf8.decode(ansi),
    1252 => decodeWindows1252(ansi),
    28591 => latin1.decode(ansi),
    _ => throw FormatException(
      'RTF 的 ANSI 代码页 $codePage 暂不支持，请另存为 DOCX 或使用 Unicode RTF',
    ),
  };
  void flushAnsi() {
    if (ansi.isEmpty) return;
    if (!state.ignored && state.pictureHex == null) text.write(decodeAnsi());
    ansi.clear();
  }

  void flushParagraph() {
    flushAnsi();
    final value = text.toString().trim();
    text.clear();
    if (value.isEmpty) return;
    if (value.length <= 120 &&
        RegExp(
          r'^(?:第[0-9零〇一二三四五六七八九十百千万两]+[章节卷回部](?:\s+.{0,80})?|chapter\s+[0-9ivxlcdm]+(?:\s+.{0,80})?)$',
          caseSensitive: false,
        ).hasMatch(value)) {
      builder.heading(value);
    } else {
      builder.text(value);
    }
  }

  void emitCharacter(String character) {
    flushAnsi();
    if (fallback > 0) {
      fallback--;
    } else if (!state.ignored && state.pictureHex == null) {
      text.write(character);
      if (text.length >= 4000) flushParagraph();
    }
  }

  void emitByte(int byte) {
    if (fallback > 0) {
      fallback--;
    } else if (!state.ignored && state.pictureHex == null) {
      ansi.add(byte);
      if (ansi.length > 4 * 1024 * 1024) {
        throw const FormatException('RTF ANSI 字符序列过长');
      }
    }
  }

  void emitPicture() {
    final encoded = state.pictureHex.toString();
    if (encoded.length > 16 * 1024 * 1024 || encoded.length.isOdd) {
      throw const FormatException('RTF 插图数据不完整或超过大小限制');
    }
    final compact = encoded.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) return;
    if (compact.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(compact)) {
      throw const FormatException('RTF 插图十六进制数据无效');
    }
    final picture = Uint8List(compact.length ~/ 2);
    for (var i = 0; i < picture.length; i++) {
      picture[i] = int.parse(compact.substring(i * 2, i * 2 + 2), radix: 16);
    }
    final key = builder.inlineResourceKey();
    if (builder.resource(key, state.pictureType ?? '', picture)) {
      builder.image(key);
    }
  }

  bool letter(int value) =>
      value >= 0x41 && value <= 0x5a || value >= 0x61 && value <= 0x7a;
  bool digit(int value) => value >= 0x30 && value <= 0x39;
  int hex(int value) {
    final character = String.fromCharCode(value);
    final parsed = int.tryParse(character, radix: 16);
    if (parsed == null) throw const FormatException('RTF 字符转义无效');
    return parsed;
  }

  while (at < bytes.length) {
    final value = bytes[at++], character = String.fromCharCode(value);
    if (character == '{') {
      flushAnsi();
      if (stack.length >= 512) throw const FormatException('RTF 分组层级过深');
      stack.add(state);
      state = state.pictureHex == null
          ? state.copy()
          : _RtfState(ignored: true, unicodeFallback: state.unicodeFallback);
      continue;
    }
    if (character == '}') {
      flushAnsi();
      if (stack.isEmpty) throw const FormatException('RTF 分组损坏');
      if (state.pictureHex != null && !state.ignored) emitPicture();
      state = stack.removeLast();
      continue;
    }
    if (character == '\\') {
      if (at >= bytes.length) throw const FormatException('RTF 转义不完整');
      final symbol = bytes[at++];
      if (symbol == 0x27) {
        if (at + 2 > bytes.length) throw const FormatException('RTF 字符转义不完整');
        emitByte(hex(bytes[at]) << 4 | hex(bytes[at + 1]));
        at += 2;
        continue;
      }
      flushAnsi();
      if (!letter(symbol)) {
        switch (String.fromCharCode(symbol)) {
          case '*':
            state.ignored = true;
          case '\\' || '{' || '}':
            emitCharacter(String.fromCharCode(symbol));
          case '~':
            emitCharacter(' ');
          case '_':
            emitCharacter('-');
          case '\r' || '\n':
            break;
          default:
            if (state.pictureHex == null && !state.ignored) {
              throw const FormatException('RTF 控制符号不完整');
            }
        }
        continue;
      }
      final word = StringBuffer(String.fromCharCode(symbol));
      while (at < bytes.length && letter(bytes[at])) {
        if (word.length >= 64) throw const FormatException('RTF 控制词无效');
        word.write(String.fromCharCode(bytes[at++]));
      }
      final number = StringBuffer();
      if (at < bytes.length && (bytes[at] == 0x2d || digit(bytes[at]))) {
        number.write(String.fromCharCode(bytes[at++]));
        while (at < bytes.length && digit(bytes[at])) {
          if (number.length >= 12) throw const FormatException('RTF 参数无效');
          number.write(String.fromCharCode(bytes[at++]));
        }
      }
      if (at < bytes.length && bytes[at] == 0x20) at++;
      final parameter = int.tryParse(number.toString()) ?? 0;
      switch (word.toString()) {
        case 'fonttbl' ||
            'colortbl' ||
            'stylesheet' ||
            'info' ||
            'object' ||
            'objdata' ||
            'header' ||
            'footer' ||
            'fldinst' ||
            'xmlnstbl' ||
            'themedata' ||
            'datastore':
          state.ignored = true;
        case 'pict':
          if (!state.ignored) {
            flushParagraph();
            state
              ..pictureType = null
              ..pictureHex = StringBuffer();
          }
        case 'pngblip':
          if (state.pictureHex != null) state.pictureType = 'image/png';
        case 'jpegblip':
          if (state.pictureHex != null) state.pictureType = 'image/jpeg';
        case 'gifblip':
          if (state.pictureHex != null) state.pictureType = 'image/gif';
        case 'uc':
          state.unicodeFallback = parameter.clamp(0, 16);
        case 'u':
          flushAnsi();
          if (!state.ignored && state.pictureHex == null) {
            final unit = parameter > 32767 ? parameter - 65536 : parameter;
            if (unit < -32768 || unit > 65535) {
              throw const FormatException('RTF Unicode 参数无效');
            }
            text.write(String.fromCharCode(unit & 0xffff));
          }
          fallback = state.unicodeFallback;
        case 'par' || 'line' || 'page':
          if (!state.ignored && state.pictureHex == null) flushParagraph();
        case 'tab':
          emitCharacter(' ');
        case 'emdash':
          emitCharacter('—');
        case 'endash':
          emitCharacter('–');
        case 'lquote' || 'rquote':
          emitCharacter("'");
        case 'ldblquote' || 'rdblquote':
          emitCharacter('"');
        case 'bin':
          if (parameter < 0 || at + parameter > bytes.length) {
            throw const FormatException('RTF 二进制内容不完整');
          }
          at += parameter;
      }
      continue;
    }
    if (character == '\r' || character == '\n') continue;
    if (state.pictureHex != null && !state.ignored) {
      if (RegExp(r'[0-9a-fA-F\s]').hasMatch(character)) {
        state.pictureHex!.write(character);
      }
    } else if (value >= 128) {
      emitByte(value);
    } else {
      emitCharacter(character);
    }
  }
  if (stack.isNotEmpty) throw const FormatException('RTF 文件不完整');
  if (state.pictureHex != null) throw const FormatException('RTF 插图分组不完整');
  flushParagraph();
}
