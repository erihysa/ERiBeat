import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ERIBeat Music',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.green,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const MusicHomePage(),
    );
  }
}

class MusicHomePage extends StatefulWidget {
  const MusicHomePage({super.key});

  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage> {
  final TextEditingController _controller = TextEditingController();
  final YoutubeExplode _yt = YoutubeExplode();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  String _songTitle = "Zgjidh një kategori ose kërko një këngë";
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isShuffleEnabled = false;
  bool _isRepeatEnabled = false;

  // Lista e kategorive/zhanreve
  final List<String> _categories = [
    "Rock Hits",
    "Hip Hop Rap",
    "Pop Music",
    "Electronic / EDM",
    "Chill & Relax",
    "Albanian Music"
  ];

  Future<void> _playSong(String query) async {
    setState(() {
      _isLoading = true;
      _songTitle = "Duke kërkuar: $query...";
    });

    try {
      var searchResults = await _yt.search.search(query);
      if (searchResults.isEmpty) {
        setState(() {
          _songTitle = "Nuk u gjet asnjë rezultat!";
          _isLoading = false;
        });
        return;
      }
      
      var video = searchResults.first;
      setState(() {
        _songTitle = video.title;
      });

      var manifest = await _yt.videos.streamsClient.getManifest(video.id);
      var audioStreamInfo = manifest.audioOnly.withHighestBitrate();

      await _audioPlayer.setUrl(audioStreamInfo.url.toString());
      await _audioPlayer.play();

      setState(() {
        _isPlaying = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _songTitle = "Gabim gjatë luajtjes!";
        _isLoading = false;
      });
    }
  }

  void _stopSong() async {
    await _audioPlayer.stop();
    setState(() {
      _isPlaying = false;
      _songTitle = "Muzika u ndalua";
    });
  }

  void _toggleShuffle() {
    setState(() {
      _isShuffleEnabled = !_isShuffleEnabled;
    });
    // Mund të shtosh logjikën e shuffle këtu nëse shton playlistë
  }

  void _toggleRepeat() {
    setState(() {
      _isRepeatEnabled = !_isRepeatEnabled;
    });
    if (_isRepeatEnabled) {
      _audioPlayer.setLoopMode(LoopMode.one);
    } else {
      _audioPlayer.setLoopMode(LoopMode.off);
    }
  }

  @override
  void dispose() {
    _yt.close();
    _audioPlayer.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ERIBeat - YouTube Music'),
        backgroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fusha e kërkimit
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Kërko artist ose këngë...',
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.search, color: Colors.green),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isLoading ? null : () {
                if (_controller.text.isNotEmpty) {
                  _playSong(_controller.text);
                }
              },
              child: _isLoading 
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Kërko dhe Luaj', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
            const SizedBox(height: 24),

            // Seksioni i Kategorive (Zhanret)
            const Text(
              'Kategoritë & Zhanret',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 45,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ActionChip(
                      backgroundColor: Colors.grey[850],
                      label: Text(_categories[index], style: const TextStyle(color: Colors.white)),
                      onPressed: () {
                        _playSong(_categories[index]);
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 40),

            // Informacioni i këngës aktuale
            Center(
              child: Column(
                children: [
                  const Icon(
                    Icons.music_note,
                    size: 60,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Duke luajtur tani:',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _songTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
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
