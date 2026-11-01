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

const bg = Color(0xFF101419);
const panel = Color(0xFF202A30);
const accent = Color(0xFF20C8DC);
const muted = Color(0xFF9BAAB0);

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

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        id: j['id'] ?? '',
        title: j['title'] ?? 'Pa titull',
        artist: j['artist'] ?? 'Artist',
        isMp3: j['isMp3'] ?? false,
        image: j['image'],
      );

  factory Song.fromVideo(yt.Video v) => Song(
        id: v.id.value,
        title: v.title,
        artist: v.author,
        image: v.thumbnails.highResUrl,
      );
}

class ERIAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer player = AudioPlayer();
  final Random random = Random();

  List<Song> songs = [];
  int index = 0;
  bool shuffle = false;
  bool repeat = false;
  bool changing = false;

  ERIAudioHandler() {
    player.playbackEventStream.listen((event) {
      playbackState.add(PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _state(player.processingState),
        playing: player.playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: index,
      ));
    });

    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !changing) {
        if (repeat) {
          player.seek(Duration.zero);
          player.play();
        } else if (songs.length > 1) {
          skipToNext();
        }
      }
    });
  }

  AudioProcessingState _state(ProcessingState s) {
    switch (s) {
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

  MediaItem _item(Song s) => MediaItem(
        id: s.id,
        title: s.title,
        artist: s.artist,
        album: 'ERIBeat',
      );

  Future<void> playQueue(List<Song> list, int start) async {
    songs = list.where((s) => s.isMp3).toList();
    if (songs.isEmpty) return;
    index = start.clamp(0, songs.length - 1);
    queue.add(songs.map(_item).toList());
    await load();
  }

  Future<void> load() async {
    if (songs.isEmpty) return;
    changing = true;
    try {
      final s = songs[index];
      mediaItem.add(_item(s));
      if (s.id.startsWith('/') && await File(s.id).exists()) {
        await player.setFilePath(s.id);
      } else {
        final uri = Uri.tryParse(s.id);
        if (uri == null || uri.scheme != 'https') {
          throw Exception('Adresa MP3 nuk është e vlefshme');
        }
        await player.setUrl(s.id);
      }
      await player.play();
    } finally {
      changing = false;
    }
  }

  Future<void> toggleShuffle() async {
    shuffle = !shuffle;
  }

  Future<void> toggleRepeat() async {
    repeat = !repeat;
  }

  Future<void> speed(double v) => player.setSpeed(v);

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration p) => player.seek(p);

  @override
  Future<void> skipToNext() async {
    if (songs.length < 2) return;
    index = shuffle
        ? random.nextInt(songs.length)
        : (index + 1) % songs.length;
    await load();
  }

  @override
  Future<void> skipToPrevious() async {
    if (player.position.inSeconds > 3) {
      await player.seek(Duration.zero);
      return;
    }
    if (songs.length < 2) return;
    index = (index - 1 + songs.length) % songs.length;
    await load();
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
          surface: panel,
        ),
        useMaterial3: true,
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
  final search = TextEditingController();

  int tab = 0;
  bool loading = false;
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
    loadSaved();
  }

  Future<List<Song>> decode(String? raw) async {
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
    final p = await SharedPreferences.getInstance();
    final f = await decode(p.getString('favorites'));
    final d = await decode(p.getString('downloads'));

    try {
      final raw = p.getString('playlists');
      if (raw != null) {
        final data = Map<String, dynamic>.from(jsonDecode(raw));
        for (final e in data.entries) {
          playlists[e.key] = (e.value as List)
              .map((x) => Song.fromJson(Map<String, dynamic>.from(x)))
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
    final p = await SharedPreferences.getInstance();
    await p.setString('favorites',
        jsonEncode(favorites.map((s) => s.toJson()).toList()));
    await p.setString('downloads',
        jsonEncode(downloads.map((s) => s.toJson()).toList()));
    await p.setString(
      'playlists',
      jsonEncode(playlists.map((k, v) =>
          MapEntry(k, v.map((s) => s.toJson()).toList())),
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
      final found = await youtube.search.search(q);
      if (!mounted) return;
      setState(() => results = found.take(30).map(Song.fromVideo).toList());
    } catch (e) {
      if (mounted) setState(() => error = 'Gabim kërkimi: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> playSong(Song song, {List<Song>? list}) async {
    try {
      if (song.isMp3) {
        videoController?.pause();
        final q = (list ?? [song]).where((s) => s.isMp3).toList();
        final i = q.indexWhere((s) => s.id == song.id);
        await audioHandler.playQueue(q, i < 0 ? 0 : i);
      } else {
        await audioHandler.stop();
        final old = videoController;
        videoController = YoutubePlayerController(
          initialVideoId: song.id,
          flags: const YoutubePlayerFlags(
            autoPlay: true,
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
      if (mounted) setState(() => error = 'Gabim në luajtje: $e');
    }
  }

  Future<void> toggleFavorite(Song s) async {
    setState(() {
      if (favorites.any((x) => x.id == s.id)) {
        favorites.removeWhere((x) => x.id == s.id);
      } else {
        favorites.add(s);
      }
    });
    await saveAll();
  }

  Future<void> addPlaylist(Song s) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Ruaj në playlist'),
        children: playlists.keys.map((k) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, k),
          child: Text(k),
        )).toList(),
      ),
    );
    if (name == null) return;
    setState(() {
      if (!playlists[name]!.any((x) => x.id == s.id)) {
        playlists[name]!.add(s);
      }
    });
    await saveAll();
  }

  Future<void> addMp3() async {
    final url = TextEditingController();
    final title = TextEditingController();
    final artist = TextEditingController();

    final song = await showDialog<Song>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Shto MP3 të autorizuar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Titulli')),
            TextField(controller: artist, decoration: const InputDecoration(labelText: 'Artisti')),
            TextField(controller: url, decoration: const InputDecoration(labelText: 'URL HTTPS MP3')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anulo')),
          FilledButton(
            onPressed: () {
              final u = Uri.tryParse(url.text.trim());
              if (u == null || u.scheme != 'https' || u.host.isEmpty) return;
              Navigator.pop(ctx, Song(
                id: u.toString(),
                title: title.text.trim().isEmpty ? 'Audio MP3' : title.text.trim(),
                artist: artist.text.trim().isEmpty ? 'Artist' : artist.text.trim(),
                isMp3: true,
              ));
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
  }

  Future<void> downloadSong(Song s) async {
    if (!s.isMp3 || !s.id.startsWith('https://')) {
      setState(() => error = 'Shkarkimi kërkon MP3 HTTPS të autorizuar.');
      return;
    }
    try {
      final dir = Directory('/storage/emulated/0/Download/ERIBeat');
      await dir.create(recursive: true);
      final safe = s.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${dir.path}/$safe.mp3');
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(s.id));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('Shkarkimi dështoi: ${response.statusCode}');
      }
      await response.pipe(file.openWrite());
      client.close();
      final saved = Song(
        id: file.path,
        title: s.title,
        artist: s.artist,
        isMp3: true,
      );
      if (!mounted) return;
      setState(() {
        if (!downloads.any((x) => x.id == saved.id)) downloads.add(saved);
      });
      await saveAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('U ruajt në Downloads')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Gabim shkarkimi: $e');
    }
  }

  Widget cover(Song s, {double size = 54}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: s.image != null
          ? Image.network(
              s.image!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallbackCover(size),
            )
          : fallbackCover(size),
    );
  }

  Widget fallbackCover(double size) {
    return Container(
      width: size,
      height: size,
      color: panel,
      child: Icon(Icons.music_note, color: accent, size: size * .55),
    );
  }

  Widget sectionTitle(String title, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          ),
          if (onTap != null)
            TextButton(onPressed: onTap, child: const Text('Shiko të gjitha')),
        ],
      ),
    );
  }

  Widget categoryCard(String name, Color color, IconData icon) {
    return InkWell(
      onTap: () {
        search.text = name;
        setState(() => tab = 1);
        searchSongs();
      },
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            Icon(icon, size: 30, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Widget horizontalSongs(List<Song> songs) {
    if (songs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: Text('Kërko këngë për të krijuar bibliotekën tënde.',
            style: TextStyle(color: muted)),
      );
    }
    return SizedBox(
      height: 190,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: songs.length,
        itemBuilder: (_, i) {
          final s = songs[i];
          return GestureDetector(
            onTap: () => playSong(s, list: songs),
            child: SizedBox(
              width: 138,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    cover(s, size: 126),
                    const SizedBox(height: 8),
                    Text(s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(s.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 12)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget homePage() {
    final recent = [...favorites, ...downloads, ...results]
        .fold<List<Song>>([], (list, s) {
      if (!list.any((x) => x.id == s.id)) list.add(s);
      return list;
    });

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
            child: Row(
              children: [
                const Icon(Icons.headphones, color: accent, size: 34),
                const SizedBox(width: 9),
                const Text('ERIBeat',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  onPressed: () => setState(() => tab = 3),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 10, 18, 8),
            child: Text('Mirë se erdhe!',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
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
              categoryCard('Rock', const Color(0xFF315C68), Icons.album),
              categoryCard('Dance', const Color(0xFF67456C), Icons.graphic_eq),
              categoryCard('Pop', const Color(0xFF9B5949), Icons.music_note),
              categoryCard('Hip-Hop', const Color(0xFF52664C), Icons.mic),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: sectionTitle('Të dëgjuara së fundmi'),
        ),
        SliverToBoxAdapter(child: horizontalSongs(recent)),
        SliverToBoxAdapter(
          child: sectionTitle('Të preferuarat'),
        ),
        SliverToBoxAdapter(child: horizontalSongs(favorites)),
        SliverToBoxAdapter(
          child: sectionTitle('Playlist-et e tua'),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: playlists.entries.map((e) => Container(
                width: 145,
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.queue_music, color: accent),
                    const Spacer(),
                    Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('${e.value.length} këngë',
                        style: const TextStyle(color: muted, fontSize: 12)),
                  ],
                ),
              )).toList(),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }

  Widget songTile(Song s, {List<Song>? list}) {
    final isFav = favorites.any((x) => x.id == s.id);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      leading: cover(s),
      title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(s.artist, style: const TextStyle(color: muted)),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'fav') toggleFavorite(s);
          if (v == 'playlist') addPlaylist(s);
          if (v == 'download') downloadSong(s);
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'fav',
            child: Text(isFav ? 'Hiq nga Favorites' : 'Shto te Favorites'),
          ),
          const PopupMenuItem(value: 'playlist', child: Text('Shto në Playlist')),
          if (s.isMp3)
            const PopupMenuItem(value: 'download', child: Text('Shkarko')),
        ],
      ),
      onTap: () => playSong(s, list: list ?? [s]),
    );
  }

  Future<void> toggleFavorite(Song s) async {
    setState(() {
      if (favorites.any((x) => x.id == s.id)) {
        favorites.removeWhere((x) => x.id == s.id);
      } else {
        favorites.add(s);
      }
    });
    await saveAll();
  }

  Widget searchPage() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: search,
            onSubmitted: (_) => searchSongs(),
            decoration: InputDecoration(
              hintText: 'Kërko këngë ose artistë',
              filled: true,
              fillColor: panel,
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
            padding: const EdgeInsets.all(8),
            child: Text(error, style: const TextStyle(color: Colors.orange)),
          ),
        Expanded(
          child: results.isEmpty
              ? const Center(
                  child: Text('Kërko muzikën tënde të preferuar',
                      style: TextStyle(color: muted)),
                )
              : ListView(
                  children: results.map((s) => songTile(s, list: results)).toList(),
                ),
        ),
      ],
    );
  }

  Widget libraryPage() {
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 24, 18, 12),
          child: Text('Biblioteka jote',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        ),
        ListTile(
          leading: const Icon(Icons.favorite, color: accent),
          title: const Text('Të preferuarat'),
          subtitle: Text('${favorites.length} këngë'),
          onTap: () => showSongList('Të preferuarat', favorites),
        ),
        const Divider(color: panel),
        ...playlists.entries.map((e) => ListTile(
          leading: const Icon(Icons.queue_music, color: accent),
          title: Text(e.key),
          subtitle: Text('${e.value.length} këngë'),
          onTap: () => showSongList(e.key, e.value),
        )),
      ],
    );
  }

  void showSongList(String title, List<Song> songs) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SongListPage(
          title: title,
          songs: songs,
          play: (s) => playSong(s, list: songs),
        ),
      ),
    );
  }

  Widget downloadsPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(18),
          child: Text('Downloads',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: downloads.isEmpty
              ? const Center(
                  child: Text('Nuk ke ende këngë të shkarkuara',
                      style: TextStyle(color: muted)),
                )
              : ListView(
                  children: downloads.map((s) => songTile(s, list: downloads)).toList(),
                ),
        ),
      ],
    );
  }

  String time(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  void openPlayer() {
    if (currentSong == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      builder: (_) => PlayerSheet(
        song: currentSong!,
        cover: cover,
        time: time,
      ),
    );
  }

  Widget miniPlayer() {
    if (currentSong == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: openPlayer,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF29434A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            cover(currentSong! , size: 43),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(currentSong!.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(currentSong!.artist,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            if (currentSong!.isMp3)
              StreamBuilder<PlayerState>(
                stream: audioHandler.player.playerStateStream,
                builder: (_, snap) {
                  final playing = snap.data?.playing ?? false;
                  return IconButton(
                    onPressed: () => playing
                        ? audioHandler.pause()
                        : audioHandler.play(),
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  );
                },
              ),
            IconButton(
              onPressed: () => toggleFavorite(currentSong!),
              icon: Icon(
                favorites.any((x) => x.id == currentSong!.id)
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
      homePage(),
      searchPage(),
      libraryPage(),
      downloadsPage(),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: IndexedStack(index: tab, children: pages)),
            if (currentSong != null) miniPlayer(),
            if (currentSong != null &&
                !currentSong!.isMp3 &&
                videoController != null)
              YoutubePlayer(
                controller: videoController!,
                showVideoProgressIndicator: true,
              ),
            NavigationBar(
              backgroundColor: const Color(0xFF171F24),
              indicatorColor: const Color(0xFF31545D),
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
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
                  icon: Icon(Icons.library_music_outlined),
                  label: 'Library',
                ),
                NavigationDestination(
                  icon: Icon(Icons.download_outlined),
                  label: 'Downloads',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
      appBar: AppBar(title: Text(title), backgroundColor: bg),
      body: ListView.builder(
        itemCount: songs.length,
        itemBuilder: (_, i) {
          final s = songs[i];
          return ListTile(
            leading: const Icon(Icons.music_note, color: accent),
            title: Text(s.title),
            subtitle: Text(s.artist),
            onTap: () => play(s),
          );
        },
      ),
    );
  }
}

class PlayerSheet extends StatelessWidget {
  final Song song;
  final Widget Function(Song, {double size}) cover;
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                ),
                const Expanded(
                  child: Text('ERIBeat PLAYER',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, letterSpacing: 2)),
                ),
                const SizedBox(width: 45),
              ],
            ),
            const SizedBox(height: 22),
            if (song.image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.network(
                  song.image!,
                  width: 300,
                  height: 300,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 300,
                    height: 300,
                    child: Icon(Icons.music_note, size: 100, color: accent),
                  ),
                ),
              )
            else
              Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.music_note, size: 100, color: accent),
              ),
            const SizedBox(height: 26),
            Text(song.title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text(song.artist, style: const TextStyle(color: muted)),
            const SizedBox(height: 25),
            if (song.isMp3) ...[
              StreamBuilder<Duration?>(
                stream: audioHandler.player.durationStream,
                builder: (_, ds) {
                  final duration = ds.data ?? Duration.zero;
                  return StreamBuilder<Duration>(
                    stream: audioHandler.player.positionStream,
                    builder: (_, ps) {
                      final pos = ps.data ?? Duration.zero;
                      final maxMs = max(1, duration.inMilliseconds);
                      return Column(
                        children: [
                          Slider(
                            min: 0,
                            max: maxMs.toDouble(),
                            value: pos.inMilliseconds.clamp(0, maxMs).toDouble(),
                            onChanged: (v) => audioHandler.seek(
                              Duration(milliseconds: v.round()),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [Text(time(pos)), Text(time(duration))],
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
                    icon: const Icon(Icons.shuffle, color: accent),
                  ),
                  IconButton(
                    onPressed: audioHandler.skipToPrevious,
                    icon: const Icon(Icons.skip_previous, size: 38),
                  ),
                  StreamBuilder<PlayerState>(
                    stream: audioHandler.player.playerStateStream,
                    builder: (_, snap) {
                      final playing = snap.data?.playing ?? false;
                      return IconButton(
                        iconSize: 66,
                        onPressed: () => playing
                            ? audioHandler.pause()
                            : audioHandler.play(),
                        icon: Icon(
                          playing ? Icons.pause_circle : Icons.play_circle,
                          color: accent,
                        ),
                      );
                    },
                  ),
                  IconButton(
                    onPressed: audioHandler.skipToNext,
                    icon: const Icon(Icons.skip_next, size: 38),
                  ),
                  IconButton(
                    onPressed: audioHandler.toggleRepeat,
                    icon: const Icon(Icons.repeat, color: accent),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: PopupMenuButton<double>(
                  onSelected: audioHandler.speed,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 0.75, child: Text('0.75x')),
                    PopupMenuItem(value: 1.0, child: Text('1.0x')),
                    PopupMenuItem(value: 1.25, child: Text('1.25x')),
                    PopupMenuItem(value: 1.5, child: Text('1.5x')),
                    PopupMenuItem(value: 2.0, child: Text('2.0x')),
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
    );
  }
}
