import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ktify/screens/channel_page.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

// ⭐️ NEW: Import the ChannelPage from its separate file

// Helper function to format duration (e.g., 00:00 or 00:00:00)
String formatDuration(Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final hours = duration.inHours;
  final minutes = twoDigits(duration.inMinutes.remainder(60));
  final seconds = twoDigits(duration.inSeconds.remainder(60));

  if (hours > 0) {
    return '${twoDigits(hours)}:$minutes:$seconds';
  } else {
    return '$minutes:$seconds';
  }
}

void main() {
  // NOTE: Replace the placeholder with your actual API key for a functional app.
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'YouTube MP3 Player UI',
      theme: ThemeData(
        // Using a dark primary color for a sleek look
        primarySwatch: Colors.blueGrey,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1C1C1C),
          elevation: 0,
        ),
      ),
      home: const YoutubeMusicSearch(),
    );
  }
}

// =========================================================================
// YOUTUBE MUSIC SEARCH (HOME) WIDGET
// =========================================================================

class YoutubeMusicSearch extends StatefulWidget {
  const YoutubeMusicSearch({super.key});

  @override
  State<YoutubeMusicSearch> createState() => _YoutubeMusicSearchState();
}

class _YoutubeMusicSearchState extends State<YoutubeMusicSearch> {
  final ctrl = TextEditingController();
  final ScrollController _scrollController =
      ScrollController(); // Scroll Controller
  List videos = [];
  YoutubePlayerController? player;
  Map<String, dynamic>? currentTrack;

  // State variable to control the animation and padding
  bool _isPlayerVisible = false;

  // NOTE: REPLACE THIS KEY WITH YOUR ACTUAL YOUTUBE DATA API KEY
  static const apiKey = "AIzaSyDtFCwWmCYx75yzygjI0x1yjRYfbNx2rss";

  // --- API and Search Logic ---

  Future<List> fetchVideoDetails(List searchItems) async {
    if (searchItems.isEmpty) return [];

    final videoIds = searchItems
        .where((item) => item["id"] != null && item["id"]["videoId"] != null)
        .map((item) => item["id"]["videoId"])
        .join(',');

    if (videoIds.isEmpty) return [];

    final url = Uri.https("www.googleapis.com", "/youtube/v3/videos", {
      "part": "contentDetails,snippet",
      "id": videoIds,
      "key": apiKey,
    });

    final res = await http.get(url);
    final data = jsonDecode(res.body);
    final videoDetailsMap = {for (var item in data["items"]) item["id"]: item};

    List finalVideos = [];
    for (var searchItem in searchItems) {
      final videoId = searchItem["id"]["videoId"];
      final detail = videoDetailsMap[videoId];

      if (detail != null) {
        final duration = detail["contentDetails"]["duration"] ?? "";

        // Filter out shorts or very short videos
        if (duration.contains('M') || duration.contains('H')) {
          finalVideos.add({
            "id": {"videoId": videoId},
            "snippet": {
              ...detail["snippet"], // Merges snippet from video details
              "channelId":
                  detail["snippet"]["channelId"], // Ensure channelId is present
              "channelTitle":
                  detail["snippet"]["channelTitle"], // Ensure channelTitle is present
            },
          });
        }
      }
    }

    return finalVideos;
  }

