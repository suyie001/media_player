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
        // 监听播放完成
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackStateChanged),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        
        // 监听播放器状态
        player.addObserver(self, forKeyPath: "timeControlStatus", options: [.new], context: nil)
        
        // 监听缓冲状态
        player.addObserver(self, forKeyPath: "currentItem.loadedTimeRanges", options: [.new], context: nil)
        
        // 监听播放位置
        player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 1),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            self.updateNowPlayingInfo()
            
            // 发送播放位置
            let position = Int(time.seconds * 1000)
            self.eventSink?(["type": "positionChanged", "data": position])
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        switch keyPath {
        case "timeControlStatus":
            // 监听播放器状态变化
            if let player = object as? AVPlayer {
                switch player.timeControlStatus {
                case .paused:
                    eventSink?(["type": "playbackStateChanged", "data": "paused"])
                case .playing:
                    eventSink?(["type": "playbackStateChanged", "data": "playing"])
                case .waitingToPlayAtSpecifiedRate:
                    eventSink?(["type": "playbackStateChanged", "data": "loading"])
                @unknown default:
                    break
                }
            }
            
        case "currentItem.loadedTimeRanges":
            // 监听缓冲进度
            if let player = object as? AVPlayer,
               let timeRange = player.currentItem?.loadedTimeRanges.first?.timeRangeValue {
                let bufferedDuration = timeRange.start.seconds + timeRange.duration.seconds
                let totalDuration = player.currentItem?.duration.seconds ?? 0
                let progress = totalDuration > 0 ? bufferedDuration / totalDuration : 0
                
                // 发送缓冲进度
                eventSink?(["type": "bufferChanged", "data": progress])
                
                // 发送缓冲状态
                let isBuffering = progress < 1.0 && player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                eventSink?(["type": "bufferingChanged", "data": isBuffering])
            }
            
        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    @objc private func handlePlaybackStateChanged() {
        // 发送完成事件
        eventSink?(["type": "completed", "data": true])
        
        // 自动播放下一曲
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
            let playerItem = AVPlayerItem(url: url)
            
            // 监听加载状态
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleItemReadyToPlay(_:)),
                name: .AVPlayerItemNewAccessLogEntry,
                object: playerItem
            )
            
            return playerItem
        }
        
        guard !playerItems.isEmpty else { return }
        
        currentIndex = 0
        player.replaceCurrentItem(with: playerItems[currentIndex])
        updateNowPlayingInfo()
        
        // 发送播放列表变化事件
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
        
        // 预加载封面图
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
    
    @objc private func handleItemReadyToPlay(_ notification: Notification) {
        if let playerItem = notification.object as? AVPlayerItem,
           let duration = playerItem.asset.duration.seconds.isNaN ? nil : playerItem.asset.duration.seconds {
            // 发送媒体时长
            eventSink?(["type": "durationChanged", "data": Int(duration * 1000)])
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
        // 移除所有观察者
        player.removeObserver(self, forKeyPath: "timeControlStatus")
        player.removeObserver(self, forKeyPath: "currentItem.loadedTimeRanges")
        NotificationCenter.default.removeObserver(self)
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
} 