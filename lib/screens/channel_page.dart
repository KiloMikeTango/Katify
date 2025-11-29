import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_player_flutter/youtube_player_flutter.dart'; // **NEW IMPORT**

class ChannelPage extends StatefulWidget {
  final String channelId;
  final String channelTitle;
  // NOTE: We no longer need onVideoTap as playback is now local.
  final Function(Map<String, dynamic> video) onVideoTap;

  const ChannelPage({
    super.key,
    required this.channelId,
    required this.channelTitle,
    required this.onVideoTap, // Keeping this for compatibility, but not used internally now
  });

  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  List channelVideos = [];
  Map<String, dynamic>? channelProfile;
  bool isLoading = true;
  bool hasError = false;

  // ⭐️ NEW STATE: Player Management
  YoutubePlayerController? _youtubeController;
  Map<String, dynamic>? _currentPlayingVideo;
  bool _isPlayerInit = false;

  // NOTE: This MUST be the same API key as in _YoutubeMusicSearchState
  static const apiKey = "AIzaSyDtFCwWmCYx75yzygjI0x1yjRYfbNx2rss";

  @override
  void initState() {
    super.initState();
    _fetchChannelData();
  }

  // Dispose of the controller when the widget is removed
  @override
  void dispose() {
    _youtubeController?.dispose();
    super.dispose();
  }