  Future<void> search(String q) async {
    if (q.isEmpty) return;

    final url = Uri.https("www.googleapis.com", "/youtube/v3/search", {
      "part": "snippet",
      "q": q,
      "type": "video",
      "maxResults": "25",
      "key": apiKey,
    });

    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final fullVideos = await fetchVideoDetails(data["items"]);

        setState(() {
          videos = fullVideos;
        });
      } else {
        print("API Error: ${res.statusCode}");
        setState(() {
          videos = [
            {
              "snippet": {
                "title": "Error: API call failed.",
                "channelTitle": "Check your API key or quota.",
              },
            },
          ];
        });
      }
    } catch (e) {
      print("Network Error: $e");
      setState(() {
        videos = [
          {
            "snippet": {
              "title": "Error: Network issue.",
              "channelTitle": "Could not connect to YouTube API.",
            },
          },
        ];
      });
    }
  }

  // --- Playback and Cleanup Logic ---

  void _onPlaybackEnded() {
    if (player?.value.playerState == PlayerState.ended) {
      setState(() {
        _isPlayerVisible = false;
      });

      Future.delayed(const Duration(milliseconds: 400), () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (player != null) {
            player!.removeListener(_onPlaybackEnded);
            player!.dispose();
            player = null;
            setState(() {
              currentTrack = null;
            });
          }
        });
      });
    }
  }

  void _scrollToCurrentTrack() {
    if (currentTrack == null || !_scrollController.hasClients) return;

    final videoId = currentTrack!["id"]?["videoId"];

    final indexToScroll = videos.indexWhere((v) {
      return v["id"] != null && v["id"]["videoId"] == videoId;
    });

    if (indexToScroll != -1) {
      const double itemHeight = 70.0;

      final targetOffset = indexToScroll * itemHeight;
      final currentOffset = _scrollController.offset;
      final viewportHeight = _scrollController.position.viewportDimension;

      if (targetOffset < currentOffset ||
          targetOffset > (currentOffset + viewportHeight - 150)) {
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  // ⭐️ Play method made public so it can be passed as a callback
  void play(Map<String, dynamic> video) async {
    final videoId = video["id"]["videoId"];

    final indexToScroll = videos.indexWhere((v) {
      return v["id"] != null && v["id"]["videoId"] == videoId;
    });

    if (indexToScroll != -1 && _scrollController.hasClients) {
      const double itemHeight = 70.0;
      _scrollController.animateTo(
        indexToScroll * itemHeight,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    player?.dispose();
    player = null;

    setState(() {
      currentTrack = null;
      _isPlayerVisible = false;
    });

    await Future.delayed(const Duration(milliseconds: 100));

    player = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: false,
        mute: false,
        loop: false,
        hideControls: true,
      ),
    );

    player!.addListener(_onPlaybackEnded);

    setState(() {
      currentTrack = video;
      _isPlayerVisible = true;
    });
  }

  @override
  void dispose() {
    ctrl.dispose();
    _scrollController.dispose();
    if (player != null) {
      player!.removeListener(_onPlaybackEnded);
    }
    player?.dispose();
    super.dispose();
  }

  // --- UI Methods ---

  Widget _buildSearchResults() {
    final String? playingVideoId = currentTrack?["id"]?["videoId"];

    return Expanded(
      child: ListView.builder(
        controller: _scrollController,
        itemCount: videos.length,
        itemBuilder: (context, i) {
          final v = videos[i];
          final snip = v["snippet"];

          final hasVideoId = v["id"] != null && v["id"]["videoId"] != null;
          final videoId = hasVideoId ? v["id"]["videoId"] : null;

          final isPlaying = videoId != null && videoId == playingVideoId;

          // Conditional Styling
          final bgColor = isPlaying
              ? Colors.blue.withOpacity(0.2)
              : const Color(0xFF1C1C1C);
          final trailingIcon = isPlaying ? Icons.equalizer : Icons.play_arrow;
          final iconColor = isPlaying ? Colors.blue : Colors.white70;

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8.0),
              border: isPlaying
                  ? Border.all(color: Colors.blue, width: 1.5)
                  : null,
            ),
            child: ListTile(
              leading: hasVideoId
                  ? ClipOval(
                      // Circular thumbnail
                      child: Image.network(
                        snip["thumbnails"]["default"]["url"],
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                      ),
                    )
                  : const Icon(Icons.warning, color: Colors.amber),
              title: Text(
                snip["title"],
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              // GestureDetector wrapped subtitle for channel click
              subtitle: GestureDetector(
                onTap: () {
                  if (snip["channelId"] != null &&
                      snip["channelTitle"] != null) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ChannelPage(
                          channelId: snip["channelId"],
                          channelTitle: snip["channelTitle"],
                          onVideoTap: play,
                          // ⭐️ FIX: Pass the public play method as the callback!
                        ),
                      ),
                    );
                  }
                },
                child: Text(
                  snip["channelTitle"] ?? "Unknown Channel",
                  style: const TextStyle(
                    color: Colors.blue, // Highlight as clickable
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.blue,
                    fontSize: 12,
                  ),
                ),
              ),
              onTap: hasVideoId ? () => play(v) : null,
              trailing: hasVideoId
                  ? Icon(trailingIcon, color: iconColor)
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildLargePlayer() {
    if (player == null) return const SizedBox.shrink();

    final snip = currentTrack?["snippet"];
    final thumbnailUrl = snip?["thumbnails"]?["default"]?["url"] ?? '';

    return ValueListenableBuilder<YoutubePlayerValue>(
      valueListenable: player!,
      builder: (context, value, child) {
        final isReady = value.playerState != PlayerState.unknown;
        final isPlaying = isReady && value.isPlaying;
        final isLoading =
            value.playerState == PlayerState.buffering ||
            value.playerState == PlayerState.unknown;

        final position = value.position;
        final duration = value.metaData.duration;

        void skip(bool forward) {
          if (!isReady) return;
          final newPosition = forward
              ? position + const Duration(seconds: 5)
              : position - const Duration(seconds: 5);

          final clampedPosition = newPosition < Duration.zero
              ? Duration.zero
              : (newPosition > duration ? duration : newPosition);

          player!.seekTo(clampedPosition);
          _scrollToCurrentTrack();
        }

        void togglePlayPause() {
          if (isPlaying) {
            player!.pause();
          } else {
            player!.play();
          }
          _scrollToCurrentTrack();
        }

        // --- Animated Slide and Fade ---
        return AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          height: _isPlayerVisible ? 150.0 : 0.0,

          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: _isPlayerVisible ? 1.0 : 0.0,

            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16.0),
                topRight: Radius.circular(16.0),
              ),
              child: Container(
                height: 150,
                padding: const EdgeInsets.all(12.0),
                decoration: const BoxDecoration(
                  color: Color(0xFF282828),
                  boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10)],
                ),
                child: Column(
                  children: [
                    // 1. Slider and Duration Row
                    Row(
                      children: [
                        Text(
                          formatDuration(position),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6.0,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 10.0,
                              ),
                              trackHeight: 2.0,
                            ),
                            child: Slider(
                              min: 0.0,
                              max: duration.inSeconds.toDouble() == 0
                                  ? 1.0
                                  : duration.inSeconds.toDouble(),
                              value: position.inSeconds.toDouble().clamp(
                                0.0,
                                duration.inSeconds.toDouble(),
                              ),
                              activeColor: Colors.blue,
                              inactiveColor: Colors.grey.withOpacity(0.3),
                              onChanged: (double newValue) {
                                if (isReady && duration.inSeconds > 0) {
                                  player!.seekTo(
                                    Duration(seconds: newValue.toInt()),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                        Text(
                          formatDuration(duration),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 2. Control Row
                    Row(
                      children: [
                        // Thumbnail
                        ClipOval(
                          child: Image.network(
                            thumbnailUrl,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Title/Subtitle
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                snip?["title"] ?? "Loading...",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                snip?["channelTitle"] ?? "",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // --- REWIND BUTTON (InkWell with Scroll) ---
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: isReady && !isLoading
                                ? () => skip(false)
                                : null,
                            child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(
                                Icons.replay_5,
                                color: Colors.white70,
                                size: 30,
                              ),
                            ),
                          ),
                        ),

                        // --- PLAY/PAUSE/LOADING BUTTON (InkWell with Scroll) ---
                        SizedBox(
                          width: 50,
                          height: 50,
                          child: isLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3.0,
                                  ),
                                )
                              : Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: !isReady || isLoading
                                        ? null
                                        : togglePlayPause,
                                    child: Padding(
                                      padding: const EdgeInsets.all(0.0),
                                      child: Icon(
                                        isPlaying
                                            ? Icons.pause_circle_filled
                                            : Icons.play_circle_filled,
                                        color: Colors.white,
                                        size: 50,
                                      ),
                                    ),
                                  ),
                                ),
                        ),

                        // --- SKIP BUTTON (InkWell with Scroll) ---
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: isReady && !isLoading
                                ? () => skip(true)
                                : null,
                            child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(
                                Icons.forward_5,
                                color: Colors.white70,
                                size: 30,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // --- BUILD METHOD ---

  @override
  Widget build(BuildContext context) {
    final playerHeight = _isPlayerVisible ? 150.0 : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "🎶 YouTube MP3 Player",
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: false,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                // Search Bar
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: TextField(
                    controller: ctrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Search track or artist...",
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1C1C1C),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30.0),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search, color: Colors.white70),
                        onPressed: () => search(ctrl.text),
                      ),
                    ),
                    onSubmitted: (value) => search(value),
                  ),
                ),

                // HIDDEN YOUTUBE PLAYER
                if (player != null && currentTrack != null)
                  SizedBox(
                    height: 0,
                    width: 0,
                    child: YoutubePlayer(
                      controller: player!,
                      onReady: () {
                        player!.play();
                        print(
                          "Player is now READY and auto-playing in the background.",
                        );
                      },
                    ),
                  ),

                // Search Results List (Padded at the bottom by playerHeight)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: playerHeight),
                    child: _buildSearchResults(),
                  ),
                ),
              ],
            ),
          ),

          // 2. Player Drawer/Overlay (Anchored to the Bottom)
          if (player != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildLargePlayer(),
            ),
        ],
      ),
    );
  }
}
