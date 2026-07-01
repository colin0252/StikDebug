import SwiftUI
import WebKit
import Foundation
import CommonCrypto
import UIKit

// MARK: - AES 加密工具
struct AESHelper {
    static let keyString = "IENNSJFJWKSFJ"
    static let mainKey = Data(keyString.utf8)
    
    static func encrypt(_ str: String) -> String {
        return aesCrypt(text: str, keyData: mainKey, isEncrypt: true)
    }
    static func decrypt(_ base64Str: String) -> String {
        return aesCrypt(text: base64Str, keyData: mainKey, isEncrypt: false)
    }
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

// MARK: - 账号模型
struct Account: Codable, Identifiable {
    let id = UUID()
    let openid: String
    let seecoon_token: String
    let quid: String
    let refresh_token: String
    let createTime: Date
}

// MARK: - 数据管理器
class DataManager: ObservableObject {
    @Published var accounts: [Account] = []
    var docPath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("delta.dat")
    }
    init(){ loadAccounts() }
    func saveAccount(acc:Account){
        accounts.append(acc)
        let json = try! JSONEncoder().encode(accounts)
        let cipher = AESHelper.encrypt(String(data:json,encoding:.utf8)!)
        try! cipher.write(to:docPath,atomically:true,encoding:.utf8)
    }
    func loadAccounts(){
        if FileManager.default.fileExists(atPath: docPath.path){
            let cipher = try! String(contentsOf: docPath)
            let jsonStr = AESHelper.decrypt(cipher)
            let data = jsonStr.data(using:.utf8)!
            accounts = try! JSONDecoder().decode([Account].self,from:data)
        }
    }
    func deleteAccount(id:UUID){
        accounts.removeAll{$0.id == id}
        let json = try! JSONEncoder().encode(accounts)
        let cipher = AESHelper.encrypt(String(data:json,encoding:.utf8)!)
        try! cipher.write(to:docPath,atomically:true,encoding:.utf8)
    }
}

// MARK: - 网页劫持 JS
let hookJS = """
(function(){
    var oldSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function(body){
        var oldOnReady = this.onreadystatechange;
        this.onreadystatechange = ()=>{
            if(this.readyState == 4 && this.responseURL.indexOf("loginByMobileScan")!=-1){
                window.webkit.messageHandlers.tokenHook.postMessage(this.responseText);
            }
            if(oldOnReady) oldOnReady();
        }
        oldSend.call(this,body);
    }
})();
"""

// MARK: - WebView 容器
struct QRWebView: UIViewRepresentable {
    @ObservedObject var dm:DataManager
    var webView = WKWebView(frame: .zero, configuration: {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        let script = WKUserScript(source: hookJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        return config
    }())
    
    func makeUIView(context: Context) -> WKWebView {
        webView.configuration.userContentController.add(context.coordinator, name: "tokenHook")
        webView.load(URLRequest(url: URL(string:"https://game.seecoon.com/h5/login.html")!))
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context){}
    func makeCoordinator() -> Coordinator { Coordinator(parent:self,dm:dm) }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        let parent:QRWebView
        let dm:DataManager
        init(parent:QRWebView,dm:DataManager){
            self.parent = parent
            self.dm = dm
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let jsonStr = message.body as? String, let data = jsonStr.data(using:.utf8) else {return}
            let dict = try! JSONSerialization.jsonObject(with: data) as! [String:Any]
            let dataDict = dict["data"] as! [String:Any]
            let newAcc = Account(
                openid: dataDict["openid"] as! String,
                seecoon_token: dataDict["seecoon_token"] as! String,
                quid: dataDict["quid"] as! String,
                refresh_token: dataDict["refresh_token"] as! String,
                createTime: Date()
            )
            dm.saveAccount(acc:newAcc)
            parent.webView.load(URLRequest(url: URL(string:"https://game.seecoon.com/h5/login.html")!))
        }
    }
}

