import SwiftUI
import CoreImage
import CryptoKit

// MARK: - QQ 互联配置
struct QQConfig {
    static let appID = "100360353"
    static let redirectURI = "seecoonlocal://oauth/callback"
    
    static func authURL(state: String) -> URL {
        var comps = URLComponents(string: "https://graph.qq.com/oauth2.0/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "client_id", value: appID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "get_user_info"),
            URLQueryItem(name: "state", value: state)
        ]
        return comps.url!
    }
}

// MARK: - AppDelegate（动态控制屏幕方向）
class AppDelegate: NSObject, UIApplicationDelegate {
    // ✅ 默认竖屏，可动态切换
    static var orientationLock = UIInterfaceOrientationMask.portrait
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
    
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return QQAuthManager.shared.handleCallback(url: url)
    }
}

// MARK: - QQ 授权管理器
class QQAuthManager: ObservableObject {
    static let shared = QQAuthManager()
    @Published var accessToken: String? = nil
    @Published var isAuthorizing = false
    private var currentState = ""
    
    func startAuth() -> URL? {
        currentState = UUID().uuidString
        isAuthorizing = true
        return QQConfig.authURL(state: currentState)
    }
    
    func handleCallback(url: URL) -> Bool {
        guard isAuthorizing else { return false }
        isAuthorizing = false
        var params = [String: String]()
        if let fragment = url.fragment {
            URLComponents(string: "?" + fragment)?.queryItems?.forEach { params[$0.name] = $0.value }
        } else if let query = url.query {
            URLComponents(string: "?" + query)?.queryItems?.forEach { params[$0.name] = $0.value }
        }
        guard params["state"] == currentState, let token = params["access_token"] else { return false }
        self.accessToken = token
        return true
    }
}

// MARK: - 二维码生成器
struct QRGenerator {
    static let context = CIContext()
    static func createQRCode(text: String) -> UIImage {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return UIImage() }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return UIImage() }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 15, y: 15))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return UIImage() }
        return UIImage(cgImage: cg)
    }
}

// MARK: - 加密工具
struct CryptoHelper {
    private static let keyRaw = Data("IENNSJFJWKSFJ20260702".utf8)
    private static let nonceRaw = Data("1234567890123456".utf8)
    static func encrypt(_ text: String) -> String {
        let key = SymmetricKey(data: keyRaw)
        let nonce = try! AES.GCM.Nonce(data: nonceRaw)
        let box = try! AES.GCM.seal(Data(text.utf8), using: key, nonce: nonce)
        return box.combined!.base64EncodedString()
    }
    static func decrypt(_ base64Str: String) -> String {
        guard let combined = Data(base64Encoded: base64Str) else { return "" }
        let key = SymmetricKey(data: keyRaw)
        guard let box = try? AES.GCM.SealedBox(combined: combined),
              let data = try? AES.GCM.open(box, using: key) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - 账号模型
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
    enum CodingKeys: CodingKey { case id, openid, seecoon_token, quid, refresh_token, createTime }
}

// MARK: - 数据管理器
class DataManager: ObservableObject {
    @Published var accounts: [Account] = []
    var filePath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("delta.dat")
    }
    init() { loadAllAccounts() }
    func saveNewAccount(_ acc: Account) { accounts.append(acc); syncToDisk() }
    func deleteAccount(uuid: UUID) { accounts.removeAll { $0.id == uuid }; syncToDisk() }
    private func syncToDisk() {
        let json = try! JSONEncoder().encode(accounts)
        let enc = CryptoHelper.encrypt(json.base64EncodedString())
        try! enc.write(to: filePath, atomically: true, encoding: .utf8)
    }
    private func loadAllAccounts() {
        guard FileManager.default.fileExists(atPath: filePath.path) else { return }
        let cipher = try! String(contentsOf: filePath)
        let plain = CryptoHelper.decrypt(cipher)
        guard let data = Data(base64Encoded: plain) else { return }
        accounts = try! JSONDecoder().decode([Account].self, from: data)
    }
}

// MARK: - 页面路由
enum AppPage { case home, authQR, accountList, tokenCheck }

