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
      title: 'YouTube Music App',
      theme: ThemeData.dark(),
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
  
  String _songTitle = "Kërko një këngë për të dëgjuar";
  bool _isPlaying = false;

  Future<void> _playSong(String query) async {
    try {
      // Merr katalogun nga YouTube
      var searchResults = await _yt.search.search(query);
      if (searchResults.isEmpty) return;
      var video = searchResults.first;

      setState(() {
        _songTitle = video.title;
      });

      // Gjej linqet e audios pa reklama
      var manifest = await _yt.videos.streamsClient.getManifest(video.id);
      var audioStreamInfo = manifest.audioOnly.withHighestBitrate();

      // Luaj audion
      await _audioPlayer.setUrl(audioStreamInfo.url.toString());
      _audioPlayer.play();

      setState(() {
        _isPlaying = true;
      });
    } catch (e) {
      print("Gabim: $e");
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
        title: const Text('YouTube Music (Pa Reklama)'),
        backgroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Kërko çdo këngë nga YouTube...',
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: () {
                if (_controller.text.isNotEmpty) {
                  _playSong(_controller.text);
                }
              },
              child: const Text('Kërko dhe Luaj', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 40),
            Text('Duke luajtur tani:', style: TextStyle(color: Colors.grey[400])),
            const SizedBox(height: 8),
            Text(
              _songTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            IconButton(
              iconSize: 72,
              color: Colors.green,
              icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
              onPressed: () {
                if (_isPlaying) {
                  _audioPlayer.pause();
                  setState(() => _isPlaying = false);
                } else {
                  _audioPlayer.play();
                  setState(() => _isPlaying = true);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
