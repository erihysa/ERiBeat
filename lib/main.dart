
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ERiBeatApp());
}

class Track {
  final String id;
  final String title;
  final String author;

  Track({
    required this.id,
    required this.title,
    required this.author,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
      };

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String,
    );
  }
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
        colorSchemeSeed: Colors.green,
        useMaterial3: true,
      ),
      home: const MusicPage(),
    );
  }
}

class MusicPage extends StatefulWidget {
  const MusicPage({super.key});

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  final YoutubeExplode yt = YoutubeExplode();
  final AudioPlayer player = AudioPlayer();
  final TextEditingController searchController =
      TextEditingController();

  List<Video> results = [];
  List<Track> playlist = [];

  bool searching = false;
  bool loadingTrack = false;
  int tab = 0;

  String status = 'Kërko këngën tënde';
  String currentTitle = 'ERIBeat';

  @override
  void initState() {
    super.initState();
    loadPlaylist();
  }

  Future<void> loadPlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('eribeat_playlist');

    if (stored != null) {
      try {
        final List<dynamic> decoded = jsonDecode(stored);
        if (!mounted) return;
        setState(() {
          playlist = decoded
              .map((item) => Track.fromJson(
                  Map<String, dynamic>.from(item)))
              .toList();
        });
      } catch (_) {
        setState(() {
          playlist = [];
        });
      }
    }
  }

  Future<void> savePlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'eribeat_playlist',
      jsonEncode(playlist.map((track) => track.toJson()).toList()),
    );
  }

  bool isSaved(Video video) {
    return playlist.any(
      (track) => track.id == video.id.toString(),
    );
  }

  Future<void> toggleSave(Video video) async {
    final id = video.id.toString();

    setState(() {
      final index = playlist.indexWhere((track) => track.id == id);

      if (index >= 0) {
        playlist.removeAt(index);
      } else {
        playlist.add(
          Track(
            id: id,
            title: video.title,
            author: video.author,
          ),
        );
      }
    });

    await savePlaylist();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            playlist.any((track) => track.id == id)
                ? 'U ruajt në Playlist'
                : 'U hoq nga Playlist',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> removeTrack(Track track) async {
    setState(() {
      playlist.removeWhere((item) => item.id == track.id);
    });
    await savePlaylist();
  }

  Future<void> searchMusic(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      searching = true;
      status = 'Duke kërkuar...';
    });

    try {
      final found = await yt.search.search(query);
      if (!mounted) return;

      setState(() {
        results = found.take(25).toList();
        status = results.isEmpty
            ? 'Nuk u gjetën këngë.'
            : 'Rezultatet: ${results.length}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        status = 'Gabim kërkimi. Kontrollo internetin.';
      });
    } finally {
      if (mounted) {
        setState(() => searching = false);
      }
    }
  }

  Future<void> playTrack(Track track) async {
    await playById(track.id, track.title);
  }

  Future<void> playVideo(Video video) async {
    await playById(video.id.toString(), video.title);
  }

  Future<void> playById(String id, String title) async {
    setState(() {
      loadingTrack = true;
      currentTitle = title;
      status = 'Duke hapur këngën...';
    });

    try {
      final manifest =
          await yt.videos.streamsClient.getManifest(VideoId(id));

      final audio = manifest.audioOnly.withHighestBitrate();

      await player.setUrl(audio.url.toString());
      await player.play();

      if (mounted) {
        setState(() => status = 'Po luhet: $title');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          status = 'Nuk u luajt. Provo një këngë tjetër.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => loadingTrack = false);
      }
    }
  }

  Widget searchTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: searchMusic,
            decoration: InputDecoration(
              hintText: 'Kërko këngë ose artist...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => searchMusic(searchController.text),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (searching) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(status),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final video = results[index];
              final saved = isSaved(video);

              return ListTile(
                leading: const Icon(
                  Icons.music_note,
                  color: Colors.greenAccent,
                ),
                title: Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(video.author),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: saved ? 'Hiq nga Playlist' : 'Save',
                      icon: Icon(
                        saved ? Icons.favorite : Icons.favorite_border,
                        color: saved ? Colors.redAccent : null,
                      ),
                      onPressed: () => toggleSave(video),
                    ),
                    IconButton(
                      tooltip: 'Play',
                      icon: const Icon(Icons.play_circle_fill),
                      onPressed: () => playVideo(video),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget playlistTab() {
    if (playlist.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.queue_music, size: 64),
            SizedBox(height: 12),
            Text('Playlist është bosh'),
            Text('Kërko një këngë dhe shtyp ♡ për ta ruajtur.'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: playlist.length,
      itemBuilder: (context, index) {
        final track = playlist[index];

        return ListTile(
          leading: const Icon(
            Icons.music_note,
            color: Colors.greenAccent,
          ),
          title: Text(
            track.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(track.author),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Play',
                icon: const Icon(Icons.play_circle_fill),
                onPressed: () => playTrack(track),
              ),
              IconButton(
                tooltip: 'Hiq nga Playlist',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => removeTrack(track),
              ),
            ],
          ),
          onTap: () => playTrack(track),
        );
      },
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    player.dispose();
    yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '🎵 ERIBeat',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (tab == 1)
            IconButton(
              tooltip: 'Fshi të gjithë Playlist',
              icon: const Icon(Icons.delete_sweep),
              onPressed: () async {
                setState(() => playlist.clear());
                await savePlaylist();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: tab == 0 ? searchTab() : playlistTab(),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 16,
            ),
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Column(
              children: [
                Text(
                  currentTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.stop),
                      onPressed: () => player.stop(),
                    ),
                    IconButton.filled(
                      iconSize: 34,
                      icon: loadingTrack
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.play_arrow),
                      onPressed: loadingTrack
                          ? null
                          : () => player.play(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.pause),
                      onPressed: () => player.pause(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) {
          setState(() => tab = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search),
            label: 'Kërko',
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