  // Helper method to format duration (copied from mini_player_widget.dart)
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds"
        .replaceAll(RegExp(r'^00:'), '');
  }

  // ⭐️ NEW METHOD: Initialize and play a video
  void _playVideo(Map<String, dynamic> video) {
    final videoId = video["id"]?["videoId"];
    if (videoId == null) return;

    // Dispose old controller if exists
    _youtubeController?.dispose();

    // Create a new controller
    _youtubeController = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        disableDragSeek: true,
        loop: false,
        isLive: false,
        forceHD: false,
        enableCaption: false,
      ),
    );

    setState(() {
      _currentPlayingVideo = video;
      _isPlayerInit = true;
    });
  }

  // Helper method to fetch video details (same as before)
  Future<List> _fetchVideoDetails(List searchItems) async {
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

    List finalVideos = [];
    for (var detail in data["items"]) {
      final duration = detail["contentDetails"]["duration"] ?? "";

      // Filter out shorts or very short videos
      if (duration.contains('M') || duration.contains('H')) {
        finalVideos.add({
          "id": {"videoId": detail["id"]},
          "snippet": {
            ...detail["snippet"],
            "channelId": detail["snippet"]["channelId"],
            "channelTitle": detail["snippet"]["channelTitle"],
          },
        });
      }
    }
    return finalVideos;
  }

  // Fetches channel videos and profile info in one go (same as before)
  Future<void> _fetchChannelData() async {
    try {
      final channelUrl = Uri.https(
        "www.googleapis.com",
        "/youtube/v3/channels",
        {
          "part": "snippet,contentDetails",
          "id": widget.channelId,
          "key": apiKey,
        },
      );

      final channelRes = await http.get(channelUrl);
      final channelData = jsonDecode(channelRes.body);

      final profile = channelData["items"].isNotEmpty
          ? channelData["items"][0]
          : null;

      final uploadsPlaylistId =
          profile?["contentDetails"]?["relatedPlaylists"]?["uploads"];

      if (uploadsPlaylistId == null) {
        setState(() {
          isLoading = false;
          hasError = true;
        });
        return;
      }

      final playlistUrl =
          Uri.https("www.googleapis.com", "/youtube/v3/playlistItems", {
            "part": "snippet,contentDetails",
            "playlistId": uploadsPlaylistId,
            "maxResults": "50",
            "key": apiKey,
          });

      final playlistRes = await http.get(playlistUrl);
      final playlistData = jsonDecode(playlistRes.body);

      final videoItems = playlistData["items"]
          .where((item) => item["snippet"]?["resourceId"]?["videoId"] != null)
          .map(
            (item) => ({
              "id": {"videoId": item["snippet"]["resourceId"]["videoId"]},
            }),
          )
          .toList();

      final fullVideos = await _fetchVideoDetails(videoItems);

      setState(() {
        channelProfile = profile;
        channelVideos = fullVideos;
        isLoading = false;
      });
    } catch (e) {
      print("Error fetching channel data: $e");
      setState(() {
        isLoading = false;
        hasError = true;
      });
    }
  }

  // ⭐️ NEW WIDGET: The Compact Player UI
  Widget _buildCompactPlayer(
    YoutubePlayerController controller,
    Map<String, dynamic> video,
  ) {
    final snip = video["snippet"];
    final thumbnailUrl = snip?["thumbnails"]?["default"]?["url"] ?? '';

    return ValueListenableBuilder<YoutubePlayerValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final isReady = value.playerState != PlayerState.unknown;
        final isPlaying = isReady && value.isPlaying;
        final isBuffering = value.playerState == PlayerState.buffering;

        final position = value.position;
        final duration = value.metaData.duration;
        final progress = duration.inSeconds > 0
            ? position.inSeconds / duration.inSeconds
            : 0.0;

        // This is the player video stream container itself
        Widget playerWidget = Container(
          color: Colors.black,
          child: YoutubePlayer(
            controller: controller,
            showVideoProgressIndicator: false,
            progressColors: const ProgressBarColors(
              playedColor: Colors.blue,
              handleColor: Colors.blueAccent,
            ),
            bottomActions: const [],
          ),
        );

        return Column(
          children: [
            // Video Player Area (Can be expanded if needed, currently set to standard height)
            AspectRatio(aspectRatio: 16 / 9, child: playerWidget),

            // Custom Control Bar (Adapted from mini_player_widget)
            Container(
              height: 70, // Height of the control bar
              color: const Color(0xFF282828),
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                children: [
                  // Thumbnail or Icon
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4.0),
                    child: Image.network(
                      thumbnailUrl,
                      width: 45,
                      height: 45,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 45,
                        height: 45,
                        color: Colors.grey,
                        child: const Icon(
                          Icons.music_note,
                          color: Colors.white70,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Title/Subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          snip?["title"] ?? "Unknown Track",
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

                  // Controls
                  isBuffering
                      ? const SizedBox(
                          width: 45,
                          height: 45,
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3.0,
                            ),
                          ),
                        )
                      : IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 30,
                          ),
                          onPressed: () {
                            isPlaying ? controller.pause() : controller.play();
                          },
                        ),

                  // Progress Text
                  Text(
                    '${_formatDuration(position)} / ${_formatDuration(duration)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
            ),

            // Progress Slider Bar (Optional: if you want a separate slider)
            // If you want the slider outside the 70px bar, use this:
            SliderTheme(
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
                    controller.seekTo(Duration(seconds: newValue.toInt()));
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.channelTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (hasError || channelProfile == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.channelTitle)),
        body: const Center(
          child: Text(
            "Could not load channel or videos (Check API key/network).",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    final profileImageUrl =
        channelProfile!["snippet"]?["thumbnails"]?["high"]?["url"] ??
        channelProfile!["snippet"]?["thumbnails"]?["default"]?["url"] ??
        "";

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.channelTitle),
        backgroundColor: Colors.black,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ⭐️ NEW: Insert the Player UI here if a video is playing
          if (_isPlayerInit &&
              _youtubeController != null &&
              _currentPlayingVideo != null)
            _buildCompactPlayer(_youtubeController!, _currentPlayingVideo!),

          // Channel Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                ClipOval(
                  child: Image.network(
                    profileImageUrl,
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.person_pin,
                      size: 70,
                      color: Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.channelTitle,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      "${channelVideos.length} Uploads",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white10),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              "Channel Uploads (Playable)",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
          ),

          // Channel Videos List
          Expanded(
            child: ListView.builder(
              itemCount: channelVideos.length,
              itemBuilder: (context, i) {
                final v = channelVideos[i];
                final snip = v["snippet"];
                final hasVideoId =
                    v["id"] != null && v["id"]["videoId"] != null;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  leading: hasVideoId
                      ? AspectRatio(
                          aspectRatio: 16 / 9,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4.0),
                            child: Image.network(
                              snip["thumbnails"]["medium"]["url"] ??
                                  snip["thumbnails"]["default"]["url"],
                              fit: BoxFit.cover,
                              width: 100,
                              height: 60,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    color: Colors.grey,
                                    child: const Icon(
                                      Icons.music_video,
                                      color: Colors.white70,
                                    ),
                                  ),
                            ),
                          ),
                        )
                      : const Icon(Icons.warning, color: Colors.amber),
                  title: Text(
                    snip["title"],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    snip["channelTitle"],
                    style: const TextStyle(color: Colors.grey),
                  ),
                  onTap: hasVideoId
                      ? () {
                          // ⭐️ ACTION CHANGE: Instead of navigating/calling back, play the video locally.
                          _playVideo(v);
                        }
                      : null,
                  trailing: const Icon(Icons.play_arrow, color: Colors.white70),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}