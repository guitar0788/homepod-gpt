import Foundation
import Contacts
import Photos
import AppIntents

enum AppleLibrary {
    static func contactAccess() -> Bool {
        let status = CNContactStore.authorizationStatus(for:.contacts)
        if status == .authorized { return true }
        if #available(iOS 18.0,*), status == .limited { return true }
        return false
    }
    static func authorizeContacts() async -> String {
        do {
            let allowed = try await CNContactStore().requestAccess(for:.contacts)
            return allowed || contactAccess() ? "通讯录授权可用，查询范围以系统允许的联系人为准。" : "通讯录未授权。"
        } catch {
            let e = error as NSError
            return "通讯录权限请求失败：\(e.domain)，\(e.code)。"
        }
    }
    static func contacts(_ raw: String, details: Bool = false) async -> String {
        guard contactAccess() else { return "请先在 App 中授权通讯录。" }
        let name = raw.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { return "请输入具体联系人姓名。" }
        return await Task.detached {
            do {
                let keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for:.fullName),CNContactPhoneNumbersKey as CNKeyDescriptor,CNContactEmailAddressesKey as CNKeyDescriptor]
                let matches = try CNContactStore().unifiedContacts(matching:CNContact.predicateForContacts(matchingName:name),keysToFetch:keys)
                guard !matches.isEmpty else { return "授权范围内没有找到匹配联系人。" }
                let records = matches.prefix(5).map { contact -> String in
                    let title = CNContactFormatter.string(from:contact,style:.fullName) ?? "未命名联系人"
                    guard details else { return "\(title)，有\(contact.phoneNumbers.count)个电话号码、\(contact.emailAddresses.count)个邮箱" }
                    let phones = contact.phoneNumbers.prefix(3).map{$0.value.stringValue}.joined(separator:"、")
                    let emails = contact.emailAddresses.prefix(3).map{$0.value as String}.joined(separator:"、")
                    return title + (phones.isEmpty ? "" : "\n电话："+phones) + (emails.isEmpty ? "" : "\n邮箱："+emails)
                }
                return "找到\(matches.count)个联系人（最多显示5个）。\n"+records.joined(separator:"\n")
            } catch { return "通讯录读取失败，请检查权限。" }
        }.value
    }
    static func authorizePhotos() async -> String {
        let status=await PHPhotoLibrary.requestAuthorization(for:.readWrite)
        switch status {
        case .authorized: return "照片资料库已授权。本助手只查询，不修改照片。"
        case .limited: return "已授权部分照片，仅能查询允许访问的项目。"
        default: return "照片资料库未授权。"
        }
    }
    static func photoReport(_ raw:String) async -> String {
        let status=PHPhotoLibrary.authorizationStatus(for:.readWrite)
        guard status == .authorized || status == .limited else { return "请先在 App 中授权照片资料库。" }
        let query=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        let ranges=["今天":0,"昨天":1,"最近七天":6,"最近7天":6,"全部":-1]
        guard let days=ranges[query] else { return "目前支持今天、昨天、最近七天或全部照片统计。" }
        return await Task.detached {
            let calendar=Calendar.current
            let now=Date()
            let today=calendar.startOfDay(for:now)
            let options=PHFetchOptions()
            if days >= 0, let start=calendar.date(byAdding:.day,value:-days,to:today) {
                let end=days == 1 ? today : now
                options.predicate=NSPredicate(format:"creationDate >= %@ AND creationDate < %@",start as NSDate,end as NSDate)
            }
            let images=PHAsset.fetchAssets(with:.image,options:options).count
            let videos=PHAsset.fetchAssets(with:.video,options:options).count
            return "\(query)授权范围内有\(images)张照片、\(videos)段视频。" + (status == .limited ? "仅统计已授权项目。" : "这是设备照片资料库可见的项目数，不代表整个 iCloud 账户。")
        }.value
    }
}

struct AppleLibraryIntent: AppIntent {
    static let title: LocalizedStringResource = "苹果资料查询"
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    @Parameter(title:"查询内容",requestValueDialog:"说出查联系人及姓名，或者今天、昨天、最近七天、全部照片。")
    var query:String
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text=query.trimmingCharacters(in:.whitespacesAndNewlines)
        let result:String
        if text.hasPrefix("查联系人") {
            result=await AppleLibrary.contacts(String(text.dropFirst("查联系人".count)))
        } else if text.hasSuffix("照片") {
            result=await AppleLibrary.photoReport(String(text.dropLast("照片".count)))
        } else { result="支持查联系人姓名，或者按日期统计照片和视频。" }
        return .result(dialog:"\(result)")
    }
}
