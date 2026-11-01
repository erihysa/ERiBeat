
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

const Color bg = Color(0xFF101010);
const Color surface = Color(0xFF191919);
const Color card = Color(0xFF252525);
const Color accent = Color(0xFF20D9E8);
const Color muted = Color(0xFFB3B3B3);

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

// ---------------------------------------------------------
// SONG MODEL
// ---------------------------------------------------------

class Song {
  final String id;
  final String title;
  final String artist;
  final bool isMp3;
  final String? image;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.isMp3 = false,
    this.image,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'isMp3': isMp3,
        'image': image,
      };

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Pa titull',
      artist: json['artist'] ?? 'Artist',
      isMp3: json['isMp3'] ?? false,
      image: json['image'],
    );
  }

  factory Song.fromVideo(yt.Video video) {
    return Song(
      id: video.id.value,
      title: video.title,
      artist: video.author,
      image: video.thumbnails.highResUrl,
    );
  }
}

// ---------------------------------------------------------
// AUDIO HANDLER - BACKGROUND MP3 PLAYBACK
// ---------------------------------------------------------

class ERIAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer player = AudioPlayer();
  final Random random = Random();

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
            player.playing ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
            MediaControl.stop,
          ],
          androidCompactActionIndices: const [0, 1, 2],
          processingState: convertState(player.processingState),
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

  AudioProcessingState convertState(ProcessingState state) {
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

  MediaItem mediaItemFor(Song song) {
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: 'ERIBeat',
      artUri: song.image == null ? null : Uri.tryParse(song.image!),
    );
  }

  Future<void> playQueue(List<Song> list, int startIndex) async {
    songs = list.where((song) => song.isMp3).toList();

    if (songs.isEmpty) return;

    index = startIndex.clamp(0, songs.length - 1);
    queue.add(songs.map(mediaItemFor).toList());

    await loadCurrent();
  }

  Future<void> loadCurrent() async {
    if (songs.isEmpty) return;

    changingTrack = true;

    try {
      final song = songs[index];
      mediaItem.add(mediaItemFor(song));

      if (song.id.startsWith('/') && await File(song.id).exists()) {
        await player.setFilePath(song.id);
      } else {
        final uri = Uri.tryParse(song.id);

        if (uri == null || uri.scheme != 'https') {
          throw Exception('Adresa MP3 nuk është e vlefshme.');
        }

        await player.setUrl(song.id);
      }

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

  Future<void> changeSpeed(double value) {
    return player.setSpeed(value);
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) {
    return player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    if (songs.length < 2) return;

    if (shuffleEnabled) {
      index = random.nextInt(songs.length);
    } else {
      index = (index + 1) % songs.length;
    }

    await loadCurrent();
  }

  @override
  Future<void> skipToPrevious() async {
    if (player.position.inSeconds > 3) {
      await player.seek(Duration.zero);
      return;
    }

    if (songs.length < 2) return;

    index = (index - 1 + songs.length) % songs.length;
    await loadCurrent();
  }

  @override
  Future<void> stop() async {
    await player.stop();
    songs = [];
    index = 0;
    mediaItem.add(null);
    queue.add([]);
    await super.stop();
  }
}

// ---------------------------------------------------------
// APPLICATION
// ---------------------------------------------------------

class ERIBeatApp extends StatelessWidget {
  const ERIBeatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ERIBeat',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          surface: surface,
        ),
        useMaterial3: true,
      ),
      home: const MusicHome(),
    );
  }
}

// ---------------------------------------------------------
// HOME SCREEN
// ---------------------------------------------------------

class MusicHome extends StatefulWidget {
  const MusicHome({super.key});

  @override
  State<MusicHome> createState() => _MusicHomeState();
}

