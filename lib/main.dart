import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'metadata.dart';
import 'music_library_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.music_player.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );
  runApp(const MusicPlayerApp());
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Player',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _audioExtensions = {'.flac', '.mp3', '.aac', '.wav', '.m4a'};
  static const _rootFolderName = 'Music Player';
  static const _readmeFileName = 'README.txt';
  static const _readmeContent = '''Music Player
============

このフォルダに音楽ファイルを配置すると、
Music Player アプリで再生できます。

対応形式:
  - MP3  (.mp3)
  - FLAC (.flac)
  - AAC  (.aac)
  - WAV  (.wav)
  - M4A  (.m4a)

推奨されるフォルダ構成:
  Music Player/
    アルバム1/
      01_トラック名.flac
      02_トラック名.flac
    お気に入り/
      song1.mp3
      song2.aac

タグ情報（タイトル、アーティスト、アルバム、アートワーク）は
MP3 と FLAC ファイルで自動的に読み込まれます。
それ以外の形式はファイル名で表示されます。

ファイルの追加方法:
  1. iPad の「ファイル」アプリを開く
  2. 「このiPad内」→「Music Player」→「Music Player」の順で開く
  3. 音楽ファイルをドラッグ&ドロップ、または
     LocalSend / AirDrop で受信して保存

Apple Music / iTunes ライブラリの曲を再生したい場合は、
右上のライブラリボタン（音符アイコン）から利用できます。

このファイルは自動的に生成されました。
削除しても問題ありません（次回アプリ起動時に再作成されます）。
''';

  final AudioPlayer _player = AudioPlayer();
  Directory? _rootDir;
  Directory? _currentDir;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final docs = await getApplicationDocumentsDirectory();
    final rootDir = Directory(p.join(docs.path, _rootFolderName));
    if (!await rootDir.exists()) {
      try {
        await rootDir.create(recursive: true);
      } catch (_) {}
    }
    await _ensureReadme(rootDir);
    if (!mounted) return;
    setState(() {
      _rootDir = rootDir;
      _currentDir = rootDir;
    });
  }

  Future<void> _ensureReadme(Directory dir) async {
    try {
      final readme = File(p.join(dir.path, _readmeFileName));
      if (!await readme.exists()) {
        await readme.writeAsString(_readmeContent);
      }
    } catch (_) {}
  }

  bool _isAudio(File f) =>
      _audioExtensions.contains(p.extension(f.path).toLowerCase());

  List<FileSystemEntity> _listEntries(Directory dir) {
    try {
      final entries = dir.listSync();
      final folders = entries.whereType<Directory>().toList()
        ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      final files = entries.whereType<File>().where(_isAudio).toList()
        ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      return [...folders, ...files];
    } catch (_) {
      return [];
    }
  }

  Future<void> _playFile(File file) async {
    final folder = file.parent;
    final audioFiles = _listEntries(folder).whereType<File>().toList();
    final startIndex = audioFiles.indexWhere((f) => f.path == file.path);
    if (startIndex < 0) return;

    final metas = await Future.wait(audioFiles.map(readMetadata));

    final artUris = await Future.wait(
      List.generate(audioFiles.length, (i) {
        return writeArtworkToTemp(audioFiles[i].path, metas[i]?.artwork);
      }),
    );

    final sources = <AudioSource>[];
    for (var i = 0; i < audioFiles.length; i++) {
      final f = audioFiles[i];
      final meta = metas[i];
      sources.add(AudioSource.uri(
        Uri.file(f.path),
        tag: MediaItem(
          id: f.path,
          title: meta?.title ?? p.basenameWithoutExtension(f.path),
          artist: meta?.artist,
          album: meta?.album ?? p.basename(folder.path),
          artUri: artUris[i],
        ),
      ));
    }

    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: sources),
        initialIndex: startIndex,
      );
      await _player.play();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('再生エラー: $e')),
      );
    }
  }

  Future<void> _openInFilesApp(Directory dir) async {
    final url = Uri.parse('shareddocuments://${Uri.encodeFull(dir.path)}');
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ファイルアプリを開けませんでした')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e')),
      );
    }
  }

  void _openLibrary() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MusicLibraryPage(player: _player),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentDir == null || _rootDir == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isRoot = _currentDir!.path == _rootDir!.path;
    final entries = _listEntries(_currentDir!);
    final relPath =
        isRoot ? '' : p.relative(_currentDir!.path, from: _rootDir!.path);

    return Scaffold(
      appBar: AppBar(
        leading: isRoot
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    setState(() => _currentDir = _currentDir!.parent),
              ),
        title: Text(isRoot ? 'Music Player' : relPath),
        actions: [
          IconButton(
            icon: const Icon(Icons.library_music),
            tooltip: 'ライブラリ（iTunes / Apple Music）',
            onPressed: _openLibrary,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'キャッシュクリア + 再読み込み',
            onPressed: () {
              clearMetadataCache();
              setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: entries.isEmpty
                ? _EmptyView(
                    onOpenFolder: () => _openInFilesApp(_rootDir!),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, i) => _entryTile(entries[i]),
                  ),
          ),
          _MiniPlayer(player: _player),
        ],
      ),
    );
  }

  Widget _entryTile(FileSystemEntity e) {
    if (e is Directory) {
      final count = _listEntries(e).length;
      return ListTile(
        leading: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.folder, size: 40),
        ),
        title: Text(p.basename(e.path)),
        subtitle: Text('$count 項目'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => setState(() => _currentDir = e),
      );
    } else if (e is File) {
      return FutureBuilder<TrackMetadata?>(
        future: readMetadata(e),
        builder: (context, snap) {
          final meta = snap.data;
          final title = meta?.title ?? p.basenameWithoutExtension(e.path);
          final subtitle = meta?.artist ??
              p.extension(e.path).toUpperCase().replaceFirst('.', '');
          return ListTile(
            leading: _Artwork(bytes: meta?.artwork, size: 48),
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle:
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _playFile(e),
          );
        },
      );
    }
    return const SizedBox.shrink();
  }
}

