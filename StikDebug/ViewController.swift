import SwiftUI
import WebKit
import Foundation
import CommonCrypto

// AES加密工具 主密钥固定：IENNSJFJWKSFJ
struct AESHelper {
    static let keyString = "IENNSJFJWKSFJ"
    static let mainKey = Data(keyString.utf8)
    
    // 默认加密（程序本地存档用）
    static func encrypt(_ str: String) -> String {
        return aesCrypt(text: str, keyData: mainKey, isEncrypt: true)
    }
    static func decrypt(_ base64Str: String) -> String {
        return aesCrypt(text: base64Str, keyData: mainKey, isEncrypt: false)
    }
    
    // 自定义密钥解密（新增解密工具调用）
    static func customDecrypt(base64Str: String, keyStr: String) -> String {
        let kData = Data(keyStr.utf8)
        return aesCrypt(text: base64Str, keyData: kData, isEncrypt: false)
    }
    
    private static func aesCrypt(text: String, keyData: Data, isEncrypt: Bool) -> String {
        let iv = Data(repeating: UInt8(0), count: 16)
        var cryptor: CCCryptorRef?
        let alg = CCAlgorithm(kCCAlgorithmAES128)
        let pad = CCOption(kCCOptionPKCS7Padding)
        let mode = kCCModeCBC
        
        if isEncrypt {
            let rawData = Data(text.utf8)
            CCCryptorCreateWithMode(kCCEncrypt, mode, alg, pad, iv, keyData, nil, 0, nil, nil, 0, &cryptor)
            let up = CCCryptorUpdate(cryptor!, rawData, rawData.count)!
            let fin = CCCryptorFinal(cryptor!)!
            return (up+fin).base64EncodedString()
        } else {
            guard let rawData = Data(base64Encoded: text) else { return "解密失败" }
            CCCryptorCreateWithMode(kCCDecrypt, mode, alg, pad, iv, keyData, nil, 0, nil, nil, 0, &cryptor)
            let up = CCCryptorUpdate(cryptor!, rawData, rawData.count)!
            let fin = CCCryptorFinal(cryptor!)!
            return String(data: up+fin, encoding: .utf8) ?? "解密失败"
        }
    }
}

// 账号结构体，本地加密存档
struct Account: Codable, Identifiable {
    let id = UUID()
    let openid: String
    let seecoon_token: String
    let quid: String
    let refresh_token: String
    let createTime: Date
}

// 全局数据管理器
class DataManager: ObservableObject {
    @Published var accounts: [Account] = []
    let path: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("delta_account.dat")
    
    init() {
        loadAccounts()
    }
    
    func saveAccount(acc: Account) {
        accounts.append(acc)
        let json = try! JSONEncoder().encode(accounts)
        let encryptStr = AESHelper.encrypt(String(data: json, encoding: .utf8)!)
        try! encryptStr.write(to: path, atomically: true, encoding: .utf8)
    }
    
    func loadAccounts() {
        if FileManager.default.fileExists(atPath: path.path) {
            let encryptStr = try! String(contentsOf: path)
            let jsonStr = AESHelper.decrypt(encryptStr)
            let jsonData = jsonStr.data(using: .utf8)!
            accounts = try! JSONDecoder().decode([Account].self, from: jsonData)
        }
    }
    
    func deleteAccount(id: UUID) {
        accounts.removeAll(where: {$0.id == id})
        let json = try! JSONEncoder().encode(accounts)
        let encryptStr = AESHelper.encrypt(String(data: json, encoding: .utf8)!)
        try! encryptStr.write(to: path, atomically: true, encoding: .utf8)
    }
}

// 二维码扫码抓取页面
struct QRLoginView: View {
    @ObservedObject var dm: DataManager
    @State var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.load(URLRequest(url: URL(string:"https://game.seecoon.com/h5/login.html")!))
        return wv
    }()
    
    var body: some View {
        VStack {
            WebViewWrapper(webView: $webView, dm: dm)
                .frame(width: 400, height: 600)
            Text("请使用QQ扫描二维码，在三角洲APP内完成授权，授权后自动抓取长期Token")
                .font(.caption)
        }
    }
}

