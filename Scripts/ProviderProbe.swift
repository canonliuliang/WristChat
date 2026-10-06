// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import Foundation

@main
struct ProviderProbe {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let config = try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent(".private/BootstrapCredentials.plist")), format: nil) as! [String:String]
        let client = MiMoClient()
        var checks: [[String:Any]] = []
        for (provider, field) in [(AIProvider.mimo,"MiMoAPIKey"),(.deepSeek,"DeepSeekAPIKey")] {
            do {
                let key = config[field]!
                let models = try await client.models(key:key,provider:provider)
                let model = models.first { $0.id == provider.defaultModelID } ?? models[0]
                var prefs = ChatPreferences(); prefs.answerLength = .medium
                let prompt = "请只回复：腕聊多提供商已连接。"
                let answer = try await collect(client.reply(key:key,model:model.id,messages:ChatContext.messages(history:[],prompt:prompt,preferences:prefs),thinking:false,preferences:prefs,provider:provider))
                checks.append(["provider":provider.name,"model":model.id,"models":models.map(\.id),"complete":answer.done && answer.finish == "stop","containsExpected":answer.text.contains("已连接"),"characters":answer.text.count])
                print("Provider verified: \(provider.name), complete=\(answer.done), characters=\(answer.text.count)")
            } catch { checks.append(["provider":provider.name,"error":error.localizedDescription]); print("Provider check failed: \(provider.name), \(error.localizedDescription)") }
        }
        var prefs = ChatPreferences(); prefs.essayMode = true; prefs.answerLength = .short
        let prompt = "请以《那盏灯》为题写一篇约800字的初三记叙文。素材：初三晚自习后，我因考试失利和父亲闹别扭。父亲总在校门口等我，某晚下雨，我注意到他为了护住我的书包把伞向我倾斜，自己的袖子湿透了。不要新增重大疾病、死亡或获奖情节，用真实的动作和校门灯光表现我从不耐烦到主动靠近父亲的变化。只给标题和正文。"
        do {
            let answer = try await collect(client.reply(key:config["DeepSeekAPIKey"]!,model:"deepseek-flash",messages:ChatContext.messages(history:[],prompt:prompt,preferences:prefs),thinking:false,preferences:prefs,provider:.deepSeek))
            try answer.text.write(to:root.appendingPathComponent("Verification/v1.3-essay-sample.txt"),atomically:true,encoding:.utf8)
            let chinese = answer.text.unicodeScalars.filter { (0x3400...0x9FFF).contains($0.value) }.count
            checks.append(["feature":"essay","complete":answer.done && answer.finish == "stop","characters":answer.text.count,"chineseCharacters":chinese,"containsTitle":answer.text.contains("那盏灯"),"shortAnswerOverride":answer.text.count>650])
            print("Essay verified: complete=\(answer.done), characters=\(answer.text.count), Chinese=\(chinese)")
        } catch { checks.append(["feature":"essay","error":error.localizedDescription]); print("Essay probe failed: \(error.localizedDescription)") }
        let result:[String:Any] = ["checks":checks,"keyLogged":false,"timestamp":ISO8601DateFormatter().string(from:.now)]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("Verification/v1.3-live-providers.json"),options:.atomic)
    }
    static func collect(_ stream:AsyncThrowingStream<StreamEvent,Error>) async throws -> (text:String,done:Bool,finish:String?) {
        var text="", done=false, finish:String?
        for try await event in stream {
            switch event {
            case .text(let part):text += part
            case .done:done=true
            case .finished(let reason):finish=reason
            default:break
            }
        }
        return (text,done,finish)
    }
}
