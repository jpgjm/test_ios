import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';

/// iOS の MPMediaLibrary から取得したライブラリの曲を表示・再生するページ。
/// 内部的には on_audio_query が MPMediaQuery を呼び出している。
///
/// 前提:
///   - Info.plist に NSAppleMusicUsageDescription が設定されていること（ワークフローで追加済み）
///   - 初回起動時に許可ダイアログが表示され、ユーザーが「許可」を選択すること
class MusicLibraryPage extends StatefulWidget {
  final AudioPlayer player;
  const MusicLibraryPage({super.key, required this.player});

  @override
  State<MusicLibraryPage> createState() => _MusicLibraryPageState();
}

class _MusicLibraryPageState extends State<MusicLibraryPage> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  bool? _hasPermission;

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    try {
      final ok = await _audioQuery.checkAndRequest(retryRequest: false);
      if (!mounted) return;
      setState(() => _hasPermission = ok);
    } catch (e) {
      if (!mounted) return;
      setState(() => _hasPermission = false);
    }
  }

  /// タップした曲を含むリスト全体をキュー化して再生。
  /// iOSではSongModel.dataは ipod-library:// 形式のURIになる。
  /// just_audio (AVPlayer) がそのまま再生できる。
  Future<void> _playSong(List<SongModel> songs, int startIndex) async {
    final sources = songs.map((s) {
      return AudioSource.uri(
        Uri.parse(s.data),
        tag: MediaItem(
          id: s.data,
          title: s.title,
          artist: s.artist,
          album: s.album,
          // ライブラリの曲のアートワークは QueryArtworkWidget が表示するので、
          // ここでは artUri を渡さない。ロック画面には title/artist/album のみ。
        ),
      );
    }).toList();

    try {
      await widget.player.setAudioSource(
        ConcatenatingAudioSource(children: sources),
        initialIndex: startIndex,
      );
      await widget.player.play();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('再生エラー: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ライブラリ'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_hasPermission == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasPermission == false) {
      return _PermissionDeniedView(onRetry: _requestPermission);
    }
    return FutureBuilder<List<SongModel>>(
      future: _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        ignoreCase: true,
      ),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('エラー: ${snap.error}'),
            ),
          );
        }
        final songs = snap.data ?? [];
        if (songs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'ライブラリに曲がありません。\n'
                'iOSの「ミュージック」アプリで曲を追加してください。',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          itemCount: songs.length,
          itemBuilder: (context, i) {
            final s = songs[i];
            return ListTile(
              leading: QueryArtworkWidget(
                id: s.id,
                type: ArtworkType.AUDIO,
                artworkBorder: BorderRadius.circular(4),
                artworkWidth: 48,
                artworkHeight: 48,
                nullArtworkWidget: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.music_note),
                ),
              ),
              title: Text(
                s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                s.artist ?? '不明なアーティスト',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _playSong(songs, i),
            );
          },
        );
      },
    );
  }
}

class _PermissionDeniedView extends StatelessWidget {
  final VoidCallback onRetry;
  const _PermissionDeniedView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.library_music_outlined, size: 64),
            const SizedBox(height: 16),
            const Text(
              'ライブラリへのアクセスが\n許可されていません',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              '「設定」→「Music Player」→「メディアと Apple Music」を\n'
              'オンにすると、iTunes/Apple Music ライブラリの曲を\n'
              '再生できるようになります。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再度リクエスト'),
            ),
          ],
        ),
      ),
    );
  }
}
