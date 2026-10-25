import 'dart:math';
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
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.green,
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
  
  List<Video> _searchResults = [];
  Video? _currentVideo;
  int _currentIndex = -1;
  
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isShuffleEnabled = false;
  bool _isRepeatEnabled = false;

  final List<String> _categories = [
    "Rock Hits",
    "Hip Hop Rap",
    "Pop Music",
    "Electronic / EDM",
    "Chill & Relax",
    "Albanian Music"
  ];

  // 1. Kërko dhe shfaq listën e këngëve
  Future<void> _searchSongs(String query) async {
    setState(() {
      _isLoading = true;
    });

    try {
      var results = await _yt.search.search(query);
      setState(() {
        _searchResults = results.toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 2. Luaj një këngë të caktuar nga lista
  Future<void> _playSong(Video video, int index) async {
    setState(() {
      _isLoading = true;
      _currentVideo = video;
      _currentIndex = index;
    });

    try {
      var manifest = await _yt.videos.streamsClient.getManifest(video.id);
      var streamInfo = manifest.audioOnly.withHighestBitrate();

      if (streamInfo == null) {
        var muxedInfo = manifest.muxed.withHighestBitrate();
        await _audioPlayer.setUrl(muxedInfo.url.toString());
      } else {
        await _audioPlayer.setUrl(streamInfo.url.toString());
      }

      await _audioPlayer.play();
      setState(() {
        _isPlaying = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 3. Kënga e radhës (Next)
  void _playNext() {
    if (_searchResults.isEmpty) return;
    
    int nextIndex;
    if (_isShuffleEnabled) {
      nextIndex = Random().nextInt(_searchResults.length);
    } else {
      nextIndex = (_currentIndex + 1) % _searchResults.length;
    }
    
    _playSong(_searchResults[nextIndex], nextIndex);
  }

  // 4. Ndalimi i muzikës
  void _stopSong() async {
    await _audioPlayer.stop();
    setState(() {
      _isPlaying = false;
    });
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
        title: const Text('ERIBeat - Spotify Style'),
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
                hintText: 'Kërko këngë ose artist...',
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.search, color: Colors.green),
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) _searchSongs(value);
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                if (_controller.text.isNotEmpty) {
                  _searchSongs(_controller.text);
                }
              },
              child: const Text('Kërko në Katalog', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
            const SizedBox(height: 20),

            // Kategoritë / Zhanret
            const Text('Zhanret & Sugjerimet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
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
                        _controller.text = _categories[index];
                        _searchSongs(_categories[index]);
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // Paneli i Këngës Aktuale (Player UI)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                children: [
                  const Icon(Icons.music_note, size: 50, color: Colors.green),
                  const SizedBox(height: 10),
                  Text(
                    _currentVideo?.title ?? "Asnjë këngë e zgjedhur",
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  // Shiriti i Sekondave (Slider)
                  StreamBuilder<Duration?>(
                    stream: _audioPlayer.positionStream,
                    builder: (context, snapshotPos) {
                      final position = snapshotPos.data ?? Duration.zero;
                      return StreamBuilder<Duration?>(
                        stream: _audioPlayer.durationStream,
                        builder: (context, snapshotDur) {
                          final duration = snapshotDur.data ?? Duration.zero;
                          return Column(
                            children: [
                              Slider(
                                activeColor: Colors.green,
                                inactiveColor: Colors.grey[700],
                                min: 0.0,
                                max: duration.inMilliseconds.toDouble() > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                                value: position.inMilliseconds.toDouble().clamp(0.0, duration.inMilliseconds.toDouble() > 0 ? duration.inMilliseconds.toDouble() : 1.0),
                                onChanged: (value) {
                                  _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_formatDuration(position), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    Text(_formatDuration(duration), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),

                  // Kontrollet: Shuffle, Play/Pause, Stop, Next, Repeat
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(Icons.shuffle, color: _isShuffleEnabled ? Colors.green : Colors.grey),
                        onPressed: () => setState(() => _isShuffleEnabled = !_isShuffleEnabled),
                      ),
                      IconButton(
                        icon: const Icon(Icons.stop, color: Colors.redAccent),
                        onPressed: _stopSong,
                      ),
                      IconButton(
                        iconSize: 50,
                        color: Colors.green,
                        icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                        onPressed: () {
                          if (_isPlaying) {
                            _audioPlayer.pause();
                            setState(() => _isPlaying = false);
                          } else {
                            if (_currentVideo != null) {
                              _audioPlayer.play();
                              setState(() => _isPlaying = true);
                            }
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next, color: Colors.white, size: 30),
                        onPressed: _playNext,
                      ),
                      IconButton(
                        icon: Icon(Icons.repeat, color: _isRepeatEnabled ? Colors.green : Colors.grey),
                        onPressed: () {
                          setState(() {
                            _isRepeatEnabled = !_isRepeatEnabled;
                            _audioPlayer.setLoopMode(_isRepeatEnabled ? LoopMode.one : LoopMode.off);
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Lista e Kërkimit (Sugjerimet ku mund të zgjedhësh)
            const Text('Rezultatet / Lista e Kërkimit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.green))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      var video = _searchResults[index];
                      bool isSelected = _currentIndex == index;
                      return Card(
                        color: isSelected ? Colors.grey[800] : Colors.grey[900],
                        child: ListTile(
                          leading: const Icon(Icons.play_arrow, color: Colors.green),
                          title: Text(
                            video.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: isSelected ? Colors.green : Colors.white, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(video.author, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          onTap: () {
                            _playSong(video, index);
                          },
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }
}
