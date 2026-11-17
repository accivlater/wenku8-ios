import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'local_document_encoding.dart';
import 'local_epub_builder.dart';

class LocalMobiResource {
  const LocalMobiResource(this.bytes, this.type);
  final Uint8List bytes;
  final String type;
}

class LocalMobiDocument {
  const LocalMobiDocument({
    required this.title,
    required this.author,
    required this.markup,
    required this.resources,
    required this.cover,
  });
  final String title, author, markup;
  final Map<int, LocalMobiResource> resources;
  final int? cover;
}

class _PalmRecord {
  const _PalmRecord(this.offset, this.data);
  final int offset;
  final Uint8List data;
}

class _MobiHeader {
  const _MobiHeader({
    required this.length,
    required this.encoding,
    required this.version,
    required this.firstImage,
    required this.huffOffset,
    required this.huffCount,
    required this.extraFlags,
    required this.fragmentIndex,
    required this.skeletonIndex,
    this.fdstRecord = 0xffffffff,
    this.fdstFlowCount = 0,
  });
  final int length, encoding, version, firstImage;
  final int huffOffset, huffCount, extraFlags;
  final int fragmentIndex, skeletonIndex, fdstRecord, fdstFlowCount;
}

Never _mobiError([String message = 'MOBI 文件损坏或格式不受支持']) =>
    throw FormatException(message);

void _range(Uint8List bytes, int offset, int length) {
  if (offset < 0 || length < 0 || offset + length > bytes.length) {
    _mobiError('MOBI 头部或记录不完整');
  }
}

int _u16(Uint8List bytes, int offset) {
  _range(bytes, offset, 2);
  return bytes[offset] << 8 | bytes[offset + 1];
}

