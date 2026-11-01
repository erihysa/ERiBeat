import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:youtube_player_flutter/youtube_player_flutter.dart'
    hide PlayerState;

late ERIAudioHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  audioHandler = await AudioService.init(
    builder: ERIAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.eribeat.audio',
      androidNotificationChannelName: 'ERIBeat Music',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
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

  List<Song> songs = [];
  int index = 0;
  bool shuffleEnabled = false;
  bool repeatEnabled = false;
  bool changingTrack = false;

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
          processingState: mapState(player.processingState),
          playing: player.playing,
          updatePosition: player.position,
          bufferedPosition: player.bufferedPosition,
          speed: player.speed,
          queueIndex: index,
        ),
      );
    });

    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !changingTrack) {
        if (repeatEnabled) {
          player.seek(Duration.zero);
          player.play();
        } else if (songs.length > 1) {
          skipToNext();
        }
      }
    });
  }

  AudioProcessingState mapState(ProcessingState state) {
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

  MediaItem item(Song song) => MediaItem(
    id: song.id,
    title: song.title,
    artist: song.artist,
    album: 'ERIBeat',
  );

  Future<void> playQueue(List<Song> list, {int startIndex = 0}) async {
    songs = list.where((s) => s.isMp3).toList();
    if (songs.isEmpty) return;

    index = startIndex.clamp(0, songs.length - 1);
    queue.add(songs.map(item).toList());
    await loadCurrent();
  }

  Future<void> loadCurrent() async {
    if (songs.isEmpty) return;

    changingTrack = true;
    try {
      final song = songs[index];
      final uri = Uri.tryParse(song.id);

      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty) {
        throw Exception('URL HTTPS e pavlefshme');
      }

      mediaItem.add(item(song));
      await player.setUrl(song.id);
      await player.play();
    } finally {
      changingTrack = false;
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
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (songs.length < 2) return;

    if (shuffleEnabled) {
      var next = index;
      while (next == index) {
        next = _random.nextInt(songs.length);
      }
      index = next;
    } else {
      index = (index + 1) % songs.length;
    }
    await loadCurrent();
  }

  @override
  Future<void> skipToPrevious() async {
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
      return;
    }

    if (songs.length < 2) {
      await player.seek(Duration.zero);
      return;
    }

    index = (index - 1 + songs.length) % songs.length;
    await loadCurrent();
  }

  @override
  Future<void> stop() async {
    await player.stop();
    mediaItem.add(null);
    queue.add([]);
    songs = [];
    index = 0;
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
  final yt.YoutubeExplode youtube = yt.YoutubeExplode();
  final TextEditingController search = TextEditingController();

  YoutubePlayerController? videoController;
  Song? currentSong;

  List<Song> results = [];
  List<Song> favorites = [];
  List<Song> downloads = [];

  Map<String, List<Song>> playlists = {
    'Rock': [],
    'Dance': [],
    'Pop': [],
    'Hip-Hop': [],
  };

  bool loading = false;
  bool downloading = false;
  String error = '';
  int tab = 0;

  @override
  void initState() {
    super.initState();
    loadSaved();
  }

  Future<List<Song>> decodeSongs(String? raw) async {
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();

    final f = await decodeSongs(prefs.getString('favorites'));
    final d = await decodeSongs(prefs.getString('downloads'));

    try {
      final raw = prefs.getString('playlists');
      if (raw != null) {
        final decoded =
            Map<String, dynamic>.from(jsonDecode(raw));
        for (final entry in decoded.entries) {
          playlists[entry.key] = (entry.value as List)
              .map((e) =>
                  Song.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }
    } catch (_) {}

    for (final name in ['Rock', 'Dance', 'Pop', 'Hip-Hop']) {
      playlists.putIfAbsent(name, () => []);
    }

    if (!mounted) return;
    setState(() {
      favorites = f;
      downloads = d;
    });
  }

  Future<void> saveAll() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'favorites',
      jsonEncode(favorites.map((s) => s.toJson()).toList()),
    );

    await prefs.setString(
      'downloads',
      jsonEncode(downloads.map((s) => s.toJson()).toList()),
    );

    await prefs.setString(
      'playlists',
      jsonEncode(playlists.map(
        (key, value) => MapEntry(
          key,
          value.map((s) => s.toJson()).toList(),
        ),
      )),
    );
  }

  Future<void> searchSongs() async {
    final q = search.text.trim();
    if (q.isEmpty) return;

    setState(() {
      loading = true;
      error = '';
    });

    try {
      final videos = await youtube.search.search(q);
      final found = videos.take(30).map(Song.fromVideo).toList();
      if (mounted) setState(() => results = found);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Gabim gjatë kërkimit në YouTube.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> playSong(Song song, {List<Song>? queueSongs}) async {
    try {
      if (song.isMp3) {
        videoController?.pause();
        final list = (queueSongs ?? [song])
            .where((s) => s.isMp3)
            .toList();
        final i = list.indexWhere((s) => s.id == song.id);
        await audioHandler.playQueue(list, startIndex: i < 0 ? 0 : i);
      } else {
        await audioHandler.stop();
        final old = videoController;
        videoController = YoutubePlayerController(
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
        currentSong = song;
        error = '';
      });
    } catch (e) {
      if (mounted) setState(() => error = 'Gabim gjatë luajtjes: $e');
    }
  }

  Future<void> searchAndPlay(Song song) =>
      playSong(song, queueSongs: results);

  Future<void> toggleFavorite(Song song) async {
    setState(() {
      if (favorites.any((s) => s.id == song.id)) {
        favorites.removeWhere((s) => s.id == song.id);
      } else {
        favorites.add(song);
      }
    });
    await saveAll();
  }

  Future<void> addPlaylist(Song song) async {
    final controller = TextEditingController();
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ruaj në playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...playlists.keys.map((name) => ListTile(
              title: Text(name),
              onTap: () => Navigator.pop(ctx, name),
            )),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Playlist e re',
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
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(ctx, 'NEW:${controller.text.trim()}');
              }
            },
            child: const Text('Krijo'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (choice == null) return;
    final name = choice.startsWith('NEW:')
        ? choice.substring(4)
        : choice;

    setState(() {
      playlists.putIfAbsent(name, () => []);
      if (!playlists[name]!.any((s) => s.id == song.id)) {
        playlists[name]!.add(song);
      }
    });
    await saveAll();
  }

  Future<void> addAuthorizedMp3() async {
    final url = TextEditingController();
    final title = TextEditingController();
    final artist = TextEditingController();

    final song = await showDialog<Song>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Shto MP3 të autorizuar'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Titulli'),
              ),
              TextField(
                controller: artist,
                decoration: const InputDecoration(labelText: 'Artisti'),
              ),
              TextField(
                controller: url,
                decoration: const InputDecoration(
                  labelText: 'URL HTTPS e MP3',
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
              final uri = Uri.tryParse(url.text.trim());
              if (uri == null ||
                  uri.scheme != 'https' ||
                  uri.host.isEmpty) return;

              Navigator.pop(
                ctx,
                Song(
                  id: uri.toString(),
                  title: title.text.trim().isEmpty
                      ? 'Audio MP3'
                      : title.text.trim(),
                  artist: artist.text.trim().isEmpty
                      ? 'Audio'
                      : artist.text.trim(),
                  isMp3: true,
                ),
              );
            },
            child: const Text('Shto'),
          ),
        ],
      ),
    );

    url.dispose();
    title.dispose();
    artist.dispose();

    if (song == null) return;

    setState(() => results.insert(0, song));
    await addPlaylist(song);
  }

  Future<void> downloadAuthorizedMp3(Song song) async {
    if (!song.isMp3) {
      setState(() {
        error =
            'Shkarkimi MP3 kërkon një lidhje direkte të autorizuar.';
      });
      return;
    }

    setState(() {
      downloading = true;
      error = '';
    });

    try {
      final uri = Uri.parse(song.id);
      if (uri.scheme != 'https') {
        throw Exception('Kërkohet HTTPS');
      }

      final client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Shkarkimi dështoi');
      }

      final directory = Directory('/storage/emulated/0/Download/ERIBeat');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final safeName = song.title
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

      final file = File('${directory.path}/$safeName.mp3');
      await response.pipe(file.openWrite());
      client.close();

      final savedSong = Song(
        id: file.path,
        title: song.title,
        artist: song.artist,
        isMp3: true,
      );

      if (!downloads.any((s) => s.id == savedSong.id)) {
        setState(() => downloads.add(savedSong));
      }
      await saveAll();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('MP3 u ruajt në Downloads!')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Gabim shkarkimi: $e');
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  Widget songTile(Song song, {List<Song>? queueSongs}) {
    final fav = favorites.any((s) => s.id == song.id);

    return ListTile(
      leading: const Icon(Icons.headphones, color: Color(0xFF16D9F5)),
      title: Text(song.title, maxLines: 2),
      subtitle: Text(song.artist),
      trailing: Wrap(
        spacing: 0,
        children: [
          IconButton(
            icon: Icon(
              fav ? Icons.favorite : Icons.favorite_border,
              color: fav ? Colors.pink : null,
            ),
            onPressed: () => toggleFavorite(song),
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add),
            onPressed: () => addPlaylist(song),
          ),
          if (song.isMp3)
            IconButton(
              tooltip: 'Download MP3',
              icon: const Icon(Icons.download),
              onPressed: () => downloadAuthorizedMp3(song),
            ),
          IconButton(
            icon: const Icon(Icons.play_circle_fill, size: 32),
            onPressed: () => playSong(
              song,
              queueSongs: queueSongs ?? [song],
            ),
          ),
        ],
      ),
      onTap: () => playSong(
        song,
        queueSongs: queueSongs ?? [song],
      ),
    );
  }

  Widget searchPage() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: search,
            onSubmitted: (_) => searchSongs(),
            decoration: InputDecoration(
              hintText: 'Kërko muzikë në YouTube',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: searchSongs,
              ),
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: addAuthorizedMp3,
              icon: const Icon(Icons.add_link),
              label: const Text('Shto MP3'),
            ),
          ],
        ),
        if (loading) const LinearProgressIndicator(),
        if (downloading) const LinearProgressIndicator(),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(error, style: const TextStyle(color: Colors.orange)),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (_, i) =>
                songTile(results[i], queueSongs: results),
          ),
        ),
      ],
    );
  }

  Widget favoritesPage() => ListView(
    children: favorites.map((s) => songTile(s, queueSongs: favorites)).toList(),
  );

  Widget downloadsPage() => ListView(
    children: downloads.map((s) => songTile(s, queueSongs: downloads)).toList(),
  );

  Widget playlistsPage() => ListView(
    children: playlists.entries.map((entry) => ExpansionTile(
      title: Text(entry.key),
      subtitle: Text('${entry.value.length} këngë'),
      children: entry.value
          .map((s) => songTile(s, queueSongs: entry.value))
          .toList(),
    )).toList(),
  );

  String time(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  Widget audioControls() {
    return Container(
      color: const Color(0xFF15182D),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<Duration?>(
            stream: audioHandler.player.durationStream,
            builder: (_, ds) {
              final duration = ds.data ?? Duration.zero;
              return StreamBuilder<Duration>(
                stream: audioHandler.player.positionStream,
                builder: (_, ps) {
                  final position = ps.data ?? Duration.zero;
                  final maxMs = max(1, duration.inMilliseconds);
                  return Column(
                    children: [
                      Slider(
                        min: 0,
                        max: maxMs.toDouble(),
                        value: position.inMilliseconds
                            .clamp(0, maxMs).toDouble(),
                        onChanged: (v) => audioHandler.seek(
                          Duration(milliseconds: v.round()),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [Text(time(position)), Text(time(duration))],
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
                onPressed: () async {
                  await audioHandler.toggleShuffle();
                  setState(() {});
                },
                color: audioHandler.shuffleEnabled
                    ? const Color(0xFF16D9F5)
                    : null,
                icon: const Icon(Icons.shuffle),
              ),
              IconButton(
                onPressed: audioHandler.skipToPrevious,
                icon: const Icon(Icons.skip_previous, size: 32),
              ),
              StreamBuilder<PlayerState>(
                stream: audioHandler.player.playerStateStream,
                builder: (_, snapshot) {
                  final playing = snapshot.data?.playing ?? false;
                  return IconButton(
                    iconSize: 46,
                    onPressed: () => playing
                        ? audioHandler.pause()
                        : audioHandler.play(),
                    icon: Icon(playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill),
                  );
                },
              ),
              IconButton(
                onPressed: audioHandler.skipToNext,
                icon: const Icon(Icons.skip_next, size: 32),
              ),
              IconButton(
                onPressed: () async {
                  await audioHandler.toggleRepeat();
                  setState(() {});
                },
                color: audioHandler.repeatEnabled
                    ? const Color(0xFF16D9F5)
                    : null,
                icon: const Icon(Icons.repeat),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    search.dispose();
    videoController?.dispose();
    youtube.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      searchPage(),
      favoritesPage(),
      playlistsPage(),
      downloadsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.headphones, color: Color(0xFF16D9F5)),
            SizedBox(width: 8),
            Text('ERIBeat', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          if (currentSong?.isMp3 == true)
            IconButton(
              onPressed: audioHandler.stop,
              icon: const Icon(Icons.stop),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: pages[tab]),
          if (currentSong != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: const Color(0xFF15182D),
              child: Text(
                '${currentSong!.title} • ${currentSong!.artist}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (currentSong!.isMp3)
              audioControls()
            else if (videoController != null)
              YoutubePlayer(
                controller: videoController!,
                showVideoProgressIndicator: true,
              ),
          ],
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search), label: 'Kërko'),
          NavigationDestination(icon: Icon(Icons.favorite), label: 'Të preferuarat'),
          NavigationDestination(icon: Icon(Icons.queue_music), label: 'Playlist'),
          NavigationDestination(icon: Icon(Icons.download), label: 'Downloads'),
        ],
      ),
    );
  }
}
