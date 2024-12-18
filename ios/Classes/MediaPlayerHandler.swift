import Flutter
import Foundation
import AVFoundation
import MediaPlayer

class MediaPlayerHandler: NSObject {
    private var player: AVPlayer
    private var playerItems: [AVPlayerItem] = []
    private var currentIndex: Int = 0
    private var playlist: [[String: Any]] = []
    private var artworkCache: [String: MPMediaItemArtwork] = [:]
    
    private var eventSink: FlutterEventSink?
    
    override init() {
        player = AVPlayer()
        super.init()
        
        setupAudioSession()
        setupRemoteTransportControls()
        setupNotifications()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInterruption),
                name: AVAudioSession.interruptionNotification,
                object: nil
            )
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRouteChange),
                name: AVAudioSession.routeChangeNotification,
                object: nil
            )
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            pause()
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                play()
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            pause()
        default:
            break
        }
    }
    
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.skipToNext()
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.skipToPrevious()
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                self?.seekTo(position: event.positionTime)
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackStateChanged),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        
        player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 1),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            self.updateNowPlayingInfo()
            
            let position = Int(time.seconds * 1000)
            self.eventSink?(["type": "positionChanged", "data": position])
        }
    }
    
    @objc private func handlePlaybackStateChanged() {
        if currentIndex < playlist.count - 1 {
            skipToNext()
        } else {
            eventSink?(["type": "playbackStateChanged", "data": "completed"])
        }
    }
    
    private func updateNowPlayingInfo() {
        guard currentIndex < playlist.count else { return }
        
        let currentItem = playlist[currentIndex]
        var nowPlayingInfo = [String: Any]()
        
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentItem["title"] as? String
        nowPlayingInfo[MPMediaItemPropertyArtist] = currentItem["artist"] as? String
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = currentItem["album"] as? String
        
        if let duration = player.currentItem?.duration.seconds, !duration.isNaN {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        
        if let artworkUrlString = currentItem["artworkUrl"] as? String {
            if let cachedArtwork = artworkCache[artworkUrlString] {
                nowPlayingInfo[MPMediaItemPropertyArtwork] = cachedArtwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            } else if let artworkUrl = URL(string: artworkUrlString) {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                
                loadArtwork(from: artworkUrl) { [weak self] image in
                    guard let self = self,
                          let image = image else { return }
                    
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    self.artworkCache[artworkUrlString] = artwork
                    
                    if self.currentIndex < self.playlist.count,
                       let currentArtworkUrl = self.playlist[self.currentIndex]["artworkUrl"] as? String,
                       currentArtworkUrl == artworkUrlString {
                        var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        updatedInfo[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                    }
                }
            }
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
    }
    
    private func loadArtwork(from url: URL, completion: @escaping (UIImage?) -> Void) {
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let response = response as? HTTPURLResponse,
                  error == nil,
                  response.statusCode == 200,
                  let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let maxSize: CGFloat = 1024
            var finalImage = image
            
            if image.size.width > maxSize || image.size.height > maxSize {
                let scale = maxSize / max(image.size.width, image.size.height)
                let newSize = CGSize(width: image.size.width * scale,
                                   height: image.size.height * scale)
                
                UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
                image.draw(in: CGRect(origin: .zero, size: newSize))
                if let resized = UIGraphicsGetImageFromCurrentImageContext() {
                    finalImage = resized
                }
                UIGraphicsEndImageContext()
            }
            
            DispatchQueue.main.async {
                completion(finalImage)
            }
        }
        task.resume()
    }
    
    // MARK: - Public Methods
    
    func setEventSink(_ sink: @escaping FlutterEventSink) {
        eventSink = sink
    }
    
    func setPlaylist(_ items: [[String: Any]]) {
        artworkCache.removeAll()
        
        playlist = items
        playerItems = items.compactMap { item in
            guard let urlString = item["url"] as? String,
                  let url = URL(string: urlString) else { return nil }
            return AVPlayerItem(url: url)
        }
        
        guard !playerItems.isEmpty else { return }
        
        currentIndex = 0
        player.replaceCurrentItem(with: playerItems[currentIndex])
        updateNowPlayingInfo()
        
        let playlistData = items.map { item -> [String: Any] in
            var mappedItem = [String: Any]()
            mappedItem["id"] = item["id"]
            mappedItem["title"] = item["title"]
            mappedItem["artist"] = item["artist"]
            mappedItem["album"] = item["album"]
            mappedItem["duration"] = item["duration"]
            mappedItem["artworkUrl"] = item["artworkUrl"]
            mappedItem["url"] = item["url"]
            return mappedItem
        }
        eventSink?(["type": "playlistChanged", "data": playlistData])
        
        for item in items {
            if let artworkUrlString = item["artworkUrl"] as? String,
               let artworkUrl = URL(string: artworkUrlString),
               artworkCache[artworkUrlString] == nil {
                loadArtwork(from: artworkUrl) { [weak self] image in
                    guard let self = self,
                          let image = image else { return }
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    self.artworkCache[artworkUrlString] = artwork
                }
            }
        }
    }
    
    func play() {
        player.play()
        updateNowPlayingInfo()
        eventSink?(["type": "playbackStateChanged", "data": "playing"])
    }
    
    func pause() {
        player.pause()
        updateNowPlayingInfo()
        eventSink?(["type": "playbackStateChanged", "data": "paused"])
    }
    
    func stop() {
        player.pause()
        player.seek(to: .zero)
        eventSink?(["type": "playbackStateChanged", "data": "none"])
    }
    
    func seekTo(position: TimeInterval) {
        let time = CMTime(seconds: position, preferredTimescale: 1000)
        player.seek(to: time)
    }
    
    func skipToNext() {
        guard currentIndex < playerItems.count - 1 else { return }
        
        currentIndex += 1
        player.replaceCurrentItem(with: playerItems[currentIndex])
        play()
        
        if let currentItem = playlist[safe: currentIndex] {
            var mappedItem = [String: Any]()
            mappedItem["id"] = currentItem["id"]
            mappedItem["title"] = currentItem["title"]
            mappedItem["artist"] = currentItem["artist"]
            mappedItem["album"] = currentItem["album"]
            mappedItem["duration"] = currentItem["duration"]
            mappedItem["artworkUrl"] = currentItem["artworkUrl"]
            mappedItem["url"] = currentItem["url"]
            eventSink?(["type": "mediaItemChanged", "data": mappedItem])
        }
    }
    
    func skipToPrevious() {
        guard currentIndex > 0 else { return }
        
        currentIndex -= 1
        player.replaceCurrentItem(with: playerItems[currentIndex])
        play()
        
        if let currentItem = playlist[safe: currentIndex] {
            var mappedItem = [String: Any]()
            mappedItem["id"] = currentItem["id"]
            mappedItem["title"] = currentItem["title"]
            mappedItem["artist"] = currentItem["artist"]
            mappedItem["album"] = currentItem["album"]
            mappedItem["duration"] = currentItem["duration"]
            mappedItem["artworkUrl"] = currentItem["artworkUrl"]
            mappedItem["url"] = currentItem["url"]
            eventSink?(["type": "mediaItemChanged", "data": mappedItem])
        }
    }
    
    func setVolume(_ volume: Float) {
        player.volume = volume
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
} 