// MARK: - A 页面：二维码抓包
struct QRView: View {
    @ObservedObject var dm:DataManager
    var body: some View {
        VStack{
            QRWebView(dm:dm)
                .frame(maxWidth:.infinity,maxHeight:.infinity)
            Text("QQ扫码，在三角洲APP授权，自动抓取Token，可无限批量扫号")
                .font(.caption).foregroundColor(.gray)
        }
    }
}

// MARK: - B 页面：Token 列表
struct TokenListView: View {
    @ObservedObject var dm:DataManager
    var body: some View {
        List(dm.accounts){acc in
            VStack(alignment:.leading){
                Text("OpenID:\(acc.openid)")
                Text("Token:\(acc.seecoon_token)")
                    .font(.system(size:8))
                HStack(spacing:10){
                    Button("复制Token"){
                        UIPasteboard.general.string = acc.seecoon_token
                    }
                    Button("删除账号",role:.destructive){
                        dm.deleteAccount(id:acc.id)
                    }
                }
            }
        }
    }
}

// MARK: - 解密弹窗
struct DecryptView: View {
    @State var cipherText = ""
    @State var keyText = ""
    @State var result = ""
    var body: some View {
        VStack(spacing:12){
            TextField("粘贴delta.dat密文全部内容",text:$cipherText)
                .textFieldStyle(.roundedBorder)
            TextField("输入解密密钥",text:$keyText)
                .textFieldStyle(.roundedBorder)
            Button("解密"){
                result = AESHelper.customDecrypt(base64Str: cipherText, keyStr: keyText)
            }
            TextEditor(text:$result)
                .frame(height:220)
        }.padding()
    }
}

// MARK: - C 页面：Token 校验 + 唤起游戏 + 解密按钮
struct LoginView: View {
    @State var inputToken = ""
    @State var tipText = ""
    @State var showDecrypt = false
    
    func checkToken(){
        let header:[String:String] = [
            "Authorization":"seecoon_token=\(inputToken)",
            "User-Agent":"SeecoonGame",
            "Content-Type":"application/json"
        ]
        var req = URLRequest(url:URL(string:"https://game.seecoon.com/api/user/checkLogin")!)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = header
        req.httpBody = "{}".data(using:.utf8)
        URLSession.shared.dataTask(with:req){ data,res,err in
            DispatchQueue.main.async {
                if let d = data,let json = try? JSONSerialization.jsonObject(with:d) as? [String:Any]{
                    let valid = json["data"] as? Bool ?? false
                    tipText = valid ? "✅ Token有效，可以一键登录" : "❌ Token失效"
                }else{
                    tipText = "网络异常"
                }
            }
        }.resume()
    }
    
    func openGame(){
        guard let url = URL(string:"seecoon://login?token=\(inputToken)") else {return}
        UIApplication.shared.open(url)
    }
    
    var body: some View {
        VStack(spacing:15){
            TextField("粘贴seecoon_token",text:$inputToken)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            Button("检测Token有效性",action:checkToken)
            Text(tipText)
            Button("唤起三角洲一键登录",action:openGame)
                .disabled(!tipText.contains("✅"))
                .buttonStyle(.borderedProminent)
            Button("🔐 密文解密工具"){
                showDecrypt = true
            }
            Spacer()
        }
        .sheet(isPresented:$showDecrypt){ DecryptView() }
        .padding()
    }
}

// MARK: - 主视图（由外部的 App.swift 启动）
struct DeltaTokenMainView: View {
    @StateObject var dm = DataManager()
    @State var tabIndex = 0
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:0) {
                Button("A扫码抓包") { tabIndex = 0 }
                    .frame(maxWidth: .infinity)
                Button("B查看Token") { tabIndex = 1 }
                    .frame(maxWidth: .infinity)
                Button("C Token登录") { tabIndex = 2 }
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            Divider()
            if tabIndex == 0 { QRView(dm: dm) }
            else if tabIndex == 1 { TokenListView(dm: dm) }
            else { LoginView() }
        }
    }
}