import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class MiniPlayerWidget extends StatefulWidget {
  final YoutubePlayerController controller; // The actual player controller
  final Map<String, dynamic> video;        // The metadata of the current track
  final VoidCallback onPlayerClose;        // Callback to notify parent to hide the player

  const MiniPlayerWidget({
    super.key,
    required this.controller,
    required this.video,
    required this.onPlayerClose,
  });

  @override
  State<MiniPlayerWidget> createState() => _MiniPlayerWidgetState();
}

class _MiniPlayerWidgetState extends State<MiniPlayerWidget> {
  late VoidCallback listener;
  
  @override
  void initState() {
    super.initState();
    // ⭐️ Attach a listener to the controller to update the UI (play/pause icon)
    listener = () {
      if (mounted) {
        setState(() {});
      }
    };
    widget.controller.addListener(listener);
  }

  @override
  void dispose() {
    widget.controller.removeListener(listener);
    super.dispose();
  }

  // Helper to safely get the video title
  String get _videoTitle {
    return widget.video["snippet"]?["title"] ?? "Unknown Track";
  }
  
  // Helper to safely get the channel title
  String get _channelTitle {
    return widget.video["snippet"]?["channelTitle"] ?? "Unknown Channel";
  }

  // Toggles the play/pause state
  void _togglePlayPause() {
    if (widget.controller.value.playerState == PlayerState.playing) {
      widget.controller.pause();
    } else {
      widget.controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check the current state of the YouTube player
    final isPlaying = widget.controller.value.playerState == PlayerState.playing;
    
    // We need the hidden YouTubePlayer widget to keep the audio stream active.
    // It's placed in an invisible box within the Stack of the parent widget (main.dart)
    // to ensure it doesn't interrupt the rest of the UI.
    
    return Container(
      height: 60.0, // Standard mini-player height
      color: const Color(0xFF1E1E1E), // Dark background color
      child: Column(
        children: [
          // ⭐️ Progress Bar (Optional, but good for UX)
          // You'll need to use the YoutubePlayerValue or a StreamBuilder 
          // for accurate, live progress, but for simplicity, we use a basic divider
          // as a visual separator for the player area.
          const Divider(height: 1, color: Colors.blueAccent), 
          
          Row(
            children: [
              // 1. Thumbnail
              SizedBox(
                width: 60.0,
                height: 59.0, // Matches container height minus divider
                child: Image.network(
                  widget.video["snippet"]?["thumbnails"]?["default"]?["url"] ?? "",
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.grey,
                    child: const Icon(Icons.music_note, color: Colors.white70),
                  ),
                ),
              ),
              
              const SizedBox(width: 8.0),

              // 2. Title and Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _videoTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.0,
                      ),
                    ),
                    Text(
                      _channelTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12.0,
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Play/Pause Button
              IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: _togglePlayPause,
              ),

              // 4. Close Button
              IconButton(
                icon: const Icon(
                  Icons.close,
                  color: Colors.white,
                ),
                onPressed: () {
                  // Stop the video and notify the parent to hide the widget
                  widget.controller.pause();
                  widget.onPlayerClose();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}