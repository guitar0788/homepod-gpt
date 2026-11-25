import Foundation
import MusicKit
import AVKit
import SwiftUI

enum HomeMusic {
    @MainActor static func authorize() async -> String {
        let status = await MusicAuthorization.request()
        return status == .authorized ? "音乐访问已授权。" : "尚未获得音乐访问权限。"
    }

    @MainActor static func reply(_ text: String) async -> String? {
        let scene: String? = {
            guard text.contains("音乐") || text.contains("歌") else { return nil }
            guard ["播放","放点","放些","放一","来点","来些","我想听","想听","听点","听些"].contains(where: { text.contains($0) }) else { return nil }
            if ["睡前","睡觉","助眠","入睡"].contains(where: { text.contains($0) }) { return "sleep piano" }
            if ["放松","舒缓","轻松","安静"].contains(where: { text.contains($0) }) { return "relaxing acoustic instrumental" }
            if ["运动","健身","跑步"].contains(where: { text.contains($0) }) { return "workout dance pop" }
            if ["学习","工作","专注","阅读"].contains(where: { text.contains($0) }) { return "focus instrumental" }
            return nil
        }()
        let pause = ["暂停音乐","暂停播放","暂停","停止播放","停止音乐"]
        let next = ["下一首","切歌","换一首"]
        let previous = ["上一首"]
        let resume = ["继续播放","继续音乐","恢复播放"]
        var term: String?
        for prefix in ["帮我播放","给我播放","我想听","播放","放一首","放首","来一首"] {
            if text.hasPrefix(prefix) {
                term = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        let generic = ["听音乐","放音乐","播放音乐","播放歌曲","放首歌"]
        guard pause.contains(text) || next.contains(text) || previous.contains(text) ||
              resume.contains(text) || generic.contains(text) || term != nil || scene != nil else { return nil }
        guard MusicAuthorization.currentStatus == .authorized else {
            return "请先在助手 App 中授权音乐访问。"
        }
        let player = SystemMusicPlayer.shared
        do {
            if pause.contains(text) { player.pause(); return "已请求暂停音乐。" }
            if next.contains(text) { try await player.skipToNextEntry(); return "已切换下一首。" }
            if previous.contains(text) { try await player.skipToPreviousEntry(); return "已切换上一首。" }
            if resume.contains(text) || generic.contains(text) {
                try await player.play()
                return "已请求继续播放当前音乐队列。"
            }
            guard let query = scene ?? term, !query.isEmpty, query.count <= 100 else { return "你想听哪一首歌或哪位歌手？" }
            var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
            request.limit = scene == nil ? 5 : 12
            let response = try await request.response()
            guard let song = response.songs.first else { return "没有找到符合要求的歌曲。" }
            let songs = scene == nil ? [song] : Array(response.songs.prefix(8))
            player.queue = SystemMusicPlayer.Queue(for: songs)
            try await player.play()
            if scene != nil {
                return "已请求播放适合这个场景的搜索结果，共\(songs.count)首，从《\(song.title)》开始。声音输出由系统当前路由决定。"
            }
            return "正在播放\(song.artistName)的《\(song.title)》。实际声音输出由系统当前音频路由决定。"
        } catch {
            return "音乐操作未成功。请检查音乐授权、现有订阅或当前播放队列。"
        }
    }
}

struct HomeAudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        AVRoutePickerView(frame: .zero)
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
