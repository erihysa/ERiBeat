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
        useMaterial3: true,
      ),
      home: const EriMusicHome(),
    );
  }
}

class EriMusicHome extends StatefulWidget {
  const EriMusicHome({super.key});

  @override
  State<EriMusicHome> createState() => _EriMusicHomeState();
}

class _EriMusicHomeState extends State<EriMusicHome> {
  int _selectedTab = 0;
  String _searchQuery = '';

  final AudioPlayer _player = AudioPlayer();

  final List<PlaylistItem> playlists = const [
    PlaylistItem("Liked Songs", "1,245 songs", "♥", Color(0xFF9B59B6)),
    PlaylistItem("Focus", "Deep work", "F", Color(0xFF3B82F6)),
    PlaylistItem("Chill", "Late night", "C", Color(0xFF22C55E)),
    PlaylistItem("On Repeat", "Your favorites", "R", Color(0xFFF59E0B)),
    PlaylistItem("Daily Mix 1", "Ari, Nora", "1", Color(0xFFEF4444)),
    PlaylistItem("Summer", "Sunset vibes", "S", Color(0xFFF97316)),
  ];

  final List<Song> catalogSongs = const [
    Song("Midnight Drive", "Ari", "M", Color(0xFF1ED760),
        "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"),
    Song("Sunset Echo", "Nora", "S", Color(0xFF2DD4BF),
        "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3"),
    Song("City Lights", "Luka", "C", Color(0xFFF59E0B),
        "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3"),
    Song("Dream Flow", "Mira", "D", Color(0xFF8B5CF6),
        "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3"),
    Song("Velvet Sky", "Ari", "V", Color(0xFF8B5CF6),
        "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3"),
    Song("Night Orbit", "Juno", "N", Color(0xFF10B981),
        "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3"),
    Song("Golden Hour", "Lina", "G", Color(0xFFF59E0B),
        "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3"),
    Song("Ocean Bloom", "Mira", "O", Color(0xFF3B82F6),
        "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3"),
  ];

  final List<Song> librarySongs = const [
    Song("Your Favorite", "Ari", "Y", Color(0xFF9B59B6),
        "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"),
    Song("Deep Calm", "Nora", "D", Color(0xFF22C55E),
        "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3"),
    Song("Night Flow", "Luka", "N", Color(0xFFEF4444),
        "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3"),
  ];

  int selectedIndex = 0;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();

    _player.positionStream.listen((position) {
      if (!mounted) return;
      setState(() => currentPosition = position);
    });

    _player.durationStream.listen((duration) {
      if (!mounted || duration == null) return;
      setState(() => totalDuration = duration);
    });

    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => isPlaying = state.playing);
    });
  }

  List<Song> get filteredCatalog {
    if (_searchQuery.trim().isEmpty) {
      return catalogSongs;
    }
    final q = _searchQuery.toLowerCase();
    return catalogSongs.where((song) {
      return song.title.toLowerCase().contains(q) ||
          song.artist.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> playSong(Song song) async {
    setState(() => selectedIndex = catalogSongs.indexOf(song) >= 0
        ? catalogSongs.indexOf(song)
        : 0);

    await _player.setUrl(song.url);
    await _player.play();
  }

  Future<void> togglePlay() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.idle) {
        final first = filteredCatalog.isNotEmpty ? filteredCatalog.first : catalogSongs.first;
        await playSong(first);
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

  Widget buildHomePage() {
    return SafeArea(
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
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  width: 40,
                  height: 40,
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
                childAspectRatio: 2.8,
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
            const SizedBox(height: 18),
            const Text(
              'Recommended for you',
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
                itemCount: catalogSongs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final song = catalogSongs[index];
                  return GestureDetector(
                    onTap: () => playSong(song),
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
                                  fontSize: 26,
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
          ],
        ),
      ),
    );
  }

  Widget buildSearchPage() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: ListView(
          children: [
            const SizedBox(height: 18),
            TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1C1C1C),
                hintText: 'Search in catalog',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Catalog',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (filteredCatalog.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No results found',
                  style: TextStyle(color: Colors.white54),
                ),
              )
            else
              ...filteredCatalog.map((song) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: song.color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              song.coverLetter,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                song.artist,
                                style: const TextStyle(
                                  color: Color(0xFFB3B3B3),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => playSong(song),
                          icon: const Icon(Icons.play_arrow, color: Colors.white),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget buildLibraryPage() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: ListView(
          children: [
            const SizedBox(height: 18),
            const Text(
              'Library',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            ...librarySongs.map((song) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: song.color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            song.coverLetter,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              song.artist,
                              style: const TextStyle(
                                color: Color(0xFFB3B3B3),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => playSong(song),
                        icon: const Icon(Icons.play_arrow, color: Colors.white),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget buildMainContent() {
    switch (_selectedTab) {
      case 1:
        return buildSearchPage();
      case 2:
        return buildLibraryPage();
      default:
        return buildHomePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = filteredCatalog.isNotEmpty ? filteredCatalog.first : catalogSongs.first;

    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      body: Row(
        children: [
          Container(
            width: 220,
            color: const Color(0xFF090909),
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EriMusic',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                _SidebarItem(
                  icon: Icons.home,
                  label: 'Home',
                  active: _selectedTab == 0,
                  onTap: () => setState(() => _selectedTab = 0),
                ),
                _SidebarItem(
                  icon: Icons.search,
                  label: 'Search',
                  active: _selectedTab == 1,
                  onTap: () => setState(() => _selectedTab = 1),
                ),
                _SidebarItem(
                  icon: Icons.library_music,
                  label: 'Library',
                  active: _selectedTab == 2,
                  onTap: () => setState(() => _selectedTab = 2),
                ),
                const Spacer(),
                const Text(
                  'PLAYLISTS',
                  style: TextStyle(
                    color: Color(0xFFB3B3B3),
                    fontSize: 12,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                ...playlists.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        p.title,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    )),
              ],
            ),
          ),
          Expanded(
            child: Scaffold(
              backgroundColor: const Color(0xFF101010),
              body: buildMainContent(),
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
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1E1E1E) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: active ? Colors.white : Colors.white70,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white70,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlaylistItem {
  final String title;
  final String subtitle;
  final String coverLetter;
  final Color color;

  const PlaylistItem(this.title, this.subtitle, this.coverLetter, this.color);
}

class Song {
  final String title;
  final String artist;
  final String coverLetter;
  final Color color;
  final String url;

  const Song(this.title, this.artist, this.coverLetter, this.color, this.url);
}
