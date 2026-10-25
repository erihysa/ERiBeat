
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

late ERIAudioHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  audioHandler = await AudioService.init(
    builder: ERIAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.eribeat.audio',
      androidNotificationChannelName: 'ERIBeat Music',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,
    ),
  ) as ERIAudioHandler;

  runApp(const ERIBeatApp());
}

class Song {
  final String id;
  final String title;
  final String artist;
  final bool isMp3;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.isMp3 = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'isMp3': isMp3,
      };

  factory Song.fromJson(Map<String, dynamic> json) => Song(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Pa titull',
        artist: json['artist'] as String? ?? 'Artist i panjohur',
        isMp3: json['isMp3'] as bool? ?? false,
      );

  factory Song.fromVideo(yt.Video video) => Song(
        id: video.id.value,
        title: video.title,
        artist: video.author,
      );
}

class ERIAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer player = AudioPlayer();
  final Random _random = Random();

  List<Song> _songs = [];
  int _index = 0;

  bool shuffleEnabled = false;
  bool repeatEnabled = false;
  bool _changingTrack = false;

  ERIAudioHandler() {
    player.playbackEventStream.listen((event) {
      playbackState.add(
        PlaybackState(
          controls: [
            MediaControl.skipToPrevious,
            if (player.playing)
              MediaControl.pause
            else
              MediaControl.play,
            MediaControl.skipToNext,
            MediaControl.stop,
          ],
          androidCompactActionIndices: const [0, 1, 2],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          processingState: _mapState(player.processingState),
          playing: player.playing,
          updatePosition: player.position,
          bufferedPosition: player.bufferedPosition,
          speed: player.speed,
          queueIndex: _index,
        ),
      );
    });

    player.errorStream.listen((error) {
      playbackState.add(
        playbackState.value.copyWith(
          playing: false,
          processingState: AudioProcessingState.error,
          errorMessage: error.message,
        ),
      );
    });

    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !_changingTrack) {
        if (repeatEnabled) {
          player.seek(Duration.zero);
          player.play();
        } else if (_songs.length > 1) {
          skipToNext();
        }
      }
    });
  }

  AudioProcessingState _mapState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  MediaItem _mediaItem(Song song) => MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: 'ERIBeat',
      );

  Future<void> playQueue(
    List<Song> songs, {
    int startIndex = 0,
  }) async {
    final audioSongs = songs.where((s) => s.isMp3).toList();
    if (audioSongs.isEmpty) return;

    _songs = audioSongs;
    _index = startIndex.clamp(0, _songs.length - 1);

    queue.add(_songs.map(_mediaItem).toList());
    await _loadCurrentSong();
  }

  Future<void> _loadCurrentSong() async {
    if (_songs.isEmpty) return;

    _changingTrack = true;
    try {
      final song = _songs[_index];
      final uri = Uri.tryParse(song.id);

      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty) {
        throw ArgumentError(
          'Vendos një URL HTTPS të vlefshme për audion.',
        );
      }

      mediaItem.add(_mediaItem(song));
      await player.setUrl(song.id);
      await player.play();
    } finally {
      _changingTrack = false;
    }
  }

  Future<void> toggleShuffle() async {
    shuffleEnabled = !shuffleEnabled;
  }

  Future<void> toggleRepeat() async {
    repeatEnabled = !repeatEnabled;
  }

  Future<void> changeSpeed(double speed) =>
      player.setSpeed(speed);

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) =>
      player.seek(position);

  @override
  Future<void> seekForward(bool begin) async {
    if (!begin) return;
    final next = player.position + const Duration(seconds: 15);
    final duration = player.duration;

    await player.seek(
      duration != null && next > duration ? duration : next,
    );
  }

  @override
  Future<void> seekBackward(bool begin) async {
    if (!begin) return;

    final next = player.position - const Duration(seconds: 15);
    await player.seek(
      next < Duration.zero ? Duration.zero : next,
    );
  }

  @override
  Future<void> skipToNext() async {
    if (_songs.length < 2) return;

    if (shuffleEnabled) {
      var next = _index;
      while (next == _index) {
        next = _random.nextInt(_songs.length);
      }
      _index = next;
    } else {
      _index = (_index + 1) % _songs.length;
    }

    await _loadCurrentSong();
  }

  @override
  Future<void> skipToPrevious() async {
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
      return;
    }

    if (_songs.length < 2) {
      await player.seek(Duration.zero);
      return;
    }

    _index = (_index - 1 + _songs.length) % _songs.length;
    await _loadCurrentSong();
  }

  @override
  Future<void> stop() async {
    await player.stop();
    mediaItem.add(null);
    queue.add([]);
    _songs = [];
    _index = 0;
    await super.stop();
  }
}

