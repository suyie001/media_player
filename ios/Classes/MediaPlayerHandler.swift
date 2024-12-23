import Flutter
import Foundation
import AVFoundation
import MediaPlayer

class MediaPlayerHandler: NSObject {
      // 将 player 改为 internal 访问级别
    let player: AVPlayer
    private var playerItems: [AVPlayerItem] = []
    private var currentIndex: Int = 0
    private var playlist: [[String: Any]] = []
    private var artworkCache: [String: MPMediaItemArtwork] = [:]
    private var playMode: PlayMode = .list // 默认列表模式
    private var playHistory: [Int] = [] // 用于记录播放历史，支持随机模式下的上一曲功能
    
    private var eventSink: FlutterEventSink?
    
    // 播放模式枚举
    enum PlayMode: String {
        case all    // 列表循环
        case list   // 列表播放一次
        case one    // 单曲循环
        case shuffle // 随机播放
    }
    
    override init() {
        player = AVPlayer()
        super.init()
        
        setupAudioSession()
        setupRemoteTransportControls()
        setupNotifications()
    }
     // 实现 FlutterStreamHandler 协议
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
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
        
        // 根据不同的播放模式处理播放完成后的行为
        switch playMode {
        case .all:
            // 列表循环：如果是最后一项，则从头开始
            if currentIndex >= playlist.count - 1 {
                currentIndex = 0
                player.replaceCurrentItem(with: playerItems[currentIndex])
                player.seek(to: .zero)
                play()
                if let currentItem = playlist[safe: currentIndex] {
                    eventSink?(["type": "mediaItemChanged", "data": createMediaItemMap(from: currentItem)])
                }
                return
            } else {
                skipToNext()
            }
            
        case .list:
            // 列表播放：如果不是最后一项则播放下一项，是最后一项则停止
            if currentIndex < playlist.count - 1 {
                skipToNext()
            } else {
                eventSink?(["type": "playbackStateChanged", "data": "completed"])
            }
            
        case .one:
            // 单曲循环：重新从头播放当前歌曲
            player.seek(to: .zero)
            play()
            
        case .shuffle:
            // 随机播放：随机选择一首（排除当前播放的）
            if playlist.count > 1 {
                var nextIndex: Int
                repeat {
                    nextIndex = Int.random(in: 0..<playlist.count)
                } while nextIndex == currentIndex
                
                playHistory.append(currentIndex)
                currentIndex = nextIndex
                player.replaceCurrentItem(with: playerItems[currentIndex])
                player.seek(to: .zero)
                play()
                if let currentItem = playlist[safe: currentIndex] {
                    eventSink?(["type": "mediaItemChanged", "data": createMediaItemMap(from: currentItem)])
                }
            }
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
        // 确保从头开始播放
        player.seek(to: .zero)
        updateNowPlayingInfo()
        
        // 发送播放列表变化事件
        let playlistData = playlist.map { createMediaItemMap(from: $0) }
        eventSink?(["type": "playlistChanged", "data": playlistData])
        
        // 发送当前媒体项变化事件
        if let currentItem = playlist[safe: currentIndex] {
            eventSink?(["type": "mediaItemChanged", "data": createMediaItemMap(from: currentItem)])
        }
        
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
        
        // 更新远程控制按钮状态
        updateRemoteCommandsState()
    }
    
    // 添加一个辅助方法来创建媒体项的映射
    private func createMediaItemMap(from item: [String: Any]) -> [String: Any] {
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
    
    private func updateRemoteCommandsState() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        switch playMode {
        case .all:
            // 列表循环模式：始终启用所有按钮，因为可以循环播放
            commandCenter.nextTrackCommand.isEnabled = true
            commandCenter.previousTrackCommand.isEnabled = true
            
        case .list:
            // 列表播放模式：根据当前位置启用/禁用按钮
            commandCenter.nextTrackCommand.isEnabled = currentIndex < playerItems.count - 1
            commandCenter.previousTrackCommand.isEnabled = currentIndex > 0
            
        case .one, .shuffle:
            // 单曲循环和随机播放模式：始终启用所有按钮
            commandCenter.nextTrackCommand.isEnabled = true
            commandCenter.previousTrackCommand.isEnabled = true
        }
    }
    
    func skipToNext() {
        switch playMode {
        case .shuffle:
            guard playlist.count > 1 else { return }
            
            // 记录当前索引到历史
            playHistory.append(currentIndex)
            
            // 随机选择下一首（排除当前播放的）
            var nextIndex: Int
            repeat {
                nextIndex = Int.random(in: 0..<playlist.count)
            } while nextIndex == currentIndex
            
            currentIndex = nextIndex
            
        case .all, .list, .one:
            guard currentIndex < playerItems.count - 1 else {
                if playMode == .all {
                    // 列表循环模式下，从头开始
                    currentIndex = 0
                    // 直接跳出,避免执行 currentIndex += 1
                    break
                } else {
                    return
                }
                 
            }
            currentIndex += 1
        }
        
        player.replaceCurrentItem(with: playerItems[currentIndex])
        player.seek(to: .zero)
        play()
        
        if let currentItem = playlist[safe: currentIndex] {
            eventSink?(["type": "mediaItemChanged", "data": createMediaItemMap(from: currentItem)])
        }
        
        // 更新远程控制按钮状态
        updateRemoteCommandsState()
    }
    