// 网页拦截器，截取登录回调，抓到永久token
struct WebViewWrapper: NSViewRepresentable {
    @Binding var webView: WKWebView
    var dm: DataManager
    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        return webView
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self, dm: dm) }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebViewWrapper
        let dm: DataManager
        init(parent: WebViewWrapper, dm: DataManager) {
            self.parent = parent
            self.dm = dm
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url?.absoluteString ?? ""
            if url.contains("loginByMobileScan") {
                webView.evaluateJavaScript("JSON.stringify(window.loginResult)") { result, err in
                    if let jsonStr = result as? String, let data = jsonStr.data(using: .utf8) {
                        let dict = try! JSONSerialization.jsonObject(with: data) as! [String:Any]
                        let dataDict = dict["data"] as! [String:Any]
                        let newAcc = Account(
                            openid: dataDict["openid"] as! String,
                            seecoon_token: dataDict["seecoon_token"] as! String,
                            quid: dataDict["quid"] as! String,
                            refresh_token: dataDict["refresh_token"] as! String,
                            createTime: Date()
                        )
                        self.dm.saveAccount(acc: newAcc)
                        webView.load(URLRequest(url: URL(string:"https://game.seecoon.com/h5/login.html")!))
                    }
                }
            }
            decisionHandler(.allow)
        }
    }
}

// Token查看管理器页面
struct TokenListView: View {
    @ObservedObject var dm: DataManager
    var body: some View {
        List(dm.accounts) { acc in
            VStack(alignment: .leading) {
                Text("OpenID：\(acc.openid)")
                Text("Seecoon_Token：\(acc.seecoon_token)")
                    .font(.system(size: 9))
                HStack(spacing:12) {
                    Button("复制Token") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(acc.seecoon_token, forType: .string)
                    }
                    Button("删除账号") {
                        dm.deleteAccount(id: acc.id)
                    }
                }
            }
        }
    }
}

// 新增：密文解密弹窗
struct DecryptWindow: View {
    @State var cipherText: String = ""
    @State var keyText: String = ""
    @State var resultText: String = ""
    var body: some View {
        VStack(spacing:10) {
            TextField("粘贴密文", text: $cipherText)
            TextField("输入解密密钥", text: $keyText)
            Button("开始解密") {
                resultText = AESHelper.customDecrypt(base64Str: cipherText, keyStr: keyText)
            }
            TextEditor(text: $resultText)
                .frame(height:200)
        }
        .padding()
        .frame(width:400,height:350)
    }
}

// Token一键登录页面（加入解密按钮，弹出解密窗口）
struct TokenLoginView: View {
    @State var inputToken: String = ""
    @State var msg: String = ""
    @State var showDecrypt = false
    
    func checkToken() {
        let header: [String:String] = [
            "Authorization":"seecoon_token=\(inputToken)",
            "User-Agent":"SeecoonGame",
            "Content-Type":"application/json"
        ]
        var req = URLRequest(url: URL(string:"https://game.seecoon.com/api/user/checkLogin")!)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = header
        req.httpBody = "{}".data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, res, err in
            guard let d = data, let json = try? JSONSerialization.jsonObject(with: d) as? [String:Any] else {
                DispatchQueue.main.async {
                    msg = "网络错误"
                }
                return
            }
            let ok = (json["data"] as? Bool) ?? false
            DispatchQueue.main.async {
                if ok {
                    msg = "✅ Token有效，可以一键登录"
                } else {
                    msg = "❌ Token已经失效，请重新扫码"
                }
            }
        }.resume()
    }
    func launchGame() {
        let url = URL(string:"seecoon://login?token=\(inputToken)")!
        NSWorkspace.shared.open(url)
    }
    var body: some View {
        VStack(spacing:12) {
            TextField("粘贴你的seecoon_token", text: $inputToken)
                .frame(width:350)
            Button("检测Token有效性", action: checkToken)
            Text(msg)
            Button("唤起三角洲一键登录", action: launchGame)
                .disabled(!msg.contains("✅"))
            
            Button("🔐 密文解密工具") {
                showDecrypt = true
            }
            .sheet(isPresented: $showDecrypt) {
                DecryptWindow()
            }
        }.padding()
    }
}

// 主窗口入口
@main
struct DeltaApp: App {
    @StateObject var dm = DataManager()
    @State var selectTab = 0
    var body: some Scene {
        Window("三角洲行动", id: "main") {
            VStack {
                HStack(spacing:20) {
                    Button("A：二维码抓包"){selectTab=0}
                    Button("B：查看本地Token"){selectTab=1}
                    Button("C：Token快捷登录"){selectTab=2}
                }
                Divider()
                if selectTab == 0 {
                    QRLoginView(dm: dm)
                } else if selectTab == 1 {
                    TokenListView(dm: dm)
                } else {
                    TokenLoginView()
                }
            }
            .padding()
            .frame(width:450,height:650)
        }
    }
}
