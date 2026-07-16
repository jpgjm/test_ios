// 手書きの MP3 (ID3v2) / FLAC メタデータパーサー + iOS ロック画面用の
// アートワーク一時ファイル書き出し。純Dartで plugin 依存は path_provider のみ。
//
// サポート:
//   - MP3 の ID3v2.2 / v2.3 / v2.4 タグ（タイトル、アーティスト、アルバム、アートワーク）
//   - FLAC の Vorbis Comments + PICTURE ブロック
//   - アートワークバイトを iOS の一時ディレクトリに書き出し、
//     MediaItem.artUri に渡せる file:// URI を返す
//
// 制約:
//   - MP3 の unsynchronisation フラグは考慮していない（一般的な MP3 では未使用）
//   - MP3 の ID3v1（ファイル末尾 128 バイト）は読まない
//   - AAC (m4a)、WAV のタグは対応外

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 1曲分のメタデータ。フィールドは全てnull可能。
class TrackMetadata {
  final String? title;
  final String? artist;
  final String? album;
  final Uint8List? artwork;

  const TrackMetadata({this.title, this.artist, this.album, this.artwork});

  bool get isEmpty =>
      title == null && artist == null && album == null && artwork == null;
}

// ============================================================
// 公開API + キャッシュ
// ============================================================

final Map<String, TrackMetadata> _cache = {};
final Map<String, Future<TrackMetadata?>> _inflight = {};

/// アートワーク一時ファイル URI のキャッシュ（同トラックで再書き出しを防ぐ）
final Map<String, Uri> _artworkFileCache = {};
Directory? _artworkDir;
int _artworkSeq = 0;

/// メモリキャッシュをクリア（更新ボタン等から呼ぶ）。
/// 一時ファイル自体は iOS の一時ディレクトリ管理に任せる。
void clearMetadataCache() {
  _cache.clear();
  _artworkFileCache.clear();
}

/// 拡張子に応じて MP3 / FLAC のメタデータを読む。対応外は null。
Future<TrackMetadata?> readMetadata(File file) {
  final path = file.path;
  final cached = _cache[path];
  if (cached != null) return Future.value(cached);

  final active = _inflight[path];
  if (active != null) return active;

  final future = _readUncached(file);
  _inflight[path] = future;
  future.whenComplete(() => _inflight.remove(path));
  return future;
}

Future<TrackMetadata?> _readUncached(File file) async {
  final ext = p.extension(file.path).toLowerCase();
  TrackMetadata? meta;
  try {
    final raf = await file.open();
    try {
      switch (ext) {
        case '.mp3':
          meta = await _readMp3(raf);
          break;
        case '.flac':
          meta = await _readFlac(raf);
          break;
      }
    } finally {
      await raf.close();
    }
  } catch (_) {
    meta = null;
  }
  if (meta != null) _cache[file.path] = meta;
  return meta;
}

/// アートワークバイトを iOS の一時ディレクトリに書き出し、
/// その file:// URI を返す。同じトラックについては初回のみ書き出しキャッシュから返す。
/// これを MediaItem.artUri に渡すと iOS のロック画面 / Control Center /
/// 車載 CarPlay 等にアートワークが表示される。
Future<Uri?> writeArtworkToTemp(String trackPath, Uint8List? bytes) async {
  final cached = _artworkFileCache[trackPath];
  if (cached != null) return cached;
  if (bytes == null || bytes.isEmpty) return null;

  try {
    _artworkDir ??= await _ensureArtworkDir();
    final ext = _detectImageExt(bytes);
    final seq = _artworkSeq++;
    final file = File(p.join(_artworkDir!.path, 'art_$seq$ext'));
    await file.writeAsBytes(bytes);
    final uri = file.uri;
    _artworkFileCache[trackPath] = uri;
    return uri;
  } catch (_) {
    return null;
  }
}

