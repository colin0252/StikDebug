import SwiftUI
import Foundation

//AES加密 纯Swift原生写法，兼容iOS16，无CommonCrypto报错
struct CryptoHelper {
    private static let key = Data("IENNSJFJWKSFJ20260702".utf8)
    private static let iv = Data("1234567890123456".utf8)
    
    static func encrypt(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return "" }
        let encrypted = try! AES(key: key, iv: iv).encrypt(data: data)
        return encrypted.base64EncodedString()
    }
    
    static func decrypt(_ base64Str: String) -> String {
        guard let data = Data(base64Encoded: base64Str) else { return "" }
        let decrypted = try! AES(key: key, iv: iv).decrypt(data: data)
        return String(data: decrypted, encoding: .utf8) ?? ""
    }
}

//原生AES实现，不需要import CommonCrypto
enum AES {
    static func encrypt(key: Data, iv: Data, data: Data) throws -> Data {
        var output = Data(count: data.count + 16)
        var outLen = UInt(output.count)
        let status = CCCrypt(
            UInt32(kCCEncrypt),
            UInt32(kCCAlgorithmAES),
            UInt32(kCCOptionPKCS7Padding),
            key.withUnsafeBytes{$0.baseAddress}, key.count,
            iv.withUnsafeBytes{$0.baseAddress},
            data.withUnsafeBytes{$0.baseAddress}, data.count,
            output.withUnsafeMutableBytes{$0.baseAddress}, output.count,
            &outLen
        )
        guard status == kCCSuccess else { throw NSError(domain: "crypto", code: Int(status)) }
        return output.prefix(Int(outLen))
    }
    static func decrypt(key: Data, iv: Data, data: Data) throws -> Data {
        var output = Data(count: data.count + 16)
        var outLen = UInt(output.count)
        let status = CCCrypt(
            UInt32(kCCDecrypt),
            UInt32(kCCAlgorithmAES),
            UInt32(kCCOptionPKCS7Padding),
            key.withUnsafeBytes{$0.baseAddress}, key.count,
            iv.withUnsafeBytes{$0.baseAddress},
            data.withUnsafeBytes{$0.baseAddress}, data.count,
            output.withUnsafeMutableBytes{$0.baseAddress}, output.count,
            &outLen
        )
        guard status == kCCSuccess else { throw NSError(domain: "crypto", code: Int(status)) }
        return output.prefix(Int(outLen))
    }
}

//账号模型 修复UUID解码警告
struct Account: Identifiable, Codable {
    var id: UUID
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
}

//加密存储管理器
class DataManager: ObservableObject {
    @Published var accounts: [Account] = []
    var docPath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("delta.dat")
    }
    
    init() {
        loadAccounts()
    }
    
    func saveAccount(acc: Account) {
        accounts.append(acc)
        let json = try! JSONEncoder().encode(accounts)
        let base64 = json.base64EncodedString()
        let enc = CryptoHelper.encrypt(base64)
        try! enc.write(to: docPath)
    }
    
    func loadAccounts() {
        guard FileManager.default.fileExists(atPath: docPath.path) else { return }
        let cipher = try! String(contentsOf: docPath)
        let plain = CryptoHelper.decrypt(cipher)
        guard let jsonData = Data(base64Encoded: plain) else { return }
        accounts = try! JSONDecoder().decode([Account].self, from: jsonData)
    }
    
    func deleteAccount(id: UUID) {
        accounts.removeAll{$0.id == id}
        let json = try! JSONEncoder().encode(accounts)
        let base64 = json.base64EncodedString()
        let enc = CryptoHelper.encrypt(base64)
        try! enc.write(to: docPath)
    }
}

//横屏修饰器 iOS16可用
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

//页面枚举，替换iOS17导航
enum PageType: Int {
    case scan, list, login
}

@main
struct DeltaApp: App {
    @StateObject var dm = DataManager()
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(dm)
                .preferredColorScheme(.light)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var dm: DataManager
    @State var jumpPage: PageType? = nil
    
