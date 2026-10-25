import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    as yt;
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
        title: json['title'] as String,
        artist: json['artist'] as String? ?? 'Unknown artist',
        isMp3: json['isMp3'] as bool? ?? false,
      );

  factory Song.fromVideo(yt.Video video) => Song(
        id: video.id.value,
        title: video.title,
        artist: video.author,
      );
}

// Dedicated background audio handler for authorized MP3 URLs.
class ERIAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer player = AudioPlayer();

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
          queueIndex: event.currentIndex,
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

  Future<void> playSong(Song song) async {
    if (!song.isMp3) return;

    final uri = Uri.tryParse(song.id);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty) {
      throw ArgumentError('Use a valid HTTPS MP3 URL.');
    }

    final item = MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
    );

    mediaItem.add(item);
    queue.add([item]);

    await player.setUrl(song.id);
    await player.play();
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) =>
      player.seek(position);

  @override
  Future<void> stop() async {
    await player.stop();
    mediaItem.add(null);
    queue.add([]);
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
        updatePosition: Duration.zero,
      ),
    );
  }

  @override
  Future<void> skipToNext() async {
    // Queue navigation can be added when multiple MP3 tracks
    // are loaded into the audio handler.
  }

  @override
  Future<void> skipToPrevious() async {
    // Queue navigation can be added when multiple MP3 tracks
    // are loaded into the audio handler.
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
        scaffoldBackgroundColor: const Color(0xFF0D120D),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9DD69A),
          brightness: Brightness.dark,
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
  Map<String, List<Song>> _playlists = {
    'Playlist 1': <Song>[],
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
          .map((item) => Song.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
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
              .map((item) => Song.fromJson(
                    Map<String, dynamic>.from(item as Map),
                  ))
              .toList();
        }
      }
    } catch (_) {}

    if (playlists.isEmpty) {
      playlists['Playlist 1'] = [];
    }

    if (!mounted) return;
    setState(() {
      _favorites = favorites;
      _playlists = playlists;
    });
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
      final songs = videos.take(25).map(Song.fromVideo).toList();

      if (!mounted) return;
      setState(() => _results = songs);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Gabim gjatë kërkimit. Kontrollo internetin.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playSong(Song song) async {
    try {
      if (song.isMp3) {
        // Stop the video before starting background audio.
        _videoController?.pause();
        await audioHandler.playSong(song);

        if (!mounted) return;
        setState(() {
          _currentSong = song;
          _error = '';
        });
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

        if (!mounted) return;
        setState(() {
          _currentSong = song;
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Nuk u luajt. Kontrollo URL-në ose provo një këngë tjetër.';
        });
      }
    }
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
        content: Column(
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
                labelText: 'Emër i playlistës së re',
              ),
            ),
          ],
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
      final name = choice.startsWith('NEW:')
          ? choice.substring(4)
          : choice;

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
                decoration: const InputDecoration(labelText: 'Titulli'),
              ),
              TextField(
                controller: artistController,
                decoration: const InputDecoration(labelText: 'Artisti'),
              ),
              TextField(
                controller: urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL HTTPS e MP3 të autorizuar',
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

  Widget _songTile(Song song, {String? playlistName}) {
    final favorite = _isFavorite(song);

    return ListTile(
      leading: Icon(
        song.isMp3 ? Icons.audiotrack : Icons.music_note,
        color: const Color(0xFF66E6B0),
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
              onPressed: () => _removeFromPlaylist(playlistName, song),
            ),
          IconButton(
            icon: const Icon(Icons.play_circle_fill, size: 32),
            onPressed: () => _playSong(song),
          ),
        ],
      ),
      onTap: () => _playSong(song),
    );
  }

  Widget _searchPage() {
    return Column(
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
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: _addMp3Url,
              icon: const Icon(Icons.add_link),
              label: const Text('Shto MP3'),
            ),
          ],
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
            itemBuilder: (ctx, i) => _songTile(_results[i]),
          ),
        ),
      ],
    );
  }

  Widget _favoritesPage() => _favorites.isEmpty
      ? const Center(child: Text('Nuk ke këngë të preferuara.'))
      : ListView(
          children: _favorites.map((s) => _songTile(s)).toList(),
        );

  Widget _playlistsPage() => ListView(
        children: _playlists.entries.map((entry) {
          return ExpansionTile(
            leading: const Icon(Icons.queue_music),
            title: Text(entry.key),
            subtitle: Text('${entry.value.length} këngë'),
            children: entry.value.isEmpty
                ? [const ListTile(title: Text('Playlist bosh'))]
                : entry.value
                    .map((s) => _songTile(s, playlistName: entry.key))
                    .toList(),
          );
        }).toList(),
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
        title: const Text(
          '♫ ERIBeat',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: pages[_tab]),
          if (_currentSong != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: const Color(0xFF1C241C),
              child: Text(
                '${_currentSong!.title} • ${_currentSong!.artist}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            if (!_currentSong!.isMp3 && _videoController != null)
              YoutubePlayer(
                controller: _videoController!,
                showVideoProgressIndicator: true,
              ),
            if (_currentSong!.isMp3)
              Container(
                color: const Color(0xFF1C241C),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.stop),
                      onPressed: audioHandler.stop,
                    ),
                    StreamBuilder<PlaybackState>(
                      stream: audioHandler.playbackState,
                      builder: (context, snapshot) {
                        final playing =
                            snapshot.data?.playing ?? false;
                        return IconButton(
                          iconSize: 42,
                          icon: Icon(
                            playing
                                ? Icons.pause_circle
                                : Icons.play_circle,
                          ),
                          onPressed: playing
                              ? audioHandler.pause
                              : audioHandler.play,
                        );
                      },
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
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