class _MusicHomeState extends State<MusicHome>
    with WidgetsBindingObserver {
  final yt.YoutubeExplode youtube = yt.YoutubeExplode();
  final TextEditingController search = TextEditingController();

  int tab = 0;

  bool loading = false;
  bool backgroundEnabled = true;

  String error = '';

  Song? currentSong;
  YoutubePlayerController? videoController;

  List<Song> results = [];
  List<Song> favorites = [];
  List<Song> downloads = [];

  Map<String, List<Song>> playlists = {
    'Rock': [],
    'Dance': [],
    'Pop': [],
    'Hip-Hop': [],
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadSaved();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!backgroundEnabled &&
        state == AppLifecycleState.paused &&
        audioHandler.player.playing) {
      audioHandler.pause();
    }
  }

  // -------------------------------------------------------
  // SAVE AND LOAD
  // -------------------------------------------------------

  Future<List<Song>> decodeSongs(String? raw) async {
    if (raw == null) return [];

    try {
      final data = jsonDecode(raw) as List;

      return data
          .map(
            (item) => Song.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();

    final savedFavorites =
        await decodeSongs(prefs.getString('favorites'));

    final savedDownloads =
        await decodeSongs(prefs.getString('downloads'));

    final savedBackground =
        prefs.getBool('backgroundEnabled') ?? true;

    try {
      final raw = prefs.getString('playlists');

      if (raw != null) {
        final data = Map<String, dynamic>.from(jsonDecode(raw));

        for (final entry in data.entries) {
          playlists[entry.key] = (entry.value as List)
              .map(
                (item) => Song.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList();
        }
      }
    } catch (_) {}

    for (final name in ['Rock', 'Dance', 'Pop', 'Hip-Hop']) {
      playlists.putIfAbsent(name, () => []);
    }

    if (!mounted) return;

    setState(() {
      favorites = savedFavorites;
      downloads = savedDownloads;
      backgroundEnabled = savedBackground;
    });
  }

  Future<void> saveAll() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'favorites',
      jsonEncode(
        favorites.map((song) => song.toJson()).toList(),
      ),
    );

    await prefs.setString(
      'downloads',
      jsonEncode(
        downloads.map((song) => song.toJson()).toList(),
      ),
    );

    await prefs.setString(
      'playlists',
      jsonEncode(
        playlists.map(
          (name, songs) => MapEntry(
            name,
            songs.map((song) => song.toJson()).toList(),
          ),
        ),
      ),
    );

    await prefs.setBool('backgroundEnabled', backgroundEnabled);
  }

  // -------------------------------------------------------
  // YOUTUBE SEARCH
  // -------------------------------------------------------

  Future<void> searchSongs() async {
    final query = search.text.trim();

    if (query.isEmpty) return;

    setState(() {
      loading = true;
      error = '';
      tab = 1;
    });

    try {
      final found = await youtube.search.search(query);

      if (!mounted) return;

      setState(() {
        results = found.take(30).map(Song.fromVideo).toList();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Gabim gjatë kërkimit: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  // -------------------------------------------------------
  // PLAY SONG
  // -------------------------------------------------------

  Future<void> playSong(
    Song song, {
    List<Song>? list,
  }) async {
    try {
      if (song.isMp3) {
        videoController?.pause();

        final queue = (list ?? [song])
            .where((item) => item.isMp3)
            .toList();

        final start = queue.indexWhere(
          (item) => item.id == song.id,
        );

        await audioHandler.playQueue(
          queue,
          start < 0 ? 0 : start,
        );
      } else {
        await audioHandler.stop();

        final oldController = videoController;

        videoController = YoutubePlayerController(
          initialVideoId: song.id,
          flags: const YoutubePlayerFlags(
            autoPlay: true,
            enableCaption: false,
          ),
        );

        oldController?.dispose();
      }

      if (!mounted) return;

      setState(() {
        currentSong = song;
        error = '';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Gabim në luajtje: $e';
        });
      }
    }
  }

  // -------------------------------------------------------
  // FAVORITES
  // -------------------------------------------------------

  Future<void> toggleFavorite(Song song) async {
    setState(() {
      if (favorites.any((item) => item.id == song.id)) {
        favorites.removeWhere((item) => item.id == song.id);
      } else {
        favorites.add(song);
      }
    });

    await saveAll();
  }

  // -------------------------------------------------------
  // PLAYLISTS
  // -------------------------------------------------------

  Future<void> addPlaylist(Song song) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Zgjidh Playlist'),
          children: playlists.keys.map((name) {
            return SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, name);
              },
              child: Text(name),
            );
          }).toList(),
        );
      },
    );

    if (name == null) return;

    setState(() {
      if (!playlists[name]!.any(
        (item) => item.id == song.id,
      )) {
        playlists[name]!.add(song);
      }
    });

    await saveAll();
  }

  void openPlaylist(String name) {
    final songs = playlists[name] ?? [];

    showSongList(
      name,
      songs,
    );
  }

  // -------------------------------------------------------
  // ADD MP3
  // -------------------------------------------------------

  Future<void> addMp3() async {
    final url = TextEditingController();
    final title = TextEditingController();
    final artist = TextEditingController();

    final song = await showDialog<Song>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Shto MP3 të autorizuar'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(
                    labelText: 'Titulli',
                  ),
                ),
                TextField(
                  controller: artist,
                  decoration: const InputDecoration(
                    labelText: 'Artisti',
                  ),
                ),
                TextField(
                  controller: url,
                  decoration: const InputDecoration(
                    labelText: 'URL HTTPS MP3',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Anulo'),
            ),
            FilledButton(
              onPressed: () {
                final uri = Uri.tryParse(url.text.trim());

                if (uri == null ||
                    uri.scheme != 'https' ||
                    uri.host.isEmpty) {
                  return;
                }

                Navigator.pop(
                  context,
                  Song(
                    id: uri.toString(),
                    title: title.text.trim().isEmpty
                        ? 'Audio MP3'
                        : title.text.trim(),
                    artist: artist.text.trim().isEmpty
                        ? 'Artist'
                        : artist.text.trim(),
                    isMp3: true,
                  ),
                );
              },
              child: const Text('Shto'),
            ),
          ],
        );
      },
    );

    url.dispose();
    title.dispose();
    artist.dispose();

    if (song == null) return;

    setState(() {
      results.insert(0, song);
      tab = 1;
    });
  }

  // -------------------------------------------------------
  // DOWNLOAD MP3
  // -------------------------------------------------------

  Future<void> downloadSong(Song song) async {
    if (!song.isMp3 || !song.id.startsWith('https://')) {
      setState(() {
        error = 'Shkarkimi kërkon MP3 HTTPS të autorizuar.';
      });
      return;
    }

    HttpClient? client;

    try {
      final directory =
          Directory('/storage/emulated/0/Download/ERIBeat');

      await directory.create(recursive: true);

      final safeName = song.title.replaceAll(
        RegExp(r'[\\/:*?"<>|]'),
        '_',
      );

      final file = File(
        '${directory.path}/$safeName.mp3',
      );

      client = HttpClient();

      final request = await client.getUrl(
        Uri.parse(song.id),
      );

      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception(
          'Shkarkimi dështoi: ${response.statusCode}',
        );
      }

      await response.pipe(file.openWrite());

      final savedSong = Song(
        id: file.path,
        title: song.title,
        artist: song.artist,
        isMp3: true,
        image: song.image,
      );

      if (!mounted) return;

      setState(() {
        if (!downloads.any(
          (item) => item.id == savedSong.id,
        )) {
          downloads.add(savedSong);
        }

        error = '';
      });

      await saveAll();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kënga u ruajt në Downloads'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Gabim shkarkimi: $e';
        });
      }
    } finally {
      client?.close();
    }
  }

  // -------------------------------------------------------
  // BACKGROUND OPTION
  // -------------------------------------------------------

  Future<void> changeBackground(bool value) async {
    setState(() {
      backgroundEnabled = value;
    });

    await saveAll();

    if (!value && audioHandler.player.playing) {
      await audioHandler.pause();
    }
  }

  // -------------------------------------------------------
  // IMAGE AND COVER
  // -------------------------------------------------------

  Widget cover(
    Song song, {
    double size = 54,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: song.image != null
          ? Image.network(
              song.image!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return fallbackCover(size);
              },
            )
          : fallbackCover(size),
    );
  }

  Widget fallbackCover(double size) {
    return Container(
      width: size,
      height: size,
      color: card,
      child: Icon(
        Icons.music_note,
        color: accent,
        size: size * .55,
      ),
    );
  }

  // -------------------------------------------------------
  // SECTION TITLE
  // -------------------------------------------------------

  Widget sectionTitle(
    String title, {
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (onTap != null)
            TextButton(
              onPressed: onTap,
              child: const Text('Shiko të gjitha'),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------
  // CATEGORY CARDS
  // -------------------------------------------------------

  Widget categoryCard(
    String name,
    Color color,
    IconData icon,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        search.text = name;
        searchSongs();
      },
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            Icon(
              icon,
              size: 30,
              color: Colors.white70,
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------
  // HORIZONTAL SONGS
  // -------------------------------------------------------

  Widget horizontalSongs(List<Song> songs) {
    if (songs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: Text(
          'Kërko këngë për të krijuar bibliotekën tënde.',
          style: TextStyle(color: muted),
        ),
      );
    }

    return SizedBox(
      height: 190,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];

          return GestureDetector(
            onTap: () => playSong(
              song,
              list: songs,
            ),
            child: SizedBox(
              width: 138,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    cover(song, size: 126),
                    const SizedBox(height: 8),
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------
  // HOME PAGE
  // -------------------------------------------------------

  Widget homePage() {
    final recent = <Song>[];

    for (final song in [
      ...favorites,
      ...downloads,
      ...results,
    ]) {
      if (!recent.any((item) => item.id == song.id)) {
        recent.add(song);
      }
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.headphones,
                  color: accent,
                  size: 34,
                ),
                const SizedBox(width: 9),
                const Text(
                  'ERIBeat',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    setState(() => tab = 4);
                  },
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 15),
            child: Text(
              'Mirë se erdhe!',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: .95),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 9,
            crossAxisSpacing: 9,
            childAspectRatio: 2.5,
            children: [
              categoryCard(
                'Rock',
                const Color(0xFF315C68),
                Icons.album,
              ),
              categoryCard(
                'Dance',
                const Color(0xFF67456C),
                Icons.graphic_eq,
              ),
              categoryCard(
                'Pop',
                const Color(0xFF9B5949),
                Icons.music_note,
              ),
              categoryCard(
                'Hip-Hop',
                const Color(0xFF52664C),
                Icons.mic,
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: sectionTitle('Të dëgjuara së fundmi'),
        ),
        SliverToBoxAdapter(
          child: horizontalSongs(recent),
        ),
        SliverToBoxAdapter(
          child: sectionTitle(
            'Të preferuarat',
            onTap: () => setState(() => tab = 2),
          ),
        ),
        SliverToBoxAdapter(
          child: horizontalSongs(favorites),
        ),
        SliverToBoxAdapter(
          child: sectionTitle('Playlist-et e tua'),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 105,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: playlists.entries.map((entry) {
                return GestureDetector(
                  onTap: () => openPlaylist(entry.key),
                  child: Container(
                    width: 145,
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.queue_music,
                          color: accent,
                        ),
                        const Spacer(),
                        Text(
                          entry.key,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${entry.value.length} këngë',
                          style: const TextStyle(
                            color: muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: 25),
        ),
      ],
    );
  }

  // -------------------------------------------------------
  // SONG TILE
  // -------------------------------------------------------

  Widget songTile(
    Song song, {
    List<Song>? list,
  }) {
    final isFavorite = favorites.any(
      (item) => item.id == song.id,
    );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 3,
      ),
      leading: cover(song),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        song.artist,
        style: const TextStyle(color: muted),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'favorite') {
            toggleFavorite(song);
          }

          if (value == 'playlist') {
            addPlaylist(song);
          }

          if (value == 'download') {
            downloadSong(song);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'favorite',
            child: Text(
              isFavorite
                  ? 'Hiq nga Favorites'
                  : 'Shto te Favorites',
            ),
          ),
          const PopupMenuItem(
            value: 'playlist',
            child: Text('Shto në Playlist'),
          ),
          if (song.isMp3)
            const PopupMenuItem(
              value: 'download',
              child: Text('Shkarko MP3'),
            ),
        ],
      ),
      onTap: () => playSong(
        song,
        list: list ?? [song],
      ),
    );
  }

  // -------------------------------------------------------
  // SEARCH PAGE
  // -------------------------------------------------------

  Widget searchPage() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: search,
            onSubmitted: (_) => searchSongs(),
            decoration: InputDecoration(
              hintText: 'Çfarë dëshiron të dëgjosh?',
              filled: true,
              fillColor: card,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: searchSongs,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: OutlinedButton.icon(
            onPressed: addMp3,
            icon: const Icon(Icons.add_link),
            label: const Text('Shto MP3 të autorizuar'),
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              error,
              style: const TextStyle(color: Colors.orange),
            ),
          ),
        Expanded(
          child: results.isEmpty
              ? const Center(
                  child: Text(
                    'Kërko këngë ose artistë në YouTube',
                    style: TextStyle(color: muted),
                  ),
                )
              : ListView(
                  children: results.map((song) {
                    return songTile(
                      song,
                      list: results,
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  // -------------------------------------------------------
  // LIBRARY PAGE
  // -------------------------------------------------------

  Widget libraryPage() {
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 24, 18, 12),
          child: Text(
            'Biblioteka jote',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(
            Icons.favorite,
            color: accent,
          ),
          title: const Text('Të preferuarat'),
          subtitle: Text('${favorites.length} këngë'),
          onTap: () {
            showSongList(
              'Të preferuarat',
              favorites,
            );
          },
        ),
        const Divider(color: card),
        ...playlists.entries.map((entry) {
          return ListTile(
            leading: const Icon(
              Icons.queue_music,
              color: accent,
            ),
            title: Text(entry.key),
            subtitle: Text('${entry.value.length} këngë'),
            onTap: () => openPlaylist(entry.key),
          );
        }),
      ],
    );
  }

  // -------------------------------------------------------
  // OPEN SONG LIST
  // -------------------------------------------------------

  void showSongList(
    String title,
    List<Song> songs,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return SongListPage(
            title: title,
            songs: songs,
            play: (song) {
              playSong(
                song,
                list: songs,
              );
            },
          );
        },
      ),
    );
  }

  // -------------------------------------------------------
  // DOWNLOADS PAGE
  // -------------------------------------------------------

  Widget downloadsPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(18),
          child: Text(
            'Downloads',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: downloads.isEmpty
              ? const Center(
                  child: Text(
                    'Nuk ke ende këngë të shkarkuara',
                    style: TextStyle(color: muted),
                  ),
                )
              : ListView(
                  children: downloads.map((song) {
                    return songTile(
                      song,
                      list: downloads,
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  // -------------------------------------------------------
  // SETTINGS PAGE
  // -------------------------------------------------------

  Widget settingsPage() {
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 24, 18, 12),
          child: Text(
            'Cilësimet',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(
            Icons.headphones,
            color: accent,
          ),
          title: const Text('Luajtja në sfond'),
          subtitle: const Text(
            'Lejo MP3 të vazhdojë kur ekrani fiket.',
          ),
          value: backgroundEnabled,
          onChanged: changeBackground,
        ),
        const Divider(color: card),
        ListTile(
          leading: const Icon(
            Icons.info_outline,
            color: accent,
          ),
          title: const Text('Rreth ERIBeat'),
          subtitle: const Text('ERIBeat Music Player'),
          onTap: () {
            showAboutDialog(
              context: context,
              applicationName: 'ERIBeat',
              applicationVersion: '1.0.0',
              applicationLegalese: 'ERIBeat Music',
            );
          },
        ),
      ],
    );
  }

  // -------------------------------------------------------
  // PLAYER TIME
  // -------------------------------------------------------

  String formatTime(Duration duration) {
    final minutes = duration.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    final seconds = duration.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$seconds';
    }

    return '$minutes:$seconds';
  }

  // -------------------------------------------------------
  // FULL PLAYER
  // -------------------------------------------------------

  void openPlayer() {
    if (currentSong == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      builder: (context) {
        return PlayerSheet(
          song: currentSong!,
          cover: cover,
          time: formatTime,
        );
      },
    );
  }

  // -------------------------------------------------------
  // MINI PLAYER
  // -------------------------------------------------------

  Widget miniPlayer() {
    if (currentSong == null) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: openPlayer,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 5),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF24434A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            cover(
              currentSong!,
              size: 44,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentSong!.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    currentSong!.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (currentSong!.isMp3)
              StreamBuilder<PlayerState>(
                stream: audioHandler.player.playerStateStream,
                builder: (context, snapshot) {
                  final playing =
                      snapshot.data?.playing ?? false;

                  return IconButton(
                    onPressed: () {
                      if (playing) {
                        audioHandler.pause();
                      } else {
                        audioHandler.play();
                      }
                    },
                    icon: Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                    ),
                  );
                },
              ),
            IconButton(
              onPressed: () {
                toggleFavorite(currentSong!);
              },
              icon: Icon(
                favorites.any(
                  (song) => song.id == currentSong!.id,
                )
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------
  // DISPOSE
  // -------------------------------------------------------

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    search.dispose();
    videoController?.dispose();
    youtube.close();
    super.dispose();
  }

  // -------------------------------------------------------
  // MAIN BUILD
  // -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pages = [
      homePage(),
      searchPage(),
      libraryPage(),
      downloadsPage(),
      settingsPage(),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: tab,
                children: pages,
              ),
            ),

            if (currentSong != null) miniPlayer(),

            if (currentSong != null &&
                !currentSong!.isMp3 &&
                videoController != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: YoutubePlayer(
                  controller: videoController!,
                  showVideoProgressIndicator: true,
                ),
              ),

            NavigationBar(
              backgroundColor: const Color(0xFF171717),
              indicatorColor: const Color(0xFF31545D),
              selectedIndex: tab,
              onDestinationSelected: (index) {
                setState(() => tab = index);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search),
                  label: 'Search',
                ),
                NavigationDestination(
                  icon: Icon(Icons.favorite_border),
                  selectedIcon: Icon(Icons.favorite),
                  label: 'Library',
                ),
                NavigationDestination(
                  icon: Icon(Icons.download_outlined),
                  label: 'Downloads',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: 'Settings',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// SONG LIST PAGE
// ---------------------------------------------------------

class SongListPage extends StatelessWidget {
  final String title;
  final List<Song> songs;
  final ValueChanged<Song> play;

  const SongListPage({
    super.key,
    required this.title,
    required this.songs,
    required this.play,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: bg,
      ),
      body: songs.isEmpty
          ? const Center(
              child: Text(
                'Kjo listë është bosh.',
                style: TextStyle(color: muted),
              ),
            )
          : ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];

                return ListTile(
                  leading: const Icon(
                    Icons.music_note,
                    color: accent,
                  ),
                  title: Text(song.title),
                  subtitle: Text(song.artist),
                  onTap: () => play(song),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------
// FULL PLAYER SHEET
// ---------------------------------------------------------

class PlayerSheet extends StatelessWidget {
  final Song song;
  final Widget Function(
    Song, {
    double size,
  }) cover;

  final String Function(Duration) time;

  const PlayerSheet({
    super.key,
    required this.song,
    required this.cover,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 32,
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'ERIBeat PLAYER',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: muted,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 45),
                ],
              ),

              const SizedBox(height: 22),

              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: song.image != null
                    ? Image.network(
                        song.image!,
                        width: 300,
                        height: 300,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) {
                          return cover(song, size: 300);
                        },
                      )
                    : cover(song, size: 300),
              ),

              const SizedBox(height: 26),

              Text(
                song.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                song.artist,
                style: const TextStyle(color: muted),
              ),

              const SizedBox(height: 25),

              if (song.isMp3) ...[
                StreamBuilder<Duration?>(
                  stream: audioHandler.player.durationStream,
                  builder: (context, durationSnapshot) {
                    final duration =
                        durationSnapshot.data ?? Duration.zero;

                    return StreamBuilder<Duration>(
                      stream: audioHandler.player.positionStream,
                      builder: (context, positionSnapshot) {
                        final position =
                            positionSnapshot.data ?? Duration.zero;

                        final maxMs = max(
                          1,
                          duration.inMilliseconds,
                        );

                        final value = position.inMilliseconds
                            .clamp(0, maxMs)
                            .toDouble();

                        return Column(
                          children: [
                            Slider(
                              min: 0,
                              max: maxMs.toDouble(),
                              value: value,
                              onChanged: (newValue) {
                                audioHandler.seek(
                                  Duration(
                                    milliseconds: newValue.round(),
                                  ),
                                );
                              },
                            ),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(time(position)),
                                Text(time(duration)),
                              ],
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),

                const SizedBox(height: 12),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      onPressed: audioHandler.toggleShuffle,
                      icon: Icon(
                        Icons.shuffle,
                        color: audioHandler.shuffleEnabled
                            ? accent
                            : muted,
                      ),
                    ),

                    IconButton(
                      onPressed: audioHandler.skipToPrevious,
                      icon: const Icon(
                        Icons.skip_previous,
                        size: 38,
                      ),
                    ),

                    StreamBuilder<PlayerState>(
                      stream: audioHandler.player.playerStateStream,
                      builder: (context, snapshot) {
                        final playing =
                            snapshot.data?.playing ?? false;

                        return IconButton(
                          iconSize: 66,
                          onPressed: () {
                            if (playing) {
                              audioHandler.pause();
                            } else {
                              audioHandler.play();
                            }
                          },
                          icon: Icon(
                            playing
                                ? Icons.pause_circle
                                : Icons.play_circle,
                            color: accent,
                          ),
                        );
                      },
                    ),

                    IconButton(
                      onPressed: audioHandler.skipToNext,
                      icon: const Icon(
                        Icons.skip_next,
                        size: 38,
                      ),
                    ),

                    IconButton(
                      onPressed: audioHandler.toggleRepeat,
                      icon: Icon(
                        Icons.repeat,
                        color: audioHandler.repeatEnabled
                            ? accent
                            : muted,
                      ),
                    ),
                  ],
                ),

                Align(
                  alignment: Alignment.centerRight,
                  child: PopupMenuButton<double>(
                    onSelected: audioHandler.changeSpeed,
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 0.75,
                        child: Text('0.75x'),
                      ),
                      PopupMenuItem(
                        value: 1.0,
                        child: Text('1.0x'),
                      ),
                      PopupMenuItem(
                        value: 1.25,
                        child: Text('1.25x'),
                      ),
                      PopupMenuItem(
                        value: 1.5,
                        child: Text('1.5x'),
                      ),
                      PopupMenuItem(
                        value: 2.0,
                        child: Text('2.0x'),
                      ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.speed),
                    ),
                  ),
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Video YouTube luhet në player-in e videos.',
                    style: TextStyle(color: muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