// ============================================================
// Widgets
// ============================================================

class _Artwork extends StatelessWidget {
  final Uint8List? bytes;
  final double size;
  const _Artwork({required this.bytes, required this.size});

  @override
  Widget build(BuildContext context) {
    final b = bytes;
    if (b != null && b.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          b,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(Icons.music_note, size: size * 0.5),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onOpenFolder;
  const _EmptyView({required this.onOpenFolder});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.library_music, size: 64),
            const SizedBox(height: 16),
            const Text(
              '音楽ファイルがありません',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Music Player フォルダに\n'
              'flac / mp3 / aac / wav / m4a ファイルを配置してください。\n'
              '(LocalSend や AirDrop 経由での転送も可)',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onOpenFolder,
              icon: const Icon(Icons.folder_open),
              label: const Text('Music Player フォルダを開く'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  final AudioPlayer player;
  const _MiniPlayer({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SequenceState?>(
      stream: player.sequenceStateStream,
      builder: (context, snap) {
        final current = snap.data?.currentSource?.tag as MediaItem?;
        if (current == null) return const SizedBox.shrink();
        final filePath = current.id;
        // ローカルファイル(file:// or 通常パス)のときだけメタデータ再読み込みを試みる。
        // ライブラリの曲(ipod-library://)はローカル読み込み対象外。
        final isLocal = !filePath.startsWith('ipod-library://');

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (isLocal)
                    FutureBuilder<TrackMetadata?>(
                      future: readMetadata(File(filePath)),
                      builder: (context, metaSnap) {
                        return _Artwork(
                          bytes: metaSnap.data?.artwork,
                          size: 56,
                        );
                      },
                    )
                  else
                    const _Artwork(bytes: null, size: 56),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (current.artist != null)
                          Text(
                            current.artist!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          )
                        else if (current.album != null)
                          Text(
                            current.album!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    onPressed:
                        player.hasPrevious ? player.seekToPrevious : null,
                  ),
                  StreamBuilder<PlayerState>(
                    stream: player.playerStateStream,
                    builder: (context, snap) {
                      final playing = snap.data?.playing ?? false;
                      return IconButton(
                        iconSize: 36,
                        icon: Icon(
                            playing ? Icons.pause_circle : Icons.play_circle),
                        onPressed: () =>
                            playing ? player.pause() : player.play(),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: player.hasNext ? player.seekToNext : null,
                  ),
                ],
              ),
              StreamBuilder<Duration>(
                stream: player.positionStream,
                builder: (context, posSnap) {
                  return StreamBuilder<Duration?>(
                    stream: player.durationStream,
                    builder: (context, durSnap) {
                      final pos = posSnap.data ?? Duration.zero;
                      final dur = durSnap.data ?? Duration.zero;
                      final maxMs = dur.inMilliseconds.toDouble();
                      final curMs =
                          pos.inMilliseconds.toDouble().clamp(0.0, maxMs);
                      return Row(
                        children: [
                          Text(_fmt(pos), style: const TextStyle(fontSize: 11)),
                          Expanded(
                            child: Slider(
                              value: curMs,
                              max: maxMs > 0 ? maxMs : 1,
                              onChanged: (v) => player
                                  .seek(Duration(milliseconds: v.toInt())),
                            ),
                          ),
                          Text(_fmt(dur), style: const TextStyle(fontSize: 11)),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
