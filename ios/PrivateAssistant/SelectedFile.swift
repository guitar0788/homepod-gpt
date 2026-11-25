import Foundation

enum SelectedFile {
    static func preview(_ url:URL) async -> String {
        await Task.detached(priority:.userInitiated) {
            let access=url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            var coordinationError:NSError?
            var result="暂时无法读取所选文件。"
            NSFileCoordinator().coordinate(readingItemAt:url,options:[],error:&coordinationError) { file in
                do {
                    let handle=try FileHandle(forReadingFrom:file)
                    defer { try? handle.close() }
                    let data=try handle.read(upToCount:8192) ?? Data()
                    guard let text=String(data:data,encoding:.utf8) else { result="仅支持 UTF-8 文本预览。"; return }
                    result="本机预览：\(file.lastPathComponent)\n" + String(text.prefix(1200)) + (text.count > 1200 || data.count == 8192 ? "\n（内容已截断）" : "")
                } catch { result="文件读取失败，可能尚未从 iCloud 下载。" }
            }
            return coordinationError == nil ? result : "文件协调失败，可能尚未下载。"
        }.value
    }
}
