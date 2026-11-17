import 'dart:convert';
import 'dart:typed_data';

import 'local_markup_decode.dart';

const _windows1252 = <int>[
  0x20ac,
  0x0081,
  0x201a,
  0x0192,
  0x201e,
  0x2026,
  0x2020,
  0x2021,
  0x02c6,
  0x2030,
  0x0160,
  0x2039,
  0x0152,
  0x008d,
  0x017d,
  0x008f,
  0x0090,
  0x2018,
  0x2019,
  0x201c,
  0x201d,
  0x2022,
  0x2013,
  0x2014,
  0x02dc,
  0x2122,
  0x0161,
  0x203a,
  0x0153,
  0x009d,
  0x017e,
  0x0178,
];

String decodeWindows1252(List<int> bytes) => String.fromCharCodes(
  bytes.map(
    (byte) => byte >= 0x80 && byte <= 0x9f ? _windows1252[byte - 0x80] : byte,
  ),
);

String decodeLocalDocumentText(List<int> bytes, {String encoding = 'auto'}) {
  final normalized = encoding.toLowerCase().trim();
  if (const {
    '1252',
    'cp1252',
    'windows-1252',
    'windows1252',
  }.contains(normalized)) {
    return decodeWindows1252(bytes);
  }
  if (const {'latin1', 'iso-8859-1', '8859-1'}.contains(normalized)) {
    return latin1.decode(bytes);
  }
  if (const {'utf8', 'utf-8'}.contains(normalized)) {
    return utf8.decode(bytes).replaceFirst('\uFEFF', '');
  }
  if (normalized != 'auto' && normalized.isNotEmpty) {
    throw FormatException('暂不支持文档编码 $encoding，请转换为 UTF-8 后导入');
  }
  try {
    return decodeLocalMarkup(bytes).replaceFirst('\uFEFF', '');
  } on FormatException {
    final prefix = latin1.decode(
      Uint8List.fromList(bytes.take(4096).toList()),
      allowInvalid: true,
    );
    final declaration = RegExp(
      '(?:charset|encoding)\\s*=\\s*["\']?\\s*([a-zA-Z0-9._-]+)',
      caseSensitive: false,
    ).firstMatch(prefix)?.group(1)?.toLowerCase();
    if (const {'windows-1252', 'cp1252', '1252'}.contains(declaration)) {
      return decodeWindows1252(bytes);
    }
    if (const {'iso-8859-1', 'latin1'}.contains(declaration)) {
      return latin1.decode(bytes);
    }
    if (declaration != null &&
        declaration != 'utf-8' &&
        declaration != 'utf8') {
      throw FormatException('暂不支持文档编码 $declaration，请转换为 UTF-8 后导入');
    }
    throw const FormatException('文档不是有效的 UTF-8 / UTF-16 文本，请转换编码后导入');
  }
}