int _u32(Uint8List bytes, int offset) {
  _range(bytes, offset, 4);
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

String _ascii(Uint8List bytes, int offset, int length) {
  _range(bytes, offset, length);
  return ascii.decode(Uint8List.sublistView(bytes, offset, offset + length));
}

List<_PalmRecord> _palmRecords(Uint8List bytes) {
  if (bytes.length < 78) _mobiError('PalmDB 文件头不完整');
  final count = _u16(bytes, 76);
  if (count == 0) _mobiError('PalmDB 没有记录');
  final tableEnd = 78 + count * 8;
  if (tableEnd > bytes.length) _mobiError('PalmDB 记录表不完整');
  final offsets = <int>[
    for (var i = 0; i < count; i++) _u32(bytes, 78 + i * 8),
  ];
  for (var i = 0; i < offsets.length; i++) {
    final end = i + 1 < offsets.length ? offsets[i + 1] : bytes.length;
    if (offsets[i] < tableEnd || offsets[i] > end || end > bytes.length) {
      _mobiError('PalmDB 第 $i 条记录边界无效');
    }
  }
  return [
    for (var i = 0; i < count; i++)
      _PalmRecord(
        offsets[i],
        Uint8List.sublistView(
          bytes,
          offsets[i],
          i + 1 < count ? offsets[i + 1] : bytes.length,
        ),
      ),
  ];
}

_MobiHeader _mobiHeader(Uint8List record) {
  if (record.length < 24 || _ascii(record, 16, 4) != 'MOBI') {
    if (record.length >= 16) {
      return const _MobiHeader(
        length: 0,
        encoding: 1252,
        version: 0,
        firstImage: 0xffffffff,
        huffOffset: 0,
        huffCount: 0,
        extraFlags: 0,
        fragmentIndex: 0xffffffff,
        skeletonIndex: 0xffffffff,
      );
    }
    _mobiError('MOBI 头部不完整');
  }
  final length = _u32(record, 20);
  if (length < 24 || 16 + length > record.length) {
    _mobiError('MOBI 头部长度无效');
  }
  int u32(int relative, [int fallback = 0]) =>
      relative + 4 <= length ? _u32(record, 16 + relative) : fallback;
  return _MobiHeader(
    length: length,
    encoding: u32(12, 1252),
    version: u32(20),
    firstImage: u32(92, 0xffffffff),
    huffOffset: u32(96),
    huffCount: u32(100),
    extraFlags: 226 + 2 <= length ? _u16(record, 16 + 226) : 0,
    fragmentIndex: u32(232, 0xffffffff),
    skeletonIndex: u32(236, 0xffffffff),
    fdstRecord: u32(176, 0xffffffff),
    fdstFlowCount: u32(180),
  );
}

int _trailingSize(Uint8List record, int flags) {
  int entrySize(int end) {
    var result = 0, shift = 0, read = 0;
    while (end - read > 0 && read < 4) {
      final value = record[end - ++read];
      result |= (value & 0x7f) << shift;
      shift += 7;
      if (value & 0x80 != 0) return result;
    }
    _mobiError('MOBI 记录尾长度无效');
  }

  var size = 0;
  for (var bit = 1; bit < 16; bit++) {
    if (flags & (1 << bit) != 0) {
      final entry = entrySize(record.length - size);
      if (entry <= 0 || size + entry > record.length) {
        _mobiError('MOBI 记录尾超出记录边界');
      }
      size += entry;
    }
  }
  if (flags & 1 != 0) {
    if (size >= record.length) _mobiError('MOBI 多字节记录尾不完整');
    size += (record[record.length - size - 1] & 3) + 1;
  }
  if (size > record.length) _mobiError('MOBI 记录尾超出记录边界');
  return size;
}

Uint8List _textPayload(_PalmRecord record, int flags) {
  if (flags == 0) return record.data;
  return Uint8List.sublistView(
    record.data,
    0,
    record.data.length - _trailingSize(record.data, flags),
  );
}

Uint8List _decompressPalmDoc(Uint8List input, int maxOutput) {
  final output = <int>[];
  void add(int byte) {
    if (output.length >= maxOutput) _mobiError('MOBI 正文解压后超过大小限制');
    output.add(byte);
  }

  var at = 0;
  while (at < input.length) {
    final value = input[at++];
    if (value >= 1 && value <= 8) {
      if (at + value > input.length || output.length + value > maxOutput) {
        _mobiError('MOBI PalmDOC 字面量不完整或超过大小限制');
      }
      output.addAll(Uint8List.sublistView(input, at, at + value));
      at += value;
    } else if (value <= 0x7f) {
      add(value);
    } else if (value >= 0xc0) {
      add(0x20);
      add(value ^ 0x80);
    } else {
      if (at >= input.length) _mobiError('MOBI PalmDOC 回引不完整');
      final next = input[at++];
      final distance = ((value & 0x3f) << 5) | (next >> 3);
      final length = (next & 7) + 3;
      if (distance <= 0 || distance > output.length) {
        _mobiError('MOBI PalmDOC 回引位置无效');
      }
      for (var i = 0; i < length; i++) {
        add(output[output.length - distance]);
      }
    }
  }
  return Uint8List.fromList(output);
}

class _HuffCache {
  const _HuffCache(this.length, this.terminal, this.maxCode);
  final int length;
  final bool terminal;
  final int maxCode;
}

class _HuffTable {
  const _HuffTable(this.cache, this.minCode, this.maxCode);
  final List<_HuffCache> cache;
  final List<int> minCode, maxCode;

  factory _HuffTable.parse(Uint8List record) {
    if (record.length < 24 || _ascii(record, 0, 4) != 'HUFF') {
      _mobiError('MOBI HUFF 表头无效');
    }
    if (_u32(record, 4) != 24) _mobiError('MOBI HUFF 头部长度不受支持');
    final first = _u32(record, 8), second = _u32(record, 12);
    _range(record, first, 256 * 4);
    _range(record, second, 64 * 4);
    final cache = <_HuffCache>[];
    for (var i = 0; i < 256; i++) {
      final value = _u32(record, first + i * 4);
      final length = value & 0x1f;
      final terminal = value & 0x80 != 0;
      if (length == 0 || length <= 8 && !terminal) {
        _mobiError('MOBI HUFF 缓存项无效');
      }
      final maximum = ((((value >> 8) + 1) << (32 - length)) - 1) & 0xffffffff;
      cache.add(_HuffCache(length, terminal, maximum));
    }
    final minimum = List<int>.filled(33, 0);
    final maximum = List<int>.filled(33, 0)..[0] = 0xffffffff;
    for (var i = 1; i <= 32; i++) {
      final low = _u32(record, second + (i - 1) * 8);
      final high = _u32(record, second + (i - 1) * 8 + 4);
      minimum[i] = (low << (32 - i)) & 0xffffffff;
      maximum[i] = (((high + 1) << (32 - i)) - 1) & 0xffffffff;
    }
    return _HuffTable(cache, minimum, maximum);
  }
}

class _CdicEntry {
  _CdicEntry(this.bytes, this.literal);
  Uint8List bytes;
  bool literal;
}

class _CdicTable {
  const _CdicTable(this.entries);
  final List<_CdicEntry> entries;

  factory _CdicTable.parse(List<Uint8List> records) {
    if (records.isEmpty) _mobiError('MOBI 缺少 CDIC 词典');
    var total = 0, bits = 0;
    final entries = <_CdicEntry>[];
    for (var r = 0; r < records.length; r++) {
      final record = records[r];
      if (record.length < 16 || _ascii(record, 0, 4) != 'CDIC') {
        _mobiError('MOBI CDIC 表头无效');
      }
      if (_u32(record, 4) != 16) _mobiError('MOBI CDIC 头部长度不受支持');
      final phrases = _u32(record, 8), recordBits = _u32(record, 12);
      if (r == 0) {
        total = phrases;
        bits = recordBits;
        if (total <= 0 || total > 1000000 || bits <= 0 || bits > 20) {
          _mobiError('MOBI CDIC 词典大小超过限制');
        }
      } else if (phrases != total || recordBits != bits) {
        _mobiError('MOBI CDIC 记录参数不一致');
      }
      final count = math.min(1 << bits, total - entries.length);
      if (count < 0) _mobiError('MOBI CDIC 词条过多');
      _range(record, 16, count * 2);
      for (var i = 0; i < count; i++) {
        final offset = _u16(record, 16 + i * 2);
        _range(record, 16 + offset, 2);
        final lengthAndFlag = _u16(record, 16 + offset);
        final length = lengthAndFlag & 0x7fff;
        final start = 16 + offset + 2;
        _range(record, start, length);
        entries.add(
          _CdicEntry(
            Uint8List.sublistView(record, start, start + length),
            lengthAndFlag & 0x8000 != 0,
          ),
        );
      }
    }
    if (entries.length != total) _mobiError('MOBI CDIC 词条数量不完整');
    return _CdicTable(entries);
  }
}

class _HuffDecoder {
  _HuffDecoder(this.huff, this.cdic);
  final _HuffTable huff;
  final _CdicTable cdic;
  final _expanding = <int>{};

  Uint8List unpack(Uint8List input, int maxOutput, [int depth = 0]) {
    if (depth > 64) _mobiError('MOBI CDIC 递归层级过深');
    final padded = Uint8List(input.length + 8)
      ..setRange(0, input.length, input);
    final view = ByteData.sublistView(padded);
    var bitsLeft = input.length * 8, position = 0, n = 32;
    var high = view.getUint32(0), low = view.getUint32(4);
    final output = BytesBuilder(copy: false);
    void add(Uint8List bytes) {
      if (output.length + bytes.length > maxOutput) {
        _mobiError('MOBI HUFF/CDIC 正文解压后超过大小限制');
      }
      output.add(bytes);
    }

    while (true) {
      if (n <= 0) {
        position += 4;
        high = low;
        low = view.getUint32(position + 4);
        n += 32;
      }
      final code = n == 32
          ? high
          : ((high << (32 - n)) | (low >>> n)) & 0xffffffff;
      final cached = huff.cache[code >>> 24];
      var length = cached.length, maximum = cached.maxCode;
      if (!cached.terminal) {
        while (length <= 32 && code < huff.minCode[length]) {
          length++;
        }
        if (length > 32) _mobiError('MOBI HUFF 码字超过 32 位');
        maximum = huff.maxCode[length];
      }
      n -= length;
      bitsLeft -= length;
      if (bitsLeft < 0) break;
      final index = (maximum - code) >>> (32 - length);
      if (index < 0 || index >= cdic.entries.length) {
        _mobiError('MOBI HUFF 词典索引越界');
      }
      final entry = cdic.entries[index];
      if (entry.literal) {
        add(entry.bytes);
      } else {
        if (!_expanding.add(index)) _mobiError('MOBI CDIC 词典存在循环引用');
        try {
          final expanded = unpack(entry.bytes, maxOutput, depth + 1);
          entry
            ..bytes = expanded
            ..literal = true;
          add(expanded);
        } finally {
          _expanding.remove(index);
        }
      }
    }
    return output.toBytes();
  }
}

Uint8List _bookText(
  List<_PalmRecord> records,
  _MobiHeader mobi,
  int compression,
  int textLength,
  int textCount,
  int recordSize,
) {
  _HuffTable? huff;
  _CdicTable? cdic;
  if (compression == 17480) {
    if (mobi.huffOffset <= 0 || mobi.huffCount < 2) {
      _mobiError('MOBI 缺少 HUFF/CDIC 压缩表');
    }
    final end = mobi.huffOffset + mobi.huffCount;
    if (mobi.huffOffset <= textCount || end > records.length) {
      _mobiError('MOBI HUFF/CDIC 表记录边界无效');
    }
    huff = _HuffTable.parse(records[mobi.huffOffset].data);
    cdic = _CdicTable.parse([
      for (var i = mobi.huffOffset + 1; i < end; i++) records[i].data,
    ]);
  }
  final decoder = huff == null ? null : _HuffDecoder(huff, cdic!);
  final output = BytesBuilder(copy: false);
  for (var i = 1; i <= textCount; i++) {
    final payload = _textPayload(records[i], mobi.extraFlags);
    final allowance = textLength + recordSize - output.length;
    if (allowance <= 0 && payload.isNotEmpty) {
      _mobiError('MOBI 正文长度与记录表不一致');
    }
    late final Uint8List decoded;
    switch (compression) {
      case 1:
        if (payload.length > allowance) {
          _mobiError('MOBI 未压缩正文超过声明长度');
        }
        decoded = payload;
      case 2:
        decoded = _decompressPalmDoc(
          payload,
          math.min(math.max(recordSize, 4096), allowance),
        );
      case 17480:
        decoded = decoder!.unpack(
          payload,
          math.min(16 * 1024 * 1024, allowance),
        );
      default:
        _mobiError('MOBI 使用不支持的压缩方式 $compression');
    }
    output.add(decoded);
  }
  final bytes = output.toBytes();
  if (bytes.length < textLength || bytes.length > textLength + recordSize) {
    _mobiError('MOBI 解压后的正文长度不完整');
  }
  return Uint8List.sublistView(bytes, 0, textLength);
}

class _IndxEntry {
  const _IndxEntry(this.label, this.tags);
  final String label;
  final Map<int, List<int>> tags;
  int tag(int id, [int index = 0]) {
    final values = tags[id];
    if (values == null || index >= values.length) {
      _mobiError('AZW3 INDX 缺少标签 $id / $index');
    }
    return values[index];
  }
}

class _TagxField {
  const _TagxField(this.tag, this.values, this.mask, this.control);
  final int tag, values, mask, control;
}

int _vwi(Uint8List bytes, int start, int end, int Function(int) advance) {
  var value = 0, at = start;
  for (var i = 0; i < 4; i++) {
    if (at >= end) _mobiError('AZW3 INDX 变长整数不完整');
    final byte = bytes[at++];
    value = (value << 7) | (byte & 0x7f);
    advance(at);
    if (byte & 0x80 != 0) return value;
  }
  _mobiError('AZW3 INDX 变长整数超过 4 字节');
}

List<_IndxEntry> _parseIndx(List<_PalmRecord> records, int start) {
  if (start <= 0 || start + 1 >= records.length) {
    _mobiError('AZW3 INDX 起始记录越界');
  }
  final meta = records[start].data;
  if (meta.length < 56 || _ascii(meta, 0, 4) != 'INDX') {
    _mobiError('AZW3 INDX 元记录头无效');
  }
  final headerLength = _u32(meta, 4);
  final recordCount = _u32(meta, 24);
  final totalCount = _u32(meta, 36);
  if (headerLength < 56 ||
      headerLength > meta.length ||
      recordCount == 0 ||
      recordCount > 4096 ||
      totalCount == 0 ||
      totalCount > 1000000 ||
      start + recordCount >= records.length ||
      _ascii(meta, headerLength, 4) != 'TAGX') {
    _mobiError('AZW3 INDX 元记录数量或 TAGX 位置无效');
  }
  final tagxLength = _u32(meta, headerLength + 4);
  final controlCount = _u32(meta, headerLength + 8);
  if (tagxLength < 12 ||
      (tagxLength - 12) % 4 != 0 ||
      headerLength + tagxLength > meta.length ||
      controlCount > 32) {
    _mobiError('AZW3 TAGX 长度或控制字节数无效');
  }
  final fields = <_TagxField>[];
  var controls = 0;
  for (var at = headerLength + 12; at < headerLength + tagxLength; at += 4) {
    final control = meta[at + 3];
    if (control > 1) _mobiError('AZW3 TAGX 控制标记无效');
    if (control == 1) controls++;
    fields.add(_TagxField(meta[at], meta[at + 1], meta[at + 2], control));
  }
  if (controls != controlCount) _mobiError('AZW3 TAGX 控制字节数不一致');
  final entries = <_IndxEntry>[];
  for (
    var recordIndex = start + 1;
    recordIndex <= start + recordCount;
    recordIndex++
  ) {
    final record = records[recordIndex].data;
    if (record.length < 28 || _ascii(record, 0, 4) != 'INDX') {
      _mobiError('AZW3 INDX 数据记录头无效');
    }
    final idxt = _u32(record, 20), count = _u32(record, 24);
    if (count > totalCount - entries.length ||
        idxt + count * 2 + 4 > record.length ||
        _ascii(record, idxt, 4) != 'IDXT') {
      _mobiError('AZW3 IDXT 数量或位置无效');
    }
    final offsets = <int>[
      for (var i = 0; i < count; i++) _u16(record, idxt + 4 + i * 2),
      idxt,
    ];
    for (var i = 0; i < count; i++) {
      final begin = offsets[i], end = offsets[i + 1];
      if (begin >= end || end > record.length) {
        _mobiError('AZW3 IDXT 条目边界无效');
      }
      var at = begin;
      final labelLength = record[at++];
      if (at + labelLength + controlCount > end) {
        _mobiError('AZW3 INDX 标签超出条目边界');
      }
      final label = ascii.decode(
        Uint8List.sublistView(record, at, at + labelLength),
        allowInvalid: true,
      );
      at += labelLength;
      final control = Uint8List.sublistView(record, at, at + controlCount);
      at += controlCount;
      final tags = <int, List<int>>{};
      var controlIndex = 0;
      for (final field in fields) {
        if (field.control == 1) {
          controlIndex++;
          continue;
        }
        if (controlIndex >= control.length) {
          _mobiError('AZW3 TAGX 控制字节引用越界');
        }
        var value = control[controlIndex] & field.mask;
        if (value == 0) continue;
        int? valueCount;
        int? valueBytes;
        if (value == field.mask) {
          if (field.mask & (field.mask - 1) != 0) {
            valueBytes = _vwi(record, at, end, (next) => at = next);
          } else {
            valueCount = 1;
          }
        } else {
          var mask = field.mask;
          while (mask & 1 == 0) {
            mask >>= 1;
            value >>= 1;
          }
          valueCount = value;
        }
        final values = <int>[];
        if (valueCount != null) {
          final countValues = valueCount * field.values;
          if (countValues > 1024) _mobiError('AZW3 INDX 标签值过多');
          for (var j = 0; j < countValues; j++) {
            values.add(_vwi(record, at, end, (next) => at = next));
          }
        } else {
          final start = at;
          while (at - start < valueBytes!) {
            values.add(_vwi(record, at, end, (next) => at = next));
            if (values.length > 1024) _mobiError('AZW3 INDX 标签值过多');
          }
          if (at - start != valueBytes) {
            _mobiError('AZW3 INDX 标签值字节数不一致');
          }
        }
        if (values.isNotEmpty) {
          tags.update(
            field.tag,
            (existing) => [...existing, ...values],
            ifAbsent: () => values,
          );
        }
      }
      entries.add(_IndxEntry(label, tags));
    }
  }
  if (entries.length != totalCount) {
    _mobiError('AZW3 INDX 条目总数不一致');
  }
  return entries;
}

Uint8List _firstHtmlFlow(
  Uint8List raw,
  List<_PalmRecord> records,
  _MobiHeader mobi,
) {
  if (mobi.version < 8 ||
      mobi.fdstRecord == 0xffffffff ||
      mobi.fdstFlowCount <= 1) {
    return raw;
  }
  if (mobi.fdstRecord <= 0 || mobi.fdstRecord >= records.length) {
    _mobiError('AZW3 FDST 记录越界');
  }
  final record = records[mobi.fdstRecord].data;
  if (record.length < 12 ||
      _ascii(record, 0, 4) != 'FDST' ||
      _u32(record, 4) != 12 ||
      _u32(record, 8) != mobi.fdstFlowCount) {
    _mobiError('AZW3 FDST 头或 flow 数量无效');
  }
  _range(record, 12, mobi.fdstFlowCount * 8);
  var previous = 0;
  for (var i = 0; i < mobi.fdstFlowCount; i++) {
    final start = _u32(record, 12 + i * 8);
    final end = _u32(record, 12 + i * 8 + 4);
    if (start < previous || end < start || end > raw.length) {
      _mobiError('AZW3 FDST flow 边界无效');
    }
    previous = end;
  }
  final start = _u32(record, 12), end = _u32(record, 16);
  if (start == end) _mobiError('AZW3 的第一个 HTML flow 为空');
  return Uint8List.sublistView(raw, start, end);
}

class _Kf8Segment {
  _Kf8Segment(this.data, [this.next]);
  Uint8List data;
  _Kf8Segment? next;
}

Uint8List _reconstructKf8(
  Uint8List raw,
  List<_PalmRecord> records,
  _MobiHeader mobi,
) {
  final flow = _firstHtmlFlow(raw, records, mobi);
  final hasSkeleton = mobi.skeletonIndex != 0xffffffff;
  final hasFragments = mobi.fragmentIndex != 0xffffffff;
  if (!hasSkeleton && !hasFragments) return flow;
  if (!hasSkeleton || !hasFragments) {
    _mobiError('AZW3 skeleton 与 fragment 索引不成对');
  }
  final skeleton = _parseIndx(records, mobi.skeletonIndex);
  final fragments = _parseIndx(records, mobi.fragmentIndex);
  var fragmentIndex = 0, rawCursor = 0, outputPosition = 0;
  final output = BytesBuilder(copy: false);
  for (var i = 0; i < skeleton.length; i++) {
    final entry = skeleton[i];
    final count = entry.tag(1);
    final position = entry.tag(6, 0), length = entry.tag(6, 1);
    if (position < rawCursor || position + length > flow.length) {
      _mobiError('AZW3 skeleton 字节区间无效');
    }
    if (count > fragments.length - fragmentIndex) {
      _mobiError('AZW3 skeleton 声明的 fragment 数量过多');
    }
    rawCursor = position + length;
    _Kf8Segment? head = _Kf8Segment(
      Uint8List.sublistView(flow, position, rawCursor),
    );
    var current = head, previous = _Kf8Segment(Uint8List(0));
    var currentStart = 0, partLength = length;
    for (var j = 0; j < count; j++, fragmentIndex++) {
      final fragment = fragments[fragmentIndex];
      final insert = int.tryParse(fragment.label);
      final fileNumber = fragment.tag(3);
      final sequence = fragment.tag(4);
      final fragmentPosition = fragment.tag(6, 0);
      final fragmentLength = fragment.tag(6, 1);
      if (insert == null ||
          insert < outputPosition ||
          fileNumber != i ||
          sequence != fragmentIndex ||
          fragmentPosition > flow.length ||
          rawCursor + fragmentLength > flow.length) {
        _mobiError('AZW3 fragment 索引、顺序或源区间无效');
      }
      final relative = insert - outputPosition;
      if (relative > partLength) {
        _mobiError('AZW3 fragment 插入点越过 skeleton 末尾');
      }
      final data = Uint8List.sublistView(
        flow,
        rawCursor,
        rawCursor + fragmentLength,
      );
      rawCursor += fragmentLength;
      if (relative < currentStart) {
        _mobiError('AZW3 fragment 插入点顺序无效');
      }
      while (currentStart + current.data.length < relative) {
        final next = current.next;
        if (next == null) _mobiError('AZW3 fragment 插入链表越界');
        currentStart += current.data.length;
        previous = current;
        current = next;
      }
      final offset = relative - currentStart;
      if (offset < 0 || offset > current.data.length) {
        _mobiError('AZW3 fragment 插入点无效');
      }
      final inserted = _Kf8Segment(data);
      if (offset == 0) {
        inserted.next = current;
        if (current == head) {
          head = inserted;
        } else {
          previous.next = inserted;
        }
        current = inserted;
      } else if (offset == current.data.length) {
        inserted.next = current.next;
        current.next = inserted;
        previous = current;
        currentStart += current.data.length;
        current = inserted;
      } else {
        final tail = _Kf8Segment(
          Uint8List.sublistView(current.data, offset),
          current.next,
        );
        current.data = Uint8List.sublistView(current.data, 0, offset);
        current.next = inserted;
        inserted.next = tail;
        previous = current;
        currentStart += offset;
        current = inserted;
      }
      partLength += fragmentLength;
      if (partLength > 512 * 1024 * 1024) {
        _mobiError('AZW3 重组后的 HTML 超过 512 MiB');
      }
    }
    var part = head;
    while (part != null) {
      output.add(part.data);
      part = part.next;
    }
    outputPosition += partLength;
  }
  if (fragmentIndex != fragments.length) {
    _mobiError('AZW3 存在未被 skeleton 引用的 fragment');
  }
  if (output.length == 0) _mobiError('AZW3 重组后没有 HTML 正文');
  return output.toBytes();
}

LocalMobiDocument parseLocalMobi(Uint8List bytes) {
  final records = _palmRecords(bytes);
  final first = records.first.data;
  if (first.length < 16) _mobiError('PalmDOC 头部不完整');
  final compression = _u16(first, 0);
  final textLength = _u32(first, 4);
  final textCount = _u16(first, 8);
  final recordSize = _u16(first, 10);
  final encryption = _u16(first, 12);
  if (encryption != 0) _mobiError('不支持受 DRM 保护的 Kindle 电子书');
  if (textLength <= 0 || textLength > 512 * 1024 * 1024) {
    _mobiError('MOBI 正文为空或解压后超过 512 MiB');
  }
  if (textCount <= 0 || textCount + 1 > records.length) {
    _mobiError('MOBI 正文记录数量无效');
  }
  if (recordSize <= 0 || recordSize > 1024 * 1024) {
    _mobiError('MOBI 正文记录大小无效');
  }
  final mobi = _mobiHeader(first);
  if (16 + 160 <= first.length && mobi.length >= 160) {
    final drmCount = _u32(first, 16 + 156);
    if (drmCount != 0xffffffff && drmCount > 0) {
      _mobiError('不支持受 DRM 保护的 Kindle 电子书');
    }
  }
  if (!const {1, 2, 17480}.contains(compression)) {
    _mobiError('MOBI 使用不支持的压缩方式 $compression');
  }
  if (mobi.encoding != 65001 && mobi.encoding != 1252) {
    _mobiError('MOBI 文本编码 ${mobi.encoding} 暂不受支持');
  }
  final compressedText = _bookText(
    records,
    mobi,
    compression,
    textLength,
    textCount,
    recordSize,
  );
  final raw = _reconstructKf8(compressedText, records, mobi);
  final encoding = mobi.encoding == 65001 ? 'utf-8' : 'windows-1252';
  final markup = decodeLocalDocumentText(raw, encoding: encoding);
  var title = '', author = '';
  int? cover;
  var resourceCount = 0;
  if (mobi.length > 0) {
    if (mobi.length >= 76) {
      final nameOffset = _u32(first, 16 + 68);
      final nameLength = _u32(first, 16 + 72);
      if (nameLength > 0) {
        _range(first, nameOffset, nameLength);
        title = decodeLocalDocumentText(
          Uint8List.sublistView(first, nameOffset, nameOffset + nameLength),
          encoding: encoding,
        ).replaceAll('\u0000', '').trim();
      }
    }
    if (mobi.length >= 116 && _u32(first, 16 + 112) & 0x40 != 0) {
      final exth = 16 + mobi.length;
      _range(first, exth, 12);
      if (_ascii(first, exth, 4) != 'EXTH') {
        _mobiError('MOBI EXTH 元数据头无效');
      }
      final exthLength = _u32(first, exth + 4);
      final count = _u32(first, exth + 8);
      if (exthLength < 12 || exthLength > first.length - exth) {
        _mobiError('MOBI EXTH 长度无效');
      }
      var at = exth + 12;
      for (var i = 0; i < count; i++) {
        if (at + 8 > exth + exthLength) _mobiError('MOBI EXTH 记录不完整');
        final type = _u32(first, at), length = _u32(first, at + 4);
        if (length < 8 || at + length > exth + exthLength) {
          _mobiError('MOBI EXTH 记录长度无效');
        }
        final value = Uint8List.sublistView(first, at + 8, at + length);
        if (const {100, 503}.contains(type)) {
          final text = decodeLocalDocumentText(
            value,
            encoding: encoding,
          ).replaceAll('\u0000', '').trim();
          if (type == 100 && author.isEmpty) author = text;
          if (type == 503 && text.isNotEmpty) title = text;
        } else if (value.length == 4 && type == 201) {
          cover = _u32(value, 0);
        } else if (value.length == 4 && type == 125) {
          resourceCount = _u32(value, 0);
        }
        at += length;
      }
    }
  }
  if (title.isEmpty) {
    final name = Uint8List.sublistView(bytes, 0, 32);
    final zero = name.indexOf(0);
    title = decodeWindows1252(
      Uint8List.sublistView(name, 0, zero < 0 ? name.length : zero),
    ).trim();
  }
  final resources = <int, LocalMobiResource>{};
  if (mobi.firstImage != 0xffffffff && mobi.firstImage < records.length) {
    if (mobi.firstImage <= textCount) _mobiError('MOBI 首图记录位于正文区');
    final end = resourceCount > 0
        ? math.min(records.length, mobi.firstImage + resourceCount)
        : records.length;
    for (var i = mobi.firstImage; i < end; i++) {
      final value = records[i].data;
      final type = switch (localRasterImageExtension('', value)) {
        'jpg' => 'image/jpeg',
        final extension? => 'image/$extension',
        _ => '',
      };
      if (type.isEmpty) continue;
      if (value.length > maxConvertedImageBytes) {
        _mobiError('MOBI 单张图片超过 8 MiB');
      }
      resources[i - mobi.firstImage] = LocalMobiResource(value, type);
    }
  }
  return LocalMobiDocument(
    title: title,
    author: author,
    markup: markup,
    resources: resources,
    cover: cover,
  );
}