    func skipToPrevious() {
        switch playMode {
        case .shuffle:
            // 从历史记录中获取上一首
            if let previousIndex = playHistory.popLast() {
                currentIndex = previousIndex
            } else {
                // 如果没有历史记录，则保持当前索引
                return
            }
            
        case .all, .list, .one:
            guard currentIndex > 0 else {
                if playMode == .all {
                    // 列表循环模式下，跳到最后一首
                    currentIndex = playerItems.count - 1
                    // 直接跳出,避免执行 currentIndex -= 1
                    break
                } else {
                    return
                }
            }
            currentIndex -= 1
        }
        
        player.replaceCurrentItem(with: playerItems[currentIndex])
        player.seek(to: .zero)
        play()
        
        if let currentItem = playlist[safe: currentIndex] {
            eventSink?(["type": "mediaItemChanged", "data": createMediaItemMap(from: currentItem)])
        }
        
        // 更新远程控制按钮状态
        updateRemoteCommandsState()
    }
    
    func setVolume(_ volume: Float) {
        player.volume = volume
    }
    
    // MARK: - Playlist Operations
    
    func add(_ mediaItem: [String: Any]) {
        playlist.append(mediaItem)
        if let urlString = mediaItem["url"] as? String,
           let url = URL(string: urlString) {
            let playerItem = AVPlayerItem(url: url)
            playerItems.append(playerItem)
            
            // 如果是第一个项目，直接开始播放
            if playlist.count == 1 {
                currentIndex = 0
                player.replaceCurrentItem(with: playerItem)
                // 确保从头开始播放
                player.seek(to: .zero)
                updateNowPlayingInfo()
            }
            
            // 发送播放列表变化事件
            let playlistData = playlist.map { createMediaItemMap(from: $0) }
            eventSink?(["type": "playlistChanged", "data": playlistData])
        }
    }
    
    func removeAt(_ index: Int) {
        guard index >= 0 && index < playlist.count else { return }
        
        playlist.remove(at: index)
        playerItems.remove(at: index)
        
        // 如果移除的是当前播放项
        if index == currentIndex {
            if playlist.isEmpty {
                currentIndex = 0
                player.replaceCurrentItem(with: nil)
            } else {
                currentIndex = min(index, playlist.count - 1)
                player.replaceCurrentItem(with: playerItems[currentIndex])
                updateNowPlayingInfo()
                // 发送当前媒体项变化事件
                if let currentItem = playlist[safe: currentIndex] {
                    eventSink?(["type": "mediaItemChanged", "data": createMediaItemMap(from: currentItem)])
                }
            }
        } else if index < currentIndex {
            currentIndex -= 1
        }
        
        // 发送播放列表变化事件
        let playlistData = playlist.map { createMediaItemMap(from: $0) }
        eventSink?(["type": "playlistChanged", "data": playlistData])
    }
    
    func insertAt(_ index: Int, mediaItem: [String: Any]) {
        guard index >= 0 && index <= playlist.count else { return }
        
        playlist.insert(mediaItem, at: index)
        if let urlString = mediaItem["url"] as? String,
           let url = URL(string: urlString) {
            let playerItem = AVPlayerItem(url: url)
            playerItems.insert(playerItem, at: index)
            
            // 如果插入位置在当前播放项之前或当前位置
            if index <= currentIndex {
                currentIndex += 1
            }
            
            // 如果是第一个项目，直接开始播放
            if playlist.count == 1 {
                currentIndex = 0
                player.replaceCurrentItem(with: playerItem)
                // 确保从头开始播放
                player.seek(to: .zero)
                updateNowPlayingInfo()
            }
            
            // 发送播放列表变化事件
            let playlistData = playlist.map { createMediaItemMap(from: $0) }
            eventSink?(["type": "playlistChanged", "data": playlistData])
        }
    }
    
    func move(_ from: Int, _ to: Int) {
        guard from >= 0 && from < playlist.count && to >= 0 && to < playlist.count else { return }
        
        let mediaItem = playlist.remove(at: from)
        let playerItem = playerItems.remove(at: from)
        
        playlist.insert(mediaItem, at: to)
        playerItems.insert(playerItem, at: to)
        
        // 更新当前索引
        if currentIndex == from {
            currentIndex = to
        } else if from < currentIndex && to >= currentIndex {
            currentIndex -= 1
        } else if from > currentIndex && to <= currentIndex {
            currentIndex += 1
        }
        
        // 发送播放列表变化事件
        let playlistData = playlist.map { createMediaItemMap(from: $0) }
        eventSink?(["type": "playlistChanged", "data": playlistData])
    }
    
    func jumpTo(_ index: Int) {
        guard index >= 0 && index < playlist.count else { return }
        
        currentIndex = index
        player.replaceCurrentItem(with: playerItems[currentIndex])
        // 确保从头开始播放
        player.seek(to: .zero)
        play()
        
        // 发送当前媒体项变化事件
        if let currentItem = playlist[safe: currentIndex] {
            eventSink?(["type": "mediaItemChanged", "data": createMediaItemMap(from: currentItem)])
        }
    }
    
    func setPlayMode(_ mode: String) {
        if let newMode = PlayMode(rawValue: mode) {
            playMode = newMode
            // 切换到随机模式时清空历史记录
            if newMode == .shuffle {
                playHistory.removeAll()
            }
            // 发送播放模式变化事件
            eventSink?(["type": "playModeChanged", "data": mode])
            
            // 更新远程控制按钮状态
            updateRemoteCommandsState()
        }
    }
    
    func getPlayMode() -> String {
        return playMode.rawValue
    }
    
    deinit {
        // 移除所有观察者
        player.removeObserver(self, forKeyPath: "timeControlStatus")
        player.removeObserver(self, forKeyPath: "currentItem.loadedTimeRanges")
        NotificationCenter.default.removeObserver(self)
    }
    
    func updateCurrentUrl(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            eventSink?(["type": "error", "data": "Invalid URL"])
            return
        }
        
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)
        
        // 通知 Flutter 端 URL 已更新
        eventSink?(["type": "urlUpdated"])
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
} 