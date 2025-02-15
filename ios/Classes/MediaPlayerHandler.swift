import Flutter
import Foundation
import AVFoundation
import MediaPlayer
import AVKit

class MediaPlayerHandler: NSObject, FlutterStreamHandler {
    static let shared = MediaPlayerHandler()
    
    let player: AVPlayer
    private var playerLayer: AVPlayerLayer?
    private var playerItems: [AVPlayerItem] = []
    private var currentIndex: Int = 0
    private var playlist: [[String: Any]] = []
    private var artworkCache: [String: MPMediaItemArtwork] = [:]
    private var playMode: PlayMode = .all // 默认列表模式
    private var playHistory: [Int] = [] // 用于记录播放历史，支持随机模式下的上一曲功能
    private var isLoggingEnabled: Bool = false
    
    private var eventSink: FlutterEventSink?
    private var pipController: AVPictureInPictureController?
    
    var count: Int {
        return playlist.count
    }
    
    // 播放模式枚举
    enum PlayMode: String {
        case all    // 列表循环
        case one    // 单曲循环
        case shuffle // 随机播放
    }
    
    override init() {
        player = AVPlayer()
        super.init()
        
        // 创建 playerLayer
        playerLayer = AVPlayerLayer(player: player)
        
        // 设置音频会话
        setupAudioSession()
        
        // 启用后台播放
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(true)
            // 设置播放器在后台继续播放
            player.automaticallyWaitsToMinimizeStalling = false
            player.playImmediately(atRate: 1.0)
        } catch {
            print("Failed to set audio session active: \(error)")
        }
        
        // 监听音频会话中断
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        // 监听音频路由变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        setupRemoteTransportControls()
        setupNotifications()
        setupPictureInPicture()
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
            let audioSession = AVAudioSession.sharedInstance()
            
            // 设置类别和选项
            try audioSession.setCategory(
                .playback,
                mode: .moviePlayback,  // 使用 moviePlayback 模式以支持视频播放
                options: [
                    .allowAirPlay,
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .duckOthers,
                    .mixWithOthers  // 允许与其他音频混合
                ]
            )
            
            // 设置活跃状态
            try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
            
