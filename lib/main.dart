import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.eribeat.audio',
    androidNotificationChannelName: 'ERIBeat music',
    androidNotificationOngoing: true,
  );
  runApp(const ERiBeatApp());
}

class ERiBeatApp extends StatelessWidget {
  const ERiBeatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ERIBeat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF20D997),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF101412),
        useMaterial3: true,
      ),
      home: const MusicHomePage(),
    );
  }
}

class AudioTrack {
  const AudioTrack({
    required this.title,
    required this.artist,
    required this.audioUrl,
    required this.pageUrl,
    required this.license,
  });

  final String title;
  final String artist;
  final String audioUrl;
  final String pageUrl;
  final String license;
}

class MusicHomePage extends StatefulWidget {
  const MusicHomePage({super.key});

  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage> {
  final AudioPlayer _player = AudioPlayer();
  final TextEditingController _searchController = TextEditingController();
  final List<AudioTrack> _tracks = [];
  StreamSubscription<int?>? _indexSubscription;

  AudioTrack? _currentTrack;
  String _status = 'Po kërkoj muzikë me licencë të hapur…';
  bool _isSearching = false;
  bool _isShuffling = false;
  LoopMode _loopMode = LoopMode.off;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.positionStream.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _player.durationStream.listen((value) {
      if (mounted) setState(() => _duration = value ?? Duration.zero);
    });
    _indexSubscription = _player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < _tracks.length && mounted) {
        setState(() => _currentTrack = _tracks[index]);
      }
    });
    _searchController.text = 'music';
    _search('music');
  }

  @override
  void dispose() {
    _indexSubscription?.cancel();
    _searchController.dispose();
    _player.dispose();
    super.dispose();
  }

  String _plainText(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toString()
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _supportedAudio(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return const ['.mp3', '.ogg', '.oga', '.opus', '.wav', '.flac', '.m4a']
        .any(path.endsWith);
  }

  Future<void> _search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      setState(() => _status = 'Shkruaj emrin e këngës ose artistit.');
      return;
    }

    setState(() {
      _isSearching = true;
      _status = 'Duke kërkuar audio të licencuar…';
      _tracks.clear();
    });

    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'generator': 'search',
        'gsrsearch': 'filetype:audio $cleanQuery',
        'gsrnamespace': '6',
        'gsrlimit': '30',
        'prop': 'imageinfo',
        'iiprop': 'url|extmetadata',
        'format': 'json',
        'origin': '*',
      });

      final response = await http.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': 'ERIBeatMusicPlayer/1.0 (Flutter app)',
      }).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('Kërkimi nuk u përgjigj (${response.statusCode}).');
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
      final queryData = decoded['query'] as Map<String, dynamic>?;
      final pages = queryData?['pages'] as Map<String, dynamic>?;

      final found = <AudioTrack>[];
      if (pages != null) {
        for (final pageValue in pages.values) {
          final page = pageValue as Map<String, dynamic>;
          final title = _plainText(page['title'], fallback: 'Audio file');
          final infos = page['imageinfo'] as List<dynamic>?;
          if (infos == null || infos.isEmpty) continue;

          final info = infos.first as Map<String, dynamic>;
          final audioUrl = (info['url'] ?? '').toString();
          if (audioUrl.isEmpty || !_supportedAudio(audioUrl)) continue;

          final metadata = info['extmetadata'] as Map<String, dynamic>? ?? {};
          final artist = _plainText(
            metadata['Artist']?['value'],
            fallback: 'Artist not listed',
          );
          final license = _plainText(
            metadata['LicenseShortName']?['value'],
            fallback: 'Check license on source page',
          );
          final pageUrl = (metadata['PageURL']?['value'] ??
                  'https://commons.wikimedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}')
              .toString();

          found.add(AudioTrack(
            title: title.replaceFirst(RegExp(r'^File:'), ''),
            artist: artist,
            audioUrl: audioUrl,
            pageUrl: pageUrl,
            license: license,
          ));
        }
      }

      if (!mounted) return;
      setState(() {
        _tracks.addAll(found);
        _status = found.isEmpty
            ? 'Nuk u gjet audio e përshtatshme. Provo një fjalë tjetër, p.sh. piano, jazz ose guitar.'
            : 'U gjetën ${found.length} skedarë audio. Kontrollo licencën dhe atribuimin te burimi.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status =
          'Nuk u krye kërkimi. Kontrollo internetin dhe provo përsëri.');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _playTrack(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    final track = _tracks[index];
    try {
      setState(() {
        _currentTrack = track;
        _status = 'Duke hapur: ${track.title}';
        _position = Duration.zero;
      });

      final sources = _tracks.map((item) {
        return AudioSource.uri(
          Uri.parse(item.audioUrl),
          tag: MediaItem(
            id: item.audioUrl,
            title: item.title,
            artist: item.artist,
            album: 'Wikimedia Commons • ${item.license}',
          ),
        );
      }).toList();

      await _player.setAudioSource(
        ConcatenatingAudioSource(children: sources),
        initialIndex: index,
      );
      await _player.play();
      if (mounted) setState(() => _status = 'Po luhet');
    } catch (_) {
      if (!mounted) return;
      setState(() => _status =
          'Ky skedar nuk u hap. Provo një tjetër; disa formate mund të mos mbështeten.');
    }
  }

  Future<void> _togglePlay() async {
    if (_player.playing) {
      await _player.pause();
    } else if (_player.audioSource != null) {
      await _player.play();
    } else if (_tracks.isNotEmpty) {
      await _playTrack(0);
    } else {
      await _search(_searchController.text);
    }
  }

  Future<void> _toggleShuffle() async {
    final next = !_isShuffling;
    await _player.setShuffleModeEnabled(next);
    if (mounted) setState(() => _isShuffling = next);
  }

  Future<void> _toggleRepeat() async {
    final next = _loopMode == LoopMode.off
        ? LoopMode.all
        : _loopMode == LoopMode.all
            ? LoopMode.one
            : LoopMode.off;
    await _player.setLoopMode(next);
    if (mounted) setState(() => _loopMode = next);
  }

  String _time(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$minutes:$seconds'
        : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final posMs = _position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.graphic_eq, color: Color(0xFF20D997)),
            SizedBox(width: 8),
            Text('ERIBeat', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Kërko muzikë',
            onPressed: _isSearching ? null : () => _search(_searchController.text),
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'Kërko muzikë, artist ose instrument…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    onPressed: _isSearching
                        ? null
                        : () => _search(_searchController.text),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1B231F),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (_isSearching) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Audio me licencë të hapur',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Text('${_tracks.length} rezultate',
                      style: TextStyle(color: Colors.white.withOpacity(0.6))),
                ],
              ),
            ),
            Expanded(
              child: _tracks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.library_music,
                                size: 64, color: Color(0xFF20D997)),
                            const SizedBox(height: 16),
                            Text(_status, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _isSearching
                                  ? null
                                  : () => _search(_searchController.text),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Provo përsëri'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _tracks.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: Colors.white.withOpacity(0.06),
                      ),
                      itemBuilder: (context, index) {
                        final track = _tracks[index];
                        final isCurrent = _currentTrack?.audioUrl == track.audioUrl;
                        return ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1D352B),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isCurrent ? Icons.equalizer : Icons.music_note,
                              color: const Color(0xFF20D997),
                            ),
                          ),
                          title: Text(track.title,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${track.artist}\n${track.license}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: 'Luaj',
                            onPressed: () => _playTrack(index),
                            icon: Icon(
                              isCurrent && _player.playing
                                  ? Icons.graphic_eq
                                  : Icons.play_circle_fill,
                              color: const Color(0xFF20D997),
                              size: 30,
                            ),
                          ),
                          onTap: () => _playTrack(index),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: const Color(0xFF19201C),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF234333),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.music_note,
                            color: Color(0xFF20D997), size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentTrack?.title ?? 'Zgjidh një këngë',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _currentTrack?.artist ?? _status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: posMs,
                    max: maxMs,
                    onChanged: _duration == Duration.zero
                        ? null
                        : (value) => _player.seek(
                              Duration(milliseconds: value.round()),
                            ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_time(_position),
                          style: const TextStyle(fontSize: 11)),
                      Text(_time(_duration),
                          style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        tooltip: 'Përziej',
                        onPressed: _toggleShuffle,
                        color: _isShuffling
                            ? const Color(0xFF20D997)
                            : Colors.white70,
                        icon: const Icon(Icons.shuffle),
                      ),
                      IconButton(
                        tooltip: 'Kënga e mëparshme',
                        onPressed: () async {
                          if (_player.hasPrevious) await _player.seekToPrevious();
                        },
                        icon: const Icon(Icons.skip_previous, size: 34),
                      ),
                      StreamBuilder<PlayerState>(
                        stream: _player.playerStateStream,
                        builder: (context, snapshot) {
                          final playing = snapshot.data?.playing ?? false;
                          final loading = snapshot.data?.processingState ==
                                  ProcessingState.loading ||
                              snapshot.data?.processingState ==
                                  ProcessingState.buffering;
                          return IconButton.filled(
                            tooltip: playing ? 'Pauzë' : 'Luaj',
                            onPressed: _togglePlay,
                            iconSize: 32,
                            icon: loading
                                ? const SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Icon(playing ? Icons.pause : Icons.play_arrow),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'Kënga tjetër',
                        onPressed: () async {
                          if (_player.hasNext) await _player.seekToNext();
                        },
                        icon: const Icon(Icons.skip_next, size: 34),
                      ),
                      IconButton(
                        tooltip: 'Përsërit',
                        onPressed: _toggleRepeat,
                        color: _loopMode == LoopMode.off
                            ? Colors.white70
                            : const Color(0xFF20D997),
                        icon: Icon(_loopMode == LoopMode.one
                            ? Icons.repeat_one
                            : Icons.repeat),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Burimi: Wikimedia Commons • kontrollo licencën dhe kushtet e atribuimit.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
