import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  List<Video> _results = [];
  Video? _currentVideo;

  int _currentIndex = -1;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  bool _isLoading = false;
  bool _isSearching = false;
  bool _isShuffle = false;
  bool _isRepeat = false;
  bool _isDisposed = false;

  String? _errorMessage;

  bool get _isPlaying => _player.playing;

  final List<String> _categories = [
    'Pop Music',
    'Rock Hits',
    'Hip Hop Rap',
    'Electronic EDM',
    'Chill Music',
    'Albanian Music',
  ];

  @override
  void initState() {
    super.initState();

    _playerStateSubscription =
        _player.playerStateStream.listen((state) {
      if (!mounted) return;

      setState(() {});

      if (state.processingState == ProcessingState.completed &&
          !_isRepeat) {
        _playNext();
      }
    });

    _durationSubscription = _player.durationStream.listen((duration) {
      if (!mounted) return;

      setState(() {
        _duration = duration ?? Duration.zero;
      });
    });

    _positionSubscription = _player.positionStream.listen((position) {
      if (!mounted) return;

      setState(() {
        _position = position;
      });
    });
  }

  Future<void> _searchSongs(String query) async {
    final searchQuery = query.trim();
    if (searchQuery.isEmpty) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _results = [];
    });

    try {
      final videos = await _yt.search
          .search(searchQuery)
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;

      setState(() {
        _results = videos.toList();
        _isSearching = false;
      });

      if (_results.isEmpty) {
        _showError('Nuk u gjet asnjë këngë.');
      }
    } catch (e) {
      debugPrint('Search error: $e');

      if (!mounted) return;

      setState(() {
        _isSearching = false;
      });

      _showError(
        'Kërkimi dështoi. Kontrollo internetin dhe provo përsëri.',
      );
    }
  }

  Future<void> _playSong(Video video, int index) async {
    if (_isDisposed) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentVideo = video;
      _currentIndex = index;
      _duration = video.duration ?? Duration.zero;
      _position = Duration.zero;
    });

    try {
      final manifest = await _yt.videos.streamsClient
          .getManifest(video.id)
          .timeout(const Duration(seconds: 25));

      final audioStreams = manifest.audioOnly;

      if (audioStreams.isEmpty) {
        throw Exception('Nuk u gjet audio për këtë video.');
      }

      final audio = audioStreams.withHighestBitrate();
      final url = audio.url.toString();

      await _player.stop();

      await _player
          .setUrl(url)
          .timeout(const Duration(seconds: 25));

      if (!mounted || _isDisposed) return;

      setState(() {
        _isLoading = false;
        _duration = _player.duration ?? video.duration ?? Duration.zero;
      });

      await _player.play();
    } catch (e) {
      debugPrint('ERIBeat playback error: $e');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage =
            'Nuk u hap kënga. Provo një tjetër ose kontrollo internetin.';
      });
    }
  }

  Future<void> _togglePlayback() async {
    if (_isLoading) return;

    try {
      if (_player.playing) {
        await _player.pause();
      } else if (_currentVideo != null &&
          _player.audioSource != null) {
        await _player.play();
      } else if (_results.isNotEmpty) {
        final index = _currentIndex >= 0 ? _currentIndex : 0;
        await _playSong(_results[index], index);
      } else {
        _showError('Kërko një këngë dhe zgjidhe nga lista.');
      }
    } catch (e) {
      debugPrint('Playback control error: $e');
      _showError('Nuk mund të niset muzika.');
    }
  }

  Future<void> _playNext() async {
    if (_results.isEmpty || _isDisposed) return;

    int nextIndex;

    if (_isShuffle && _results.length > 1) {
      do {
        nextIndex = Random().nextInt(_results.length);
      } while (nextIndex == _currentIndex);
    } else {
      nextIndex = (_currentIndex + 1) % _results.length;
    }

    await _playSong(_results[nextIndex], nextIndex);
  }

  Future<void> _playPrevious() async {
    if (_results.isEmpty) return;

    if (_position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }

    final previousIndex = _currentIndex <= 0
        ? _results.length - 1
        : _currentIndex - 1;

    await _playSong(_results[previousIndex], previousIndex);
  }

  Future<void> _stopSong() async {
    await _player.stop();

    if (!mounted) return;

    setState(() {
      _position = Duration.zero;
      _isLoading = false;
    });
  }

  Future<void> _toggleRepeat() async {
    final newRepeat = !_isRepeat;

    setState(() {
      _isRepeat = newRepeat;
    });

    await _player.setLoopMode(
      newRepeat ? LoopMode.one : LoopMode.off,
    );
  }

  Future<void> _seek(double value) async {
    await _player.seek(
      Duration(milliseconds: value.round()),
    );
  }

  void _showError(String message) {
    if (!mounted) return;

    setState(() {
      _errorMessage = message;
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (duration.inHours > 0) {
      return '${duration.inHours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${duration.inMinutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _isDisposed = true;

    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();

    _controller.dispose();
    _yt.close();
    _player.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxPosition = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;

    final sliderPosition = _position.inMilliseconds
        .toDouble()
        .clamp(0.0, maxPosition);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Row(
          children: [
            Icon(Icons.graphic_eq, color: Colors.green),
            SizedBox(width: 8),
            Text(
              'ERIBeat',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(width: 6),
            Text(
              'Music',
              style: TextStyle(color: Colors.green),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: _searchSongs,
              decoration: InputDecoration(
                hintText: 'Kërko këngë ose artist...',
                prefixIcon: const Icon(
                  Icons.search,
                  color: Colors.green,
                ),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isSearching
                    ? null
                    : () => _searchSongs(_controller.text),
                icon: const Icon(Icons.search),
                label: const Text('Kërko në Katalog'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Zhanret & Sugjerimet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _categories.map((category) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      backgroundColor: Colors.grey[850],
                      label: Text(category),
                      onPressed: () {
                        _controller.text = category;
                        _searchSongs(category);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 22),

            // Player
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade800),
              ),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _currentVideo != null
                        ? Image.network(
                            _currentVideo!.thumbnails.highResUrl,
                            height: 190,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _coverPlaceholder(),
                          )
                        : _coverPlaceholder(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _currentVideo?.title ??
                        'Zgjidh një këngë nga lista',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _currentVideo?.author ?? 'ERIBeat Music Player',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    min: 0,
                    max: maxPosition,
                    value: sliderPosition,
                    activeColor: Colors.green,
                    inactiveColor: Colors.grey,
                    onChanged: _duration.inMilliseconds > 0
                        ? _seek
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_position),
                          style: const TextStyle(color: Colors.grey),
                        ),
                        Text(
                          _formatDuration(_duration),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Column(
                        children: [
                          CircularProgressIndicator(color: Colors.green),
                          SizedBox(height: 8),
                          Text(
                            'Duke ngarkuar audion...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        tooltip: 'Shuffle',
                        onPressed: () {
                          setState(() {
                            _isShuffle = !_isShuffle;
                          });
                        },
                        icon: Icon(
                          Icons.shuffle,
                          color: _isShuffle ? Colors.green : Colors.grey,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Previous',
                        onPressed: _playPrevious,
                        icon: const Icon(Icons.skip_previous),
                      ),
                      IconButton(
                        tooltip: 'Stop',
                        onPressed: _stopSong,
                        icon: const Icon(
                          Icons.stop_circle_outlined,
                          color: Colors.redAccent,
                          size: 30,
                        ),
                      ),
                      IconButton(
                        tooltip: _isPlaying ? 'Pause' : 'Play',
                        onPressed: _togglePlayback,
                        iconSize: 48,
                        color: Colors.green,
                        icon: Icon(
                          _isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next',
                        onPressed: _playNext,
                        icon: const Icon(Icons.skip_next, size: 30),
                      ),
                      IconButton(
                        tooltip: 'Repeat',
                        onPressed: _toggleRepeat,
                        icon: Icon(
                          Icons.repeat,
                          color: _isRepeat ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text(
              'Rezultatet / Lista e Kërkimit',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),

            if (_isSearching)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: Colors.green),
                ),
              )
            else if (_results.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Kërko një këngë për të parë rezultatet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ...List.generate(_results.length, (index) {
                final video = _results[index];
                final selected = index == _currentIndex;

                return Card(
                  color: selected
                      ? Colors.green.withOpacity(0.15)
                      : Colors.grey[900],
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        video.thumbnails.mediumResUrl,
                        width: 55,
                        height: 55,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.music_note,
                          color: Colors.green,
                        ),
                      ),
                    ),
                    title: Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? Colors.green : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      video.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: selected && _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(
                            selected && _isPlaying
                                ? Icons.equalizer
                                : Icons.play_arrow,
                            color: Colors.green,
                          ),
                    onTap: () => _playSong(video, index),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      height: 190,
      width: double.infinity,
      color: Colors.grey[850],
      child: const Icon(
        Icons.music_note,
        size: 70,
        color: Colors.green,
      ),
    );
  }
}