            print("Audio session setup successful")
        } catch {
            print("Failed to setup audio session: \(error)")
            eventSink?(["type": "error", "data": "Failed to setup audio session: \(error.localizedDescription)"])
        }
    }
    
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // 音频被中断（如来电）
            pause()
        case .ended:
            // 中断结束
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if options.contains(.shouldResume) {
                play()
            }
            
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
        // 音频设备断开连接（如拔出耳机）
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
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 1000),
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
        // // 检查当前媒体项是否为视频
        // let isVideo = isCurrentItemVideo()
        // // 检查是否处于画中画模式
        // let isInPiPMode = pipController?.isPictureInPictureActive ?? false
        // // 如果在画中画模式下，退出画中画
        // if isInPiPMode {
        //     pipController?.stopPictureInPicture()
        // }
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
            
      
            
        case .one:
            // 单曲循环：重新从播放当前歌曲
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

    // 添加辅助方法来检查当前媒体项是否为视频
    private func isCurrentItemVideo() -> Bool {
        guard let currentItem = player.currentItem,
              let asset = currentItem.asset as? AVURLAsset else {
            return false
        }
        
        // 使用可选绑定来处理 tracks
        if let videoTracks = try? asset.tracks(withMediaType: .video),
           !videoTracks.isEmpty {
            return true
        }
        
        return false
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
        let isPlaying = player.timeControlStatus == .playing
        player.pause()
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
        // 恢复播放状态
        if isPlaying {
            player.play()
        }
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
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            player.play()
            updateNowPlayingInfo()
            eventSink?(["type": "playbackStateChanged", "data": "playing"])
        } catch {
            print("Failed to activate audio session: \(error)")
        }
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
        // 先临时变量保存当前isPlaying状态  
        let isPlaying = player.timeControlStatus == .playing
        player.pause()
        player.seek(to: time)
        // 恢复播放状态
        if isPlaying {
            player.play()
        }
    }
    
    private func updateRemoteCommandsState() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        //  始终启用所有按钮
            commandCenter.nextTrackCommand.isEnabled = true
            commandCenter.previousTrackCommand.isEnabled = true
    }
    
    func skipToNext() {
        switch playMode {
        case .shuffle:
            // 如果播放列表只有一首歌或为空，则直接返回，不做任何操作
            if playlist.count <= 1 {
                return
            }

            // 将当前播放的歌曲索引添加到播放历史中
            playHistory.append(currentIndex)

            // 随机选择下一首要播放的歌曲（确保不与当前播放的歌曲相同）
            var nextIndex: Int
            repeat {
                nextIndex = Int.random(in: 0..<playlist.count)
            } while nextIndex == currentIndex

            // 更新当前播放的索引
            currentIndex = nextIndex
            
        case .all, .one:
            // 如果当前播放的歌曲不是列表中的最后一首
            if currentIndex < playerItems.count - 1 {
                // 播放下一首歌曲
                currentIndex += 1
            } else { // 如果当前播放的是最后一首歌曲，则从头开始
                currentIndex = 0
            }
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
                // 如果没有历史记录，则使用上一首
                if currentIndex > 0 {
                    currentIndex -= 1
                } else {
                    currentIndex = playerItems.count - 1
                    // 直接跳出,避免执行 currentIndex -= 1
                    break
                
                }
            }
            
        case .all, .one:
            // 如果当前不是第一首歌曲
            if currentIndex > 0 {
                // 播放上一首歌曲
                currentIndex -= 1
            } else { // 如果当前是第一首歌曲，则跳到最后一首
                currentIndex = playerItems.count - 1
            }
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
            
            // 如果插入位置在当前播放项之前当前位置
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

    func setSpeed(_ speed: Double) {
        player.rate = Float(speed)
        eventSink?(["type": "speedChanged", "data": speed])
    }
    
    deinit {
        // 移除所有观察者
        player.removeObserver(self, forKeyPath: "timeControlStatus")
        player.removeObserver(self, forKeyPath: "currentItem.loadedTimeRanges")
        NotificationCenter.default.removeObserver(self)
        
        // 停用音频会话
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
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

        // 通知flutter端，当前媒体项变化
        if let currentItem = playlist[safe: currentIndex] {
            eventSink?(["type": "mediaItemChanged", "data": createMediaItemMap(from: currentItem)])
        }
        // 通知flutter端，当前媒体项时长变化
        if let duration = playerItem.asset.duration.seconds.isNaN ? nil : playerItem.asset.duration.seconds {
            eventSink?(["type": "durationChanged", "data": Int(duration * 1000)])
        }
    }
    
    private func setupPictureInPicture() {
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let playerLayer = self.playerLayer else {
            return
        }
        
        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.delegate = self
    }
    
    // 提供开始/停止画中画的方法
    func startPictureInPicture() {
        pipController?.startPictureInPicture()
    }
    
    func stopPictureInPicture() {
        pipController?.stopPictureInPicture()
    }
    
    // 获取 playerLayer 的访问器方法
    func getPlayerLayer() -> AVPlayerLayer? {
        return playerLayer
    }
    
    // 添加视图管理方法
    func attachPlayerLayer() -> AVPlayerLayer {
        if playerLayer == nil {
            playerLayer = AVPlayerLayer(player: player)
            playerLayer?.videoGravity = .resizeAspect
            
            // 重新设置画中画控制器
            setupPictureInPicture()
        }
        return playerLayer!
    }
    
    func detachPlayerLayer() {
        // 如果正在画中画模式，先停止
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
        
        // 清理画中画控制器
        pipController = nil
        
        // 移除播放器图层
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
    }
    
    func updateAt(_ index: Int, mediaItem: [String: Any]) {
        guard index >= 0 && index < playlist.count else {
            log("Invalid index for update: \(index)")
            return
        }
        
        // 更新指定索引的媒体项
        playlist[index] = mediaItem
        //如果更新的是当前播放项，则更新当前播放项，并更新当前播放项的时长
        if index == currentIndex {
            // 保留当前位置
            let position = player.currentTime()
            if let item = playerItems[safe: index] {
                player.replaceCurrentItem(with: item)
                // 恢复到之前的位置
                player.seek(to: position)
             
            }
            
        }

        // 发送媒体项变化事件
        eventSink?(["type": "mediaItemChanged", "data": mediaItem])

        // 通知flutter端，当前媒体项变化
        if let currentItem = playlist[safe: currentIndex] {
            eventSink?(["type": "mediaItemChanged", "data": createMediaItemMap(from: currentItem)])
        }

        // 通知flutter端，当前媒体项时长变化
        if let playerItem = playerItems[safe: index],
           let duration = playerItem.asset.duration.seconds.isNaN ? nil : playerItem.asset.duration.seconds {
            eventSink?(["type": "durationChanged", "data": Int(duration * 1000)])
        }

    }
    
    // // 添加安全数组访问扩展
    // private subscript<T>(safe index: Int) -> T? {
    //     guard index >= 0, index < count else { return nil }
    //     return self[index] as? T
    // }
    
    private func log(_ message: String, isError: Bool = false) {
        if isLoggingEnabled {
            let event: [String: Any] = [
                "type": "log",
                "data": [
                    "tag": "MediaPlayerHandler",
                    "message": message,
                    "isError": isError,
                    "timestamp": Date().timeIntervalSince1970 * 1000
                ]
            ]
            eventSink?(event)
        }
    }
    
    func setLoggingEnabled(_ enabled: Bool) {
        isLoggingEnabled = enabled
        log("Logging \(enabled ? "enabled" : "disabled")")
    }
}

// 添加画中画代理
extension MediaPlayerHandler: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        eventSink?(["type": "pipWillStart"])
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        eventSink?(["type": "pipDidStart"])
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        eventSink?(["type": "pipWillStop"])
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        eventSink?(["type": "pipDidStop"])
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("画中画启动失败: \(error)")
        eventSink?(["type": "error", "data": "Failed to start PiP: \(error.localizedDescription)"])
    }
}

// 添加数组安全访问扩展
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
} 