class ERIBeatApp extends StatelessWidget {
  const ERIBeatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ERIBeat',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0D18),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF16D9F5),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF101329),
          foregroundColor: Colors.white,
        ),
      ),
      home: const MusicHome(),
    );
  }
}

class MusicHome extends StatefulWidget {
  const MusicHome({super.key});

  @override
  State<MusicHome> createState() => _MusicHomeState();
}

class _MusicHomeState extends State<MusicHome> {
  final yt.YoutubeExplode _youtube = yt.YoutubeExplode();
  final TextEditingController _search = TextEditingController();

  YoutubePlayerController? _videoController;
  Song? _currentSong;

  List<Song> _results = [];
  List<Song> _favorites = [];
  List<Song> _activeQueue = [];
  int _activeIndex = 0;

  Map<String, List<Song>> _playlists = {
    'Rock': <Song>[],
    'Dance': <Song>[],
    'Pop': <Song>[],
    'Hip-Hop': <Song>[],
  };

  bool _loading = false;
  String _error = '';
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<List<Song>> _decodeSongs(String? raw) async {
    if (raw == null) return [];

    try {
      return (jsonDecode(raw) as List)
          .map(
            (item) => Song.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final favorites =
        await _decodeSongs(prefs.getString('favorites'));

    final Map<String, List<Song>> playlists = {};

    try {
      final raw = prefs.getString('playlists');

      if (raw != null) {
        final decoded =
            Map<String, dynamic>.from(jsonDecode(raw) as Map);

        for (final entry in decoded.entries) {
          playlists[entry.key] = (entry.value as List)
              .map(
                (item) => Song.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList();
        }
      }
    } catch (_) {}

    for (final name in ['Rock', 'Dance', 'Pop', 'Hip-Hop']) {
      playlists.putIfAbsent(name, () => <Song>[]);
    }

    if (!mounted) return;

    setState(() {
      _favorites = favorites;
      _playlists = playlists;
    });

    await _saveSaved();
  }

  Future<void> _saveSaved() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'favorites',
      jsonEncode(_favorites.map((s) => s.toJson()).toList()),
    );

    await prefs.setString(
      'playlists',
      jsonEncode(
        _playlists.map(
          (name, songs) => MapEntry(
            name,
            songs.map((s) => s.toJson()).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _searchSongs() async {
    final query = _search.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final videos = await _youtube.search.search(query);
      final songs = videos.take(30).map(Song.fromVideo).toList();

      if (mounted) setState(() => _results = songs);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Gabim gjatë kërkimit. Kontrollo internetin.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playSong(
    Song song, {
    List<Song>? queueSongs,
  }) async {
    final list = List<Song>.from(queueSongs ?? [song]);
    final index = list.indexWhere((s) => s.id == song.id);

    _activeQueue = list;
    _activeIndex = index < 0 ? 0 : index;

    try {
      if (song.isMp3) {
        _videoController?.pause();

        final mp3Queue = list.where((s) => s.isMp3).toList();
        final mp3Index =
            mp3Queue.indexWhere((s) => s.id == song.id);

        await audioHandler.playQueue(
          mp3Queue,
          startIndex: mp3Index < 0 ? 0 : mp3Index,
        );
      } else {
        await audioHandler.stop();

        final old = _videoController;

        _videoController = YoutubePlayerController(
          initialVideoId: song.id,
          flags: const YoutubePlayerFlags(
            autoPlay: true,
            mute: false,
            enableCaption: false,
          ),
        );

        old?.dispose();
      }

      if (!mounted) return;

      setState(() {
        _currentSong = song;
        _error = '';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Nuk u luajt audio. Kontrollo URL-në dhe lidhjen.';
        });
      }
    }
  }

  Future<void> _nextSong() async {
    if (_currentSong?.isMp3 == true) {
      await audioHandler.skipToNext();
      return;
    }

    if (_activeQueue.length < 2) return;

    _activeIndex = (_activeIndex + 1) % _activeQueue.length;

    await _playSong(
      _activeQueue[_activeIndex],
      queueSongs: _activeQueue,
    );
  }

  Future<void> _previousSong() async {
    if (_currentSong?.isMp3 == true) {
      await audioHandler.skipToPrevious();
      return;
    }

    if (_activeQueue.length < 2) return;

    _activeIndex =
        (_activeIndex - 1 + _activeQueue.length) %
            _activeQueue.length;

    await _playSong(
      _activeQueue[_activeIndex],
      queueSongs: _activeQueue,
    );
  }

  bool _isFavorite(Song song) =>
      _favorites.any((s) => s.id == song.id);

  Future<void> _toggleFavorite(Song song) async {
    setState(() {
      if (_isFavorite(song)) {
        _favorites.removeWhere((s) => s.id == song.id);
      } else {
        _favorites.add(song);
      }
    });

    await _saveSaved();
  }

  Future<void> _addToPlaylist(Song song) async {
    final nameController = TextEditingController();

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ruaj në playlist'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ..._playlists.keys.map(
                (name) => ListTile(
                  title: Text(name),
                  leading: const Icon(Icons.queue_music),
                  onTap: () => Navigator.pop(ctx, name),
                ),
              ),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Emër playlist-e të re',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anulo'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx, 'NEW:$name');
              }
            },
            child: const Text('Krijo'),
          ),
        ],
      ),
    );

    nameController.dispose();

    if (choice == null || !mounted) return;

    setState(() {
      final name =
          choice.startsWith('NEW:') ? choice.substring(4) : choice;

      _playlists.putIfAbsent(name, () => <Song>[]);

      if (!_playlists[name]!.any((s) => s.id == song.id)) {
        _playlists[name]!.add(song);
      }
    });

    await _saveSaved();
  }

  Future<void> _addMp3Url() async {
    final urlController = TextEditingController();
    final titleController = TextEditingController();
    final artistController = TextEditingController();

    final song = await showDialog<Song>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Shto audio MP3'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Titulli',
                ),
              ),
              TextField(
                controller: artistController,
                decoration: const InputDecoration(
                  labelText: 'Artisti',
                ),
              ),
              TextField(
                controller: urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL HTTPS e audios së autorizuar',
                  hintText: 'https://example.com/song.mp3',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anulo'),
          ),
          FilledButton(
            onPressed: () {
              final uri = Uri.tryParse(urlController.text.trim());

              if (uri == null ||
                  uri.scheme != 'https' ||
                  uri.host.isEmpty) {
                return;
              }

              Navigator.pop(
                ctx,
                Song(
                  id: uri.toString(),
                  title: titleController.text.trim().isEmpty
                      ? 'Audio MP3'
                      : titleController.text.trim(),
                  artist: artistController.text.trim().isEmpty
                      ? 'Audio'
                      : artistController.text.trim(),
                  isMp3: true,
                ),
              );
            },
            child: const Text('Shto'),
          ),
        ],
      ),
    );

    urlController.dispose();
    titleController.dispose();
    artistController.dispose();

    if (song == null || !mounted) return;

    setState(() {
      if (!_results.any((s) => s.id == song.id)) {
        _results.insert(0, song);
      }
    });

    await _addToPlaylist(song);
  }

  Future<void> _removeFromPlaylist(
    String playlist,
    Song song,
  ) async {
    setState(() {
      _playlists[playlist]?.removeWhere((s) => s.id == song.id);
    });

    await _saveSaved();
  }

  Widget _songTile(
    Song song, {
    String? playlistName,
    List<Song>? queueSongs,
  }) {
    final favorite = _isFavorite(song);

    return ListTile(
      leading: Icon(
        song.isMp3 ? Icons.audiotrack : Icons.music_note,
        color: const Color(0xFF16D9F5),
      ),
      title: Text(
        song.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(song.artist),
      trailing: Wrap(
        spacing: 0,
        children: [
          IconButton(
            tooltip: 'Të preferuarat',
            icon: Icon(
              favorite ? Icons.favorite : Icons.favorite_border,
              color: favorite ? Colors.pinkAccent : null,
            ),
            onPressed: () => _toggleFavorite(song),
          ),
          if (playlistName == null)
            IconButton(
              icon: const Icon(Icons.playlist_add),
              onPressed: () => _addToPlaylist(song),
            )
          else
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  _removeFromPlaylist(playlistName, song),
            ),
          IconButton(
            icon: const Icon(Icons.play_circle_fill, size: 32),
            onPressed: () => _playSong(
              song,
              queueSongs: queueSongs ?? [song],
            ),
          ),
        ],
      ),
      onTap: () => _playSong(
        song,
        queueSongs: queueSongs ?? [song],
      ),
    );
  }

  Widget _searchPage() => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchSongs(),
              decoration: InputDecoration(
                hintText: 'Kërko këngë në YouTube...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _searchSongs,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _addMp3Url,
                  icon: const Icon(Icons.add_link),
                  label: const Text('Shto MP3'),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (ctx, i) => _songTile(
                _results[i],
                queueSongs: _results,
              ),
            ),
          ),
        ],
      );

  Widget _favoritesPage() => _favorites.isEmpty
      ? const Center(
          child: Text('Nuk ke këngë të preferuara.'),
        )
      : ListView(
          children: _favorites
              .map(
                (s) => _songTile(
                  s,
                  queueSongs: _favorites,
                ),
              )
              .toList(),
        );

  Widget _playlistsPage() => ListView(
        children: _playlists.entries.map((entry) {
          return ExpansionTile(
            leading: const Icon(Icons.queue_music),
            title: Text(entry.key),
            subtitle: Text('${entry.value.length} këngë'),
            children: entry.value.isEmpty
                ? [
                    const ListTile(
                      title: Text(
                        'Playlist bosh — shto këngë nga Kërko',
                      ),
                    ),
                  ]
                : entry.value
                    .map(
                      (s) => _songTile(
                        s,
                        playlistName: entry.key,
                        queueSongs: entry.value,
                      ),
                    )
                    .toList(),
          );
        }).toList(),
      );

  String _time(Duration d) {
    final minutes =
        d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds =
        d.inSeconds.remainder(60).toString().padLeft(2, '0');

    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$minutes:$seconds';
  }

  Widget _audioControls() => Container(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        color: const Color(0xFF15182D),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<Duration?>(
              stream: audioHandler.player.durationStream,
              builder: (context, durationSnap) {
                final duration = durationSnap.data ?? Duration.zero;

                return StreamBuilder<Duration>(
                  stream: audioHandler.player.positionStream,
                  builder: (context, positionSnap) {
                    final position =
                        positionSnap.data ?? Duration.zero;
                    final maxMs = max(1, duration.inMilliseconds);
                    final value = position.inMilliseconds
                        .clamp(0, maxMs)
                        .toDouble();

                    return Column(
                      children: [
                        Slider(
                          min: 0,
                          max: maxMs.toDouble(),
                          value: value,
                          onChanged: (v) => audioHandler.seek(
                            Duration(milliseconds: v.round()),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _time(position),
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                _time(duration),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: 'Shuffle',
                  color: audioHandler.shuffleEnabled
                      ? const Color(0xFF16D9F5)
                      : null,
                  onPressed: () async {
                    await audioHandler.toggleShuffle();
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.shuffle),
                ),
                IconButton(
                  tooltip: 'Previous',
                  onPressed: _previousSong,
                  icon: const Icon(Icons.skip_previous, size: 32),
                ),
                StreamBuilder<PlayerState>(
                  stream: audioHandler.player.playerStateStream,
                  builder: (context, snapshot) {
                    final playing =
                        snapshot.data?.playing ?? false;

                    return IconButton(
                      iconSize: 46,
                      onPressed: () => playing
                          ? audioHandler.pause()
                          : audioHandler.play(),
                      icon: Icon(
                        playing
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Next',
                  onPressed: _nextSong,
                  icon: const Icon(Icons.skip_next, size: 32),
                ),
                IconButton(
                  tooltip: 'Repeat',
                  color: audioHandler.repeatEnabled
                      ? const Color(0xFF16D9F5)
                      : null,
                  onPressed: () async {
                    await audioHandler.toggleRepeat();
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.repeat),
                ),
                PopupMenuButton<double>(
                  tooltip: 'Shpejtësia',
                  onSelected: audioHandler.changeSpeed,
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 0.75,
                      child: Text('0.75×'),
                    ),
                    PopupMenuItem(
                      value: 1.0,
                      child: Text('1× Normal'),
                    ),
                    PopupMenuItem(
                      value: 1.25,
                      child: Text('1.25×'),
                    ),
                    PopupMenuItem(
                      value: 1.5,
                      child: Text('1.5×'),
                    ),
                    PopupMenuItem(
                      value: 2.0,
                      child: Text('2×'),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('1×'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  @override
  void dispose() {
    _search.dispose();
    _videoController?.dispose();
    _youtube.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _searchPage(),
      _favoritesPage(),
      _playlistsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.graphic_eq, color: Color(0xFF16D9F5)),
            SizedBox(width: 8),
            Text(
              'ERIBeat',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          if (_currentSong?.isMp3 == true)
            IconButton(
              tooltip: 'Ndalo audio',
              onPressed: audioHandler.stop,
              icon: const Icon(Icons.stop),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: pages[_tab]),
          if (_currentSong != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: const Color(0xFF15182D),
              child: Text(
                '${_currentSong!.title} • ${_currentSong!.artist}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            if (!_currentSong!.isMp3 &&
                _videoController != null) ...[
              YoutubePlayer(
                controller: _videoController!,
                showVideoProgressIndicator: true,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _previousSong,
                    icon: const Icon(Icons.skip_previous),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Kontrollet e videos në YouTube'),
                  ),
                  IconButton(
                    onPressed: _nextSong,
                    icon: const Icon(Icons.skip_next),
                  ),
                ],
              ),
            ],
            if (_currentSong!.isMp3) _audioControls(),
          ],
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) {
          setState(() => _tab = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search),
            label: 'Kërko',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            label: 'Të preferuarat',
          ),
          NavigationDestination(
            icon: Icon(Icons.queue_music),
            label: 'Playlist',
          ),
        ],
      ),
    );
  }
}