// MARK: - QQ 授权扫码页面
struct QQAuthView: View {
    @EnvironmentObject var manager: DataManager
    @Binding var isPresented: Bool
    @StateObject private var authManager = QQAuthManager.shared
    @State private var qrImage: UIImage? = nil
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let qrImage = qrImage {
                    Image(uiImage: qrImage).resizable().scaledToFit().frame(width: 250, height: 250)
                    Text("请使用 QQ 扫描此二维码").foregroundColor(.black)
                } else {
                    ProgressView("生成二维码中...")
                }
                if let token = authManager.accessToken {
                    Text("获取到 token: \(token.prefix(10))...").foregroundColor(.green)
                    Button("复制 Token") { UIPasteboard.general.string = token }
                }
            }
            .padding()
            .background(Color.white.ignoresSafeArea())
            .onAppear {
                if let url = authManager.startAuth() {
                    qrImage = QRGenerator.createQRCode(text: url.absoluteString)
                }
            }
            .onChange(of: authManager.accessToken) { _ in
                if authManager.accessToken != nil { isPresented = false }
            }
            .navigationTitle("QQ 授权登录")
        }
    }
}

// MARK: - 主界面（✅ 竖屏，白底）
struct HomeView: View {
    @Binding var currentPage: AppPage
    @State private var showQQAuth = false
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 35) {
                Text("三角洲行动助手")
                    .font(.largeTitle).bold()
                    .foregroundColor(.black)
                
                Button("QQ 扫码登录获取 Token") { showQQAuth = true }
                    .font(.title2).padding()
                    .background(Color.orange).foregroundColor(.white).cornerRadius(14)
                
                Button("账号库存") { currentPage = .accountList }
                    .font(.title2).padding()
                    .background(Color.green).foregroundColor(.white).cornerRadius(14)
                
                Button("Token 校验 + 一键上号") { currentPage = .tokenCheck }
                    .font(.title2).padding()
                    .background(Color.blue).foregroundColor(.white).cornerRadius(14)
            }
        }
        .onAppear {
            // ✅ 进入主页强制竖屏
            AppDelegate.orientationLock = .portrait
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
        .sheet(isPresented: $showQQAuth) {
            QQAuthView(isPresented: $showQQAuth).environmentObject(DataManager())
        }
    }
}

// MARK: - 挂机收号页面（✅ 强制横屏，白底）
struct PageA: View {
    @EnvironmentObject var manager: DataManager
    @Binding var currentPage: AppPage
    @State private var catchCount = 0
    @State private var qrImage = UIImage()
    @State private var session = ""
    @State private var showAuth = false
    @State private var authFinished = false
    @State private var clipTask: Task<Void, Never>?
    @State private var loopTask: Task<Void, Never>?
    @State private var lastPaste = ""
    
    func newSession() {
        loopTask?.cancel()
        clipTask?.cancel()
        session = UUID().uuidString
        let base64Session = Data(session.utf8).base64EncodedString()
        let customProtocol = "open://authdata/\(base64Session)"
        qrImage = QRGenerator.createQRCode(text: customProtocol)
        startClipboard()
        startPolling()
    }
    
    func startClipboard() {
        clipTask = Task {
            while true {
                try? await Task.sleep(nanoseconds: 400_000_000)
                let paste = UIPasteboard.general.string ?? ""
                if paste != lastPaste && paste.contains("open://authdata/") {
                    lastPaste = paste
                    let baseStr = paste.replacingOccurrences(of: "open://authdata/", with: "")
                    guard let data = Data(base64Encoded: baseStr),
                          let sid = String(data: data, encoding: .utf8),
                          sid == session else { continue }
                    await MainActor.run { showAuth = true }
                }
            }
        }
    }
    