Future<Directory> _ensureArtworkDir() async {
  final tmp = await getTemporaryDirectory();
  final dir = Directory(p.join(tmp.path, 'mp_artwork'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// バイナリマジックから画像形式を推定して拡張子を返す。
String _detectImageExt(Uint8List bytes) {
  // JPEG: FF D8 FF
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return '.jpg';
  }
  // PNG: 89 50 4E 47
  if (bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return '.png';
  }
  return '.jpg'; // 不明時は最も一般的な JPEG を仮定
}

// ============================================================
// MP3 (ID3v2)
// ============================================================
//
// ID3v2 ヘッダー (10 bytes):
//   0-2: "ID3"
//   3:   major version (2, 3, or 4)
//   4:   revision
//   5:   flags
//   6-9: tag size (syncsafe 32-bit: 7 bits per byte)

Future<TrackMetadata?> _readMp3(RandomAccessFile raf) async {
  await raf.setPosition(0);
  final header = await raf.read(10);
  if (header.length < 10) return null;
  if (header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) {
    return null;
  }

  final major = header[3];
  final flags = header[5];
  final hasExtHeader = (flags & 0x40) != 0;
  final tagSize = _syncsafe32(header, 6);
  if (tagSize <= 0) return null;

  final body = await raf.read(tagSize);
  if (body.length < tagSize) return null;

  var offset = 0;

  if (hasExtHeader) {
    if (offset + 4 > body.length) return null;
    if (major == 4) {
      final ehSize = _syncsafe32(body, offset);
      offset += ehSize;
    } else {
      final ehSize = _uint32BE(body, offset);
      offset += 4 + ehSize;
    }
  }

  String? title;
  String? artist;
  String? album;
  Uint8List? artwork;

  final idLen = major == 2 ? 3 : 4;
  final hdrLen = major == 2 ? 6 : 10;

  while (offset + hdrLen <= body.length) {
    if (body[offset] == 0) break; // padding

    final frameId = String.fromCharCodes(body.sublist(offset, offset + idLen));

    int frameSize;
    if (major == 2) {
      frameSize = (body[offset + 3] << 16) |
          (body[offset + 4] << 8) |
          body[offset + 5];
    } else if (major == 4) {
      frameSize = _syncsafe32(body, offset + 4);
    } else {
      frameSize = _uint32BE(body, offset + 4);
    }

    if (frameSize <= 0 || offset + hdrLen + frameSize > body.length) break;

    final data =
        body.sublist(offset + hdrLen, offset + hdrLen + frameSize);

    switch (frameId) {
      case 'TIT2':
      case 'TT2':
        title ??= _decodeTextFrame(data);
        break;
      case 'TPE1':
      case 'TP1':
        artist ??= _decodeTextFrame(data);
        break;
      case 'TALB':
      case 'TAL':
        album ??= _decodeTextFrame(data);
        break;
      case 'APIC':
      case 'PIC':
        artwork ??= _decodeApicFrame(data, isV22: major == 2);
        break;
    }

    offset += hdrLen + frameSize;
  }

  final meta = TrackMetadata(
    title: title,
    artist: artist,
    album: album,
    artwork: artwork,
  );
  return meta.isEmpty ? null : meta;
}

String? _decodeTextFrame(Uint8List data) {
  if (data.isEmpty) return null;
  final encoding = data[0];
  final text = _decodeString(data.sublist(1), encoding);
  if (text == null) return null;
  final nullIdx = text.indexOf('\x00');
  final result = nullIdx >= 0 ? text.substring(0, nullIdx) : text;
  final trimmed = result.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Uint8List? _decodeApicFrame(Uint8List data, {required bool isV22}) {
  if (data.length < 4) return null;
  final encoding = data[0];
  var offset = 1;

  if (isV22) {
    if (offset + 3 > data.length) return null;
    offset += 3;
  } else {
    while (offset < data.length && data[offset] != 0) {
      offset++;
    }
    offset++;
  }

  if (offset >= data.length) return null;
  offset++; // picture type byte

  if (encoding == 0x01 || encoding == 0x02) {
    while (offset + 1 < data.length &&
        !(data[offset] == 0 && data[offset + 1] == 0)) {
      offset += 2;
    }
    offset += 2;
  } else {
    while (offset < data.length && data[offset] != 0) {
      offset++;
    }
    offset++;
  }

  if (offset >= data.length) return null;
  return Uint8List.fromList(data.sublist(offset));
}

String? _decodeString(Uint8List bytes, int encoding) {
  try {
    switch (encoding) {
      case 0x00:
        return String.fromCharCodes(bytes);
      case 0x01:
        return _decodeUtf16Bom(bytes);
      case 0x02:
        return _decodeUtf16(bytes, bigEndian: true);
      case 0x03:
        return utf8.decode(bytes, allowMalformed: true);
      default:
        return utf8.decode(bytes, allowMalformed: true);
    }
  } catch (_) {
    return null;
  }
}

String? _decodeUtf16Bom(Uint8List bytes) {
  if (bytes.length < 2) return null;
  final bigEndian = bytes[0] == 0xFE && bytes[1] == 0xFF;
  final littleEndian = bytes[0] == 0xFF && bytes[1] == 0xFE;
  if (bigEndian || littleEndian) {
    return _decodeUtf16(bytes.sublist(2), bigEndian: bigEndian);
  }
  return _decodeUtf16(bytes, bigEndian: false);
}

String _decodeUtf16(Uint8List bytes, {required bool bigEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    final unit = bigEndian
        ? (bytes[i] << 8) | bytes[i + 1]
        : bytes[i] | (bytes[i + 1] << 8);
    if (unit == 0) break;
    units.add(unit);
  }
  return String.fromCharCodes(units);
}

// ============================================================
// FLAC (Vorbis comments + PICTURE block)
// ============================================================

Future<TrackMetadata?> _readFlac(RandomAccessFile raf) async {
  await raf.setPosition(0);
  final magic = await raf.read(4);
  if (magic.length < 4 ||
      magic[0] != 0x66 ||
      magic[1] != 0x4C ||
      magic[2] != 0x61 ||
      magic[3] != 0x43) {
    return null;
  }

  String? title;
  String? artist;
  String? album;
  Uint8List? artwork;

  var isLast = false;
  while (!isLast) {
    final header = await raf.read(4);
    if (header.length < 4) break;
    isLast = (header[0] & 0x80) != 0;
    final blockType = header[0] & 0x7F;
    final blockLen = (header[1] << 16) | (header[2] << 8) | header[3];

    if (blockLen <= 0 || blockLen > 100 * 1024 * 1024) break;

    // 興味のないブロックは seek でスキップして高速化
    if (blockType != 4 && blockType != 6) {
      await raf.setPosition(await raf.position() + blockLen);
      continue;
    }

    final block = await raf.read(blockLen);
    if (block.length < blockLen) break;

    switch (blockType) {
      case 4: // VORBIS_COMMENT
        final comments = _parseVorbisComment(block);
        title ??= _lookup(comments, 'TITLE');
        artist ??= _lookup(comments, 'ARTIST') ??
            _lookup(comments, 'ALBUMARTIST');
        album ??= _lookup(comments, 'ALBUM');
        break;
      case 6: // PICTURE
        artwork ??= _parseFlacPicture(block);
        break;
    }
  }

  final meta = TrackMetadata(
    title: title,
    artist: artist,
    album: album,
    artwork: artwork,
  );
  return meta.isEmpty ? null : meta;
}

Map<String, String> _parseVorbisComment(Uint8List data) {
  final result = <String, String>{};
  var offset = 0;

  if (offset + 4 > data.length) return result;
  final vendorLen = _uint32LE(data, offset);
  offset += 4;
  if (vendorLen < 0 || offset + vendorLen > data.length) return result;
  offset += vendorLen;

  if (offset + 4 > data.length) return result;
  final count = _uint32LE(data, offset);
  offset += 4;
  if (count < 0 || count > 100000) return result;

  for (var i = 0; i < count; i++) {
    if (offset + 4 > data.length) break;
    final len = _uint32LE(data, offset);
    offset += 4;
    if (len < 0 || offset + len > data.length) break;
    final bytes = data.sublist(offset, offset + len);
    offset += len;
    try {
      final str = utf8.decode(bytes, allowMalformed: true);
      final eq = str.indexOf('=');
      if (eq > 0) {
        final key = str.substring(0, eq).toUpperCase();
        final value = str.substring(eq + 1);
        result.putIfAbsent(key, () => value);
      }
    } catch (_) {}
  }
  return result;
}

Uint8List? _parseFlacPicture(Uint8List data) {
  try {
    var offset = 4;
    final mimeLen = _uint32BE(data, offset);
    offset += 4 + mimeLen;
    if (offset + 4 > data.length) return null;
    final descLen = _uint32BE(data, offset);
    offset += 4 + descLen;
    if (offset + 20 > data.length) return null;
    offset += 16;
    final picLen = _uint32BE(data, offset);
    offset += 4;
    if (picLen <= 0 || offset + picLen > data.length) return null;
    return Uint8List.fromList(data.sublist(offset, offset + picLen));
  } catch (_) {
    return null;
  }
}

String? _lookup(Map<String, String> map, String key) {
  final v = map[key];
  if (v == null) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

// ============================================================
// バイト列読み取りヘルパー
// ============================================================

int _syncsafe32(Uint8List data, int offset) {
  return ((data[offset] & 0x7F) << 21) |
      ((data[offset + 1] & 0x7F) << 14) |
      ((data[offset + 2] & 0x7F) << 7) |
      (data[offset + 3] & 0x7F);
}

int _uint32BE(Uint8List data, int offset) {
  return (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];
}

int _uint32LE(Uint8List data, int offset) {
  return data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}
