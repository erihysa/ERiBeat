import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  runApp(const EriMusicApp());
}

class EriMusicApp extends StatelessWidget {
  const EriMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101010),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
        ),
      ),
      home: const SpotifyLikeHome(),
    );
  }
}

class SpotifyLikeHome extends StatefulWidget {
  const SpotifyLikeHome({super.key});

  @override
  State<SpotifyLikeHome> createState() => _SpotifyLikeHomeState();
}

class _SpotifyLikeHomeState extends State<SpotifyLikeHome> {
  final AudioPlayer _player = AudioPlayer();

  final List<Playlist> playlists = const [
    Playlist("Liked Songs", "1,245 songs", "♥", Color(0xFF9B59B6)),
    Playlist("Focus", "Deep work", "F", Color(0xFF3B82F6)),
    Playlist("Chill", "Late night", "C", Color(0xFF22C55E)),
    Playlist("On Repeat", "Your favorites", "R", Color(0xFFF59E0B)),
    Playlist("Daily Mix 1", "Ari, Nora", "1", Color(0xFFEF4444)),
    Playlist("Summer", "Sunset vibes", "S", Color(0xFFF97316)),
  ];

  final List<Song> recentSongs = const [
    Song("Midnight Drive", "Ari", "M", Color(0xFF1ED760),
        "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"),
    Song("Sunset Echo", "Nora", "S", Color(0xFF2DD4BF),
        "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3"),
    Song("City Lights", "Luka", "C", Color(0xFFF59E0B),
        "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3"),
    Song("Dream Flow", "Mira", "D", Color(0xFF8B5CF6),
        "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3"),
  ];

  final List<Playlist> library = const [
    Playlist("Your Episodes", "4 unplayed", "E", Color(0xFF10B981)),
    Playlist("Albums", "30 albums", "A", Color(0xFF6366F1)),
    Playlist("Artists", "82 artists", "P", Color(0xFFE11D48)),
    Playlist("Downloaded", "Ready offline", "D", Color(0xFF0EA5E9)),
  ];

  int selectedIndex = 0;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();

    _player.positionStream.listen((position) {
      setState(() => currentPosition = position);
    });

    _player.durationStream.listen((duration) {
      if (duration != null) {
        setState(() => totalDuration = duration);
      }
    });

    _player.playerStateStream.listen((state) {
      setState(() => isPlaying = state.playing);
    });
  }

  Future<void> playSong(int index) async {
    final song = recentSongs[index];
    setState(() => selectedIndex = index);

    await _player.setUrl(song.url);
    await _player.play();
  }

  Future<void> togglePlay() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.idle) {
        await playSong(0);
      } else {
        await _player.play();
      }
    }
  }

  String formatTime(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = recentSongs[selectedIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: ListView(
            children: [
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Good evening',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1C1C1C),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text(
                        'E',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.7,
                ),
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final item = playlists[index];
                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: item.color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              item.coverLetter,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                item.subtitle,
                                style: const TextStyle(
                                  color: Color(0xFFB3B3B3),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              const Text(
                'Recently played',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: recentSongs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final song = recentSongs[index];
                    return GestureDetector(
                      onTap: () => playSong(index),
                      child: SizedBox(
                        width: 150,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                color: song.color,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: Text(
                                  song.coverLetter,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              song.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              song.artist,
                              style: const TextStyle(
                                color: Color(0xFFB3B3B3),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Your library',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.7,
                ),
                itemCount: library.length,
                itemBuilder: (context, index) {
                  final item = library[index];
                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF171717),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: item.color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              item.coverLetter,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                item.subtitle,
                                style: const TextStyle(
                                  color: Color(0xFFB3B3B3),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        color: const Color(0xFF1A1A1A),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: currentSong.color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          currentSong.coverLetter,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentSong.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          currentSong.artist,
                          style: const TextStyle(
                            color: Color(0xFFB3B3B3),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.skip_previous, color: Colors.white),
                    ),
                    IconButton(
                      onPressed: togglePlay,
                      icon: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.black,
                        size: 30,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: const CircleBorder(),
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.skip_next, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  formatTime(currentPosition),
                  style: const TextStyle(
                    color: Color(0xFFD9D9D9),
                    fontSize: 12,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: totalDuration.inMilliseconds > 0
                        ? (currentPosition.inMilliseconds /
                                totalDuration.inMilliseconds)
                            .clamp(0.0, 1.0)
                        .toDouble()
                        : 0.0,
                    onChanged: (value) async {
                      final targetPosition =
                          (value * totalDuration.inMilliseconds).round();
                      await _player.seek(Duration(milliseconds: targetPosition));
                    },
                    activeColor: const Color(0xFF1ED760),
                    inactiveColor: const Color(0xFF3A3A3A),
                    thumbColor: Colors.white,
                  ),
                ),
                Text(
                  formatTime(totalDuration),
                  style: const TextStyle(
                    color: Color(0xFFD9D9D9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class Playlist {
  final String title;
  final String subtitle;
  final String coverLetter;
  final Color color;

  const Playlist(this.title, this.subtitle, this.coverLetter, this.color);
}

class Song {
  final String title;
  final String artist;
  final String coverLetter;
  final Color color;
  final String url;

  const Song(this.title, this.artist, this.coverLetter, this.color, this.url);
}