    func startPolling() {
        loopTask = Task {
            var count = 0
            while true {
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                count += 1
                if count >= 70 {
                    await MainActor.run { newSession() }
                    break
                }
                guard let url = URL(string: "https://game.seecoon.com/api/login/checkScan?session=\(session)") else { continue }
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let user = json["data"] as? [String: Any] else { continue }
                    let acc = Account(openid: user["openid"] as! String,
                                      seecoon_token: user["seecoon_token"] as! String,
                                      quid: user["quid"] as! String,
                                      refresh_token: user["refresh_token"] as! String)
                    await MainActor.run {
                        manager.saveNewAccount(acc)
                        catchCount += 1
                        newSession()
                    }
                    break
                } catch {}
            }
        }
    }
    
    var body: some View {
        ZStack {
            // ✅ 白底全屏
            Color.white.ignoresSafeArea()
            
            HStack(spacing: 0) {
                // 左侧信息
                VStack(spacing: 35) {
                    HStack {
                        // ✅ 返回键改为返回首页，不退出
                        Button("返回首页") {
                            // 恢复竖屏
                            AppDelegate.orientationLock = .portrait
                            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
                            UIViewController.attemptRotationToDeviceOrientation()
                            loopTask?.cancel()
                            clipTask?.cancel()
                            currentPage = .home
                        }
                        .foregroundColor(.blue)
                        Spacer()
                    }
                    .padding(.leading, 20)
                    
                    Spacer()
                    
                    Text("三角洲")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundColor(.black)
                    
                    Text("今日已抓取账号：\(catchCount) 个")
                        .foregroundColor(.gray)
                        .font(.system(size: 22))
                    
                    Spacer()
                }
                .frame(width: UIScreen.main.bounds.width * 0.45)
                
                // 右侧二维码
                VStack {
                    Spacer()
                    Image(uiImage: qrImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 290, height: 290)
                    Spacer()
                }
                .frame(width: UIScreen.main.bounds.width * 0.55)
            }
        }
        .onAppear {
            // ✅ 进入挂机页面强制横屏
            AppDelegate.orientationLock = .landscapeRight
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
            newSession()
        }
        .onDisappear {
            loopTask?.cancel()
            clipTask?.cancel()
            // ✅ 离开时恢复竖屏
            AppDelegate.orientationLock = .portrait
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}

// MARK: - 账号库存页面（✅ 竖屏，白底）
struct PageB: View {
    @EnvironmentObject var manager: DataManager
    @Binding var currentPage: AppPage
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            VStack {
                HStack {
                    Button("返回首页") { currentPage = .home }
                        .foregroundColor(.blue)
                    Spacer()
                }
                .padding()
                
                Text("账号库存管理")
                    .foregroundColor(.black)
                    .font(.title)
                    .bold()
                
                List(manager.accounts) { acc in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("OpenID：\(acc.openid)")
                            .foregroundColor(.black)
                        Text("Token：\(String(acc.seecoon_token.prefix(20)))...")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        HStack(spacing: 15) {
                            Button("复制Token") {
                                UIPasteboard.general.string = acc.seecoon_token
                            }
                            Button("删除账号", role: .destructive) {
                                manager.deleteAccount(uuid: acc.id)
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            // ✅ 确保竖屏
            AppDelegate.orientationLock = .portrait
        }
    }
}

// MARK: - Token 校验与上号（✅ 竖屏，白底，本地校验）
struct PageC: View {
    @Binding var currentPage: AppPage
    @State var token = ""
    @State var status = ""
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 22) {
                HStack {
                    Button("返回首页") { currentPage = .home }
                        .foregroundColor(.blue)
                    Spacer()
                }
                .padding()
                
                Text("Token 校验与一键上号")
                    .font(.title2).bold()
                    .foregroundColor(.black)
                
                TextField("粘贴 Seecoon Token", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 20)
                
                Button("校验有效性") { check() }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                
                Text(status)
                    .foregroundColor(status.contains("✅") ? .green : .red)
                    .font(.system(size: 16))
                
                Button("一键唤起三角洲登录") {
                    UIApplication.shared.open(URL(string: "seecoon://login?token=\(token)")!)
                }
                .disabled(token.isEmpty)
                .foregroundColor(.white)
                .padding()
                .background(Color.orange)
                .cornerRadius(10)
                
                Spacer()
            }
            .padding(.top, 20)
        }
        .onAppear {
            // ✅ 确保竖屏
            AppDelegate.orientationLock = .portrait
        }
    }
    
    // ✅ 本地校验
    func check() {
        if token.isEmpty {
            status = "❌ 请输入 Token"
        } else if token.count > 80 {
            status = "✅ Token 格式有效（请用一键上号验证实际可用性）"
        } else {
            status = "❌ Token 格式无效，请检查后重试"
        }
    }
}

// MARK: - 程序入口
@main
struct DeltaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var manager = DataManager()
    @State var currentPage: AppPage = .home
    
    var body: some Scene {
        WindowGroup {
            if #available(iOS 16.4, *) {
                switch currentPage {
                case .home:
                    HomeView(currentPage: $currentPage)
                        .environmentObject(manager)
                    
                case .authQR:
                    // ✅ A页面：挂机收号（强制横屏）
                    PageA(currentPage: $currentPage)
                        .environmentObject(manager)
                    
                case .accountList:
                    // ✅ B页面：账号库存（竖屏）
                    PageB(currentPage: $currentPage)
                        .environmentObject(manager)
                    
                case .tokenCheck:
                    // ✅ C页面：Token校验（竖屏）
                    PageC(currentPage: $currentPage)
                }
            }
        }
    }
}