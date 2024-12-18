# Media Player Plugin

A Flutter plugin for playing media files on Android and iOS platforms with modern features.

## Features

- Play audio files from local storage or network URLs
- Background playback support
- Media controls in notification/control center
- Lock screen controls
- Playlist management
- Audio focus handling
- Third-party app control support

### Android Features
- Based on Media3 (ExoPlayer3)
- MediaSession3 support
- Modern notification with media controls
- Background playback service

### iOS Features
- Based on AVFoundation
- Control center integration
- Lock screen controls
- Status bar controls

## Getting Started

### Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  media_player: ^0.0.1
```

### Android Setup

Add the following permissions to your Android Manifest (`android/app/src/main/AndroidManifest.xml`):

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
```

### iOS Setup

Add the following to your `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

## Usage

### Basic Usage

```dart
import 'package:media_player/media_player.dart';

// Create player instance
final player = MediaPlayer();

// Initialize
await player.initialize();

// Create playlist
final playlist = [
  MediaItem(
    id: '1',
    title: 'Song Title',
    artist: 'Artist Name',
    album: 'Album Name',
    duration: Duration(minutes: 3, seconds: 30),
    artworkUrl: 'https://example.com/artwork.jpg',
  ),
];

// Set playlist
await player.setPlaylist(playlist);

// Basic controls
await player.play();
await player.pause();
await player.stop();
await player.seekTo(Duration(seconds: 30));
await player.skipToNext();
await player.skipToPrevious();
await player.setVolume(0.5);

// Listen to events
player.playbackStateStream.listen((state) {
  print('Playback state: $state');
});

player.mediaItemStream.listen((item) {
  print('Current item: ${item?.title}');
});

player.positionStream.listen((position) {
  print('Current position: $position');
});

player.errorStream.listen((error) {
  print('Error: $error');
});
```

### Advanced Usage

See the example app for a complete implementation including:
- UI controls
- Progress bar
- Playlist management
- Error handling

## Contributing

Feel free to contribute to this project.

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create new Pull Request