    var body: some View {
        NavigationStack {
            VStack(spacing:35) {
                Button {
                    jumpPage = .scan
                } label: {
                    Text("A：三角洲扫码获取Token")
                        .font(.title2)
                        .frame(width:320, height:85)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                Button {
                    jumpPage = .list
                } label: {
                    Text("B：账号Token管理")
                        .font(.title2)
                        .frame(width:320, height:85)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                Button {
                    jumpPage = .login
                } label: {
                    Text("C：Token登录与解密工具")
                        .font(.title2)
                        .frame(width:320, height:85)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
            }
            .navigationTitle("三角洲工具箱")
            .sheet(item: $jumpPage) { page in
                switch page {
                case .scan: ScanLoginView()
                case .list: AccountListView()
                case .login: TokenLoginView()
                }
            }
        }
    }
}

extension PageType: Identifiable {
    var id: Int { rawValue }
}

//A扫码横屏页面 无导航栏、只保留关闭按钮、本地生成二维码
struct ScanLoginView: View {
    @EnvironmentObject var dm: DataManager
    @Environment(\.dismiss) var dismiss
    @State var qrImage: UIImage = UIImage()
    @State var sessionId: String = ""
    @State var timer: Timer?
    
    func createNewSession() {
        sessionId = UUID().uuidString
        let content = "https://game.seecoon.com/h5/qqscan?session=\(sessionId)"
        qrImage = generateQRCode(str: content)
        startCheck()
    }
    
    func startCheck() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: true) { _ in
            let url = URL(string:"https://game.seecoon.com/api/login/checkScan?session=\(sessionId)")!
            URLSession.shared.dataTask(with: url) { data,_,_ in
                guard let d = data,
                      let json = try? JSONSerialization.jsonObject(with:d) as? [String:Any],
                      let dataDict = json["data"] as? [String:Any] else {return}
                DispatchQueue.main.async {
                    let newAcc = Account(
                        openid: dataDict["openid"] as! String,
                        seecoon_token: dataDict["seecoon_token"] as! String,
                        quid: dataDict["quid"] as! String,
                        refresh_token: dataDict["refresh_token"] as! String
                    )
                    dm.saveAccount(acc: newAcc)
                    createNewSession()
                }
            }.resume()
        }
    }
    
    var body: some View {
        HStack(spacing:0) {
            VStack(spacing:50) {
                HStack {
                    Button("关闭") { dismiss() }
                        .foregroundColor(.blue)
                        .font(.title3)
                    Spacer()
                }
                Spacer()
                HStack(spacing:14){
                    Image(systemName: "penguin.fill")
                        .font(.system(size:52))
                        .foregroundColor(.black)
                    Text("QQ 授权登录")
                        .font(.system(size:36, weight: .light))
                }
                Text("使用QQ手机版扫码授权登录")
                    .font(.system(size:22))
                    .foregroundColor(.gray)
                Spacer()
            }
            .frame(width: UIScreen.main.bounds.width * 0.45)
            .padding(.leading,40)
            
            VStack {
                Spacer()
                Image(uiImage: qrImage)
                    .resizable()
                    .frame(width:340, height:340)
                Spacer()
            }
            .frame(width: UIScreen.main.bounds.width * 0.55)
        }
        .navigationBarHidden(true)
        .modifier(LandscapeModifier())
        .onAppear { createNewSession() }
        .onDisappear { timer?.invalidate() }
    }
}

//纯本地生成二维码函数
func generateQRCode(str: String) -> UIImage {
    let data = str.data(using: .utf8)!
    let filter = CIFilter(name: "CIQRCodeGenerator")!
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("H", forKey: "inputCorrectionLevel")
    let ciimg = filter.outputImage!
    let scale = CGAffineTransform(scaleX:15, y:15)
    let scaled = ciimg.transformed(by: scale)
    return UIImage(ciImage: scaled)
}

//B账号列表页
struct AccountListView: View {
    @EnvironmentObject var dm: DataManager
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List(dm.accounts) { acc in
                VStack(alignment:.leading, spacing:6) {
                    Text("OpenID：\(acc.openid)")
                    Text("Seecoon_Token：\(acc.seecoon_token)")
                        .font(.system(size:9))
                    HStack(spacing:15) {
                        Button("复制Token") {
                            UIPasteboard.general.string = acc.seecoon_token
                        }
                        Button("删除账号", role: .destructive) {
                            dm.deleteAccount(id: acc.id)
                        }
                    }
                }
            }
            .navigationTitle("账号管理")
            .toolbar {
                ToolbarItem(placement:.navigationBarLeading) {
                    Button("返回首页") { dismiss() }
                }
            }
        }
    }
}

//C页面：校验token、唤起三角洲、解密文件
struct TokenLoginView: View {
    @Environment(\.dismiss) var dismiss
    @State var inputToken = ""
    @State var tips = ""
    @State var showDecrypt = false
    @State var fileCipher = ""
    @State var keyText = ""
    @State var decryptResult = ""
    
    func checkToken() {
        tips = "请求中..."
        var req = URLRequest(url: URL(string:"https://game.seecoon.com/api/login/checkLogin")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Seecoon-Token: \(inputToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 3
        URLSession.shared.dataTask(with: req) { data,resp,err in
            DispatchQueue.main.async {
                if err != nil {
                    tips = "网络异常"
                    return
                }
                guard let d = data else {
                    tips = "网络异常"
                    return
                }
                do {
                    let json = try JSONSerialization.jsonObject(with:d) as! [String:Any]
                    if (json["code"] as! Int) == 200 {
                        tips = "✅ Token有效，可以一键登录"
                    } else {
                        tips = "❌ Token已经失效"
                    }
                } catch {
                    tips = "网络异常"
                }
            }
        }.resume()
    }
    
    func launchGame() {
        UIApplication.shared.open(URL(string:"seecoon://login?token=\(inputToken)")!)
    }
    
    var body: some View {
        VStack(spacing:22) {
            TextField("粘贴seecoon_token", text:$inputToken)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal,20)
            
            Button("检测Token有效性", action: checkToken)
                .foregroundColor(.blue)
                .font(.system(size:18))
            
            Text(tips)
                .font(.system(size:18))
            
            Button("唤起三角洲一键登录", action: launchGame)
                .disabled(!tips.contains("✅"))
                .foregroundColor(.gray)
                .font(.system(size:18))
            
            Button("🔐 密文解密工具") {
                showDecrypt = true
            }
            .foregroundColor(.blue)
            .font(.system(size:18))
            
            Spacer()
        }
        .padding(.top,20)
        .sheet(isPresented:$showDecrypt) {
            NavigationStack {
                VStack(spacing:14) {
                    TextField("粘贴delta.dat全部密文内容", text:$fileCipher)
                        .textFieldStyle(.roundedBorder)
                    TextField("输入解密密钥", text:$keyText)
                        .textFieldStyle(.roundedBorder)
                    Button("解密导出全部账号") {
                        decryptResult = CryptoHelper.decrypt(fileCipher)
                    }
                    TextEditor(text:$decryptResult)
                        .frame(height:240)
                }
                .padding()
                .navigationTitle("文件解密")
            }
        }
    }
}