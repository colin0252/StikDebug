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
    static var orientationLock = UIInterfaceOrientationMask.portrait
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
    
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return QQAuthManager.shared.handleCallback(url: url)
    }
}

// MARK: - 强制旋转屏幕工具
struct OrientationHelper {
    static func lockPortrait() {
        AppDelegate.orientationLock = .portrait
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
    
    static func lockLandscape() {
        AppDelegate.orientationLock = .landscapeRight
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
}

// MARK: - 安全区域工具
struct SafeArea {
    static var top: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 0
    }
    static var bottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 0
    }
    static var left: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.left ?? 0
    }
    static var right: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.right ?? 0
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

// MARK: - 主界面（竖屏，白底全屏，适配 iPhone X+ 安全区域）
struct HomeView: View {
    @Binding var currentPage: AppPage
    @State private var showQQAuth = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: SafeArea.top + geo.size.height * 0.05)
                    
                    Text("三角洲行动助手")
                        .font(.system(size: min(geo.size.width * 0.075, 34), weight: .bold))
                        .foregroundColor(.black)
                        .padding(.bottom, geo.size.height * 0.06)
                    
                    VStack(spacing: min(geo.size.height * 0.025, 20)) {
                        HomeButton(title: "挂机收号（横屏）", color: .red) {
                            currentPage = .authQR
                        }
                        .frame(width: min(geo.size.width * 0.78, 320))
                        
                        HomeButton(title: "QQ 扫码登录获取 Token", color: .orange) {
                            showQQAuth = true
                        }
                        .frame(width: min(geo.size.width * 0.78, 320))
                        
                        HomeButton(title: "账号库存", color: .green) {
                            currentPage = .accountList
                        }
                        .frame(width: min(geo.size.width * 0.78, 320))
                        
                        HomeButton(title: "Token 校验 + 一键上号", color: .blue) {
                            currentPage = .tokenCheck
                        }
                        .frame(width: min(geo.size.width * 0.78, 320))
                    }
                    
                    Spacer()
                }
            }
        }
        .onAppear { OrientationHelper.lockPortrait() }
        .sheet(isPresented: $showQQAuth) {
            QQAuthView(isPresented: $showQQAuth).environmentObject(DataManager())
        }
    }
}

// MARK: - 首页按钮组件
struct HomeButton: View {
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(color)
                .cornerRadius(14)
        }
    }
}

// MARK: - 挂机收号页面（强制横屏，白底全屏，适配 iPhone X+ 安全区域）
struct PageA: View {
    @EnvironmentObject var manager: DataManager
    @Binding var currentPage: AppPage
    @State private var catchCount = 0
    @State private var qrImage = UIImage()
    @State private var session = ""
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
                    await MainActor.run {}
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
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    HStack {
                        Button("← 返回首页") {
                            OrientationHelper.lockPortrait()
                            loopTask?.cancel()
                            clipTask?.cancel()
                            currentPage = .home
                        }
                        .foregroundColor(.blue)
                        .font(.system(size: 16))
                        Spacer()
                    }
                    .padding(.horizontal, 20 + SafeArea.left)
                    .padding(.top, 10 + SafeArea.top)
                    
                    Spacer()
                    
                    Image(uiImage: qrImage)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: min(geo.size.width * 0.32, geo.size.height * 0.55, 280),
                            height: min(geo.size.width * 0.32, geo.size.height * 0.55, 280)
                        )
                    
                    Text("已抓取：\(catchCount) 个账号")
                        .foregroundColor(.gray)
                        .font(.system(size: 16))
                        .padding(.top, 15)
                    
                    Spacer()
                }
            }
        }
        .onAppear {
            OrientationHelper.lockLandscape()
            newSession()
        }
        .onDisappear {
            loopTask?.cancel()
            clipTask?.cancel()
            OrientationHelper.lockPortrait()
        }
    }
}

// MARK: - 账号库存页面（竖屏，白底全屏，适配 iPhone X+）
struct PageB: View {
    @EnvironmentObject var manager: DataManager
    @Binding var currentPage: AppPage
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    HStack {
                        Button("← 返回首页") { currentPage = .home }
                            .foregroundColor(.blue)
                            .font(.system(size: 16))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10 + SafeArea.top)
                    
                    Text("账号库存")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.vertical, 12)
                    
                    List(manager.accounts) { acc in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OpenID: \(acc.openid)")
                                .foregroundColor(.black)
                                .font(.system(size: 14))
                            Text("Token: \(String(acc.seecoon_token.prefix(20)))...")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            HStack {
                                Button("复制") { UIPasteboard.general.string = acc.seecoon_token }
                                    .font(.system(size: 13))
                                Button("删除", role: .destructive) { manager.deleteAccount(uuid: acc.id) }
                                    .font(.system(size: 13))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            }
        }
        .onAppear { OrientationHelper.lockPortrait() }
    }
}

// MARK: - Token 校验与上号（竖屏，白底全屏，适配 iPhone X+）
struct PageC: View {
    @Binding var currentPage: AppPage
    @State var token = ""
    @State var status = ""
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    HStack {
                        Button("← 返回首页") { currentPage = .home }
                            .foregroundColor(.blue)
                            .font(.system(size: 16))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10 + SafeArea.top)
                    
                    Spacer()
                    
                    Text("Token 校验与一键上号")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.bottom, 25)
                    
                    TextField("粘贴 Seecoon Token", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 30)
                        .font(.system(size: 16))
                    
                    Button("校验有效性") { check() }
                        .foregroundColor(.white)
                        .font(.system(size: 17))
                        .frame(width: min(geo.size.width * 0.65, 280), height: 46)
                        .background(Color.blue)
                        .cornerRadius(10)
                        .padding(.top, 18)
                    
                    Text(status)
                        .foregroundColor(status.contains("✅") ? .green : .red)
                        .font(.system(size: 15))
                        .padding(.top, 10)
                    
                    Button("一键上号") {
                        UIApplication.shared.open(URL(string: "seecoon://login?token=\(token)")!)
                    }
                    .disabled(token.isEmpty)
                    .foregroundColor(.white)
                    .font(.system(size: 17))
                    .frame(width: min(geo.size.width * 0.65, 280), height: 46)
                    .background(Color.orange)
                    .cornerRadius(10)
                    .padding(.top, 10)
                    
                    Spacer()
                }
            }
        }
        .onAppear { OrientationHelper.lockPortrait() }
    }
    
    func check() {
        if token.isEmpty {
            status = "❌ 请输入 Token"
        } else if token.count > 80 {
            status = "✅ Token 格式有效"
        } else {
            status = "❌ Token 格式无效"
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
                    HomeView(currentPage: $currentPage).environmentObject(manager)
                case .authQR:
                    PageA(currentPage: $currentPage).environmentObject(manager)
                case .accountList:
                    PageB(currentPage: $currentPage).environmentObject(manager)
                case .tokenCheck:
                    PageC(currentPage: $currentPage)
                }
            }
        }
    }
}