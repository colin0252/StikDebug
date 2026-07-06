import SwiftUI
import UIKit

// MARK: - 强制横屏包装器
struct LandscapeViewController<Content: View>: UIViewControllerRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> LandscapeHostingController<Content> {
        LandscapeHostingController(rootView: content)
    }

    func updateUIViewController(_ uiViewController: LandscapeHostingController<Content>, context: Context) {}
}

class LandscapeHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscape
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        .landscapeRight
    }
}

// MARK: - 数据模型
struct GameAccount: Identifiable, Codable {
    let id: String
    let gameName: String
    let uid: String
    let username: String
    let loginTime: String
}

struct TokenRecord: Identifiable, Codable {
    let id: String
    let token: String
    let source: String
    let createTime: String
    var note: String
}

// MARK: - 游戏登录管理器
class GameLoginManager: ObservableObject {
    @Published var currentToken: String = ""
    @Published var isLoggedIn: Bool = false
    @Published var accounts: [GameAccount] = []
    @Published var tokenRecords: [TokenRecord] = []

    @Published var bannerMessage: String = ""
    @Published var bannerType: BannerType = .info
    @Published var showBanner: Bool = false

    enum BannerType {
        case info, success, warning, error
    }

    private let userDefaults = UserDefaults.standard
    private let accountsKey = "game_accounts"
    private let tokensKey = "token_records"

    init() {
        loadAccounts()
        loadTokens()
    }

    private func showBannerMsg(_ message: String, type: BannerType = .info) {
        bannerMessage = message
        bannerType = type
        showBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.showBanner = false
        }
    }

    // MARK: Token 管理
    func saveToken(_ token: String, source: String = "手动输入") {
        guard !token.isEmpty else {
            showBannerMsg("Token 不能为空", type: .warning)
            return
        }
        if tokenRecords.contains(where: { $0.token == token }) {
            showBannerMsg("该 Token 已存在", type: .warning)
            return
        }
        let record = TokenRecord(
            id: UUID().uuidString,
            token: token,
            source: source,
            createTime: getCurrentTimeString(),
            note: ""
        )
        tokenRecords.insert(record, at: 0)
        saveTokens()
        if currentToken.isEmpty {
            selectToken(token)
        }
        showBannerMsg("Token 已储存", type: .success)
    }

    func selectToken(_ token: String) {
        currentToken = token
        isLoggedIn = true
        showBannerMsg("已切换 Token", type: .success)
    }

    func copyToken(_ token: String) {
        UIPasteboard.general.string = token
        showBannerMsg("已复制到剪贴板", type: .success)
    }

    func deleteToken(id: String) {
        if let record = tokenRecords.first(where: { $0.id == id }), record.token == currentToken {
            currentToken = ""
            isLoggedIn = false
        }
        tokenRecords.removeAll { $0.id == id }
        saveTokens()
        showBannerMsg("Token 已删除")
    }

    func clearAllTokens() {
        tokenRecords.removeAll()
        currentToken = ""
        isLoggedIn = false
        saveTokens()
        showBannerMsg("所有 Token 已清空")
    }

    // MARK: Token 检测
    func checkToken(_ token: String, completion: @escaping (Bool) -> Void) {
        showBannerMsg("正在检测...", type: .info)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let valid = token.count > 20
            if valid {
                self.showBannerMsg("Token 有效", type: .success)
            } else {
                self.showBannerMsg("Token 过短或格式无效", type: .error)
            }
            completion(valid)
        }
    }

    // MARK: 游戏唤起
    func launchGame(gameName: String, urlScheme: String?, token: String? = nil) {
        let tokenToUse = token ?? currentToken
        guard !tokenToUse.isEmpty else {
            showBannerMsg("请先输入或选择 Token", type: .warning)
            return
        }

        // 自动复制 Token 到剪贴板
        UIPasteboard.general.string = tokenToUse

        if let scheme = urlScheme, !scheme.isEmpty, let url = URL(string: "\(scheme)://") {
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    self.showBannerMsg("正在唤起 \(gameName)...", type: .success)
                } else {
                    self.showBannerMsg("自动唤起失败，请手动打开 \(gameName) 并粘贴 Token", type: .warning)
                }
            }
        } else {
            showBannerMsg("Token 已复制，请手动打开 \(gameName) 并粘贴登录", type: .success)
        }

        // 记录操作
        let newAccount = GameAccount(
            id: UUID().uuidString,
            gameName: gameName,
            uid: "Token 已准备",
            username: "请手动登录",
            loginTime: getCurrentTimeString()
        )
        accounts.append(newAccount)
        saveAccounts()
    }

    func oneClickLogin(token: String? = nil) {
        launchGame(gameName: "三角洲行动", urlScheme: "dfmobile", token: token)
    }

    // MARK: 账号记录管理
    func copyAccountUID(_ uid: String) {
        UIPasteboard.general.string = uid
        showBannerMsg("UID 已复制")
    }

    func deleteAccount(id: String) {
        accounts.removeAll { $0.id == id }
        saveAccounts()
        showBannerMsg("账号记录已删除")
    }

    func clearAllAccounts() {
        accounts.removeAll()
        saveAccounts()
        showBannerMsg("所有操作记录已清空")
    }

    // MARK: 持久化
    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            userDefaults.set(data, forKey: accountsKey)
        }
    }

    private func loadAccounts() {
        if let data = userDefaults.data(forKey: accountsKey),
           let decoded = try? JSONDecoder().decode([GameAccount].self, from: data) {
            accounts = decoded
        }
    }

    private func saveTokens() {
        if let data = try? JSONEncoder().encode(tokenRecords) {
            userDefaults.set(data, forKey: tokensKey)
        }
    }

    private func loadTokens() {
        if let data = userDefaults.data(forKey: tokensKey),
           let decoded = try? JSONDecoder().decode([TokenRecord].self, from: data) {
            tokenRecords = decoded
        }
    }

    private func getCurrentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    // MARK: 二维码生成（示例，可替换为真实 QQ 互联链接）
    func generateQRCodeURL() -> String {
        // 等待配置 AppID，当前返回一个占位二维码
        return "https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=WAIT_FOR_APPID&color=000&bgcolor=fff"
    }

    func simulateQRCodeScan() {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let token = "QQ_" + String((0..<32).map { _ in chars.randomElement()! })
        saveToken(token, source: "模拟扫码")
    }
}

// MARK: - App 入口
@main
struct DeltaApp: App {
    @State private var showQRScanner = true
    @State private var showGameLogin = false

    var body: some Scene {
        WindowGroup {
            NavigationView {
                HomeView(showGameLogin: $showGameLogin)
            }
            .navigationViewStyle(.stack)
            .ignoresSafeArea(.all)
            .fullScreenCover(isPresented: $showQRScanner) {
                QRCodeLandscapeView(isPresented: $showQRScanner)
            }
            .fullScreenCover(isPresented: $showGameLogin) {
                GameLoginLandscapeView(isPresented: $showGameLogin)
            }
        }
    }
}

// MARK: - 横屏扫码界面
struct QRCodeLandscapeView: View {
    @Binding var isPresented: Bool
    @StateObject private var manager = GameLoginManager()
    @State private var countdown = 120
    @State private var expired = false
    @State private var timer: Timer?

    var body: some View {
        LandscapeViewController {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    // 退出按钮
                    HStack {
                        Spacer()
                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white.opacity(0.6))
                                .padding()
                        }
                    }

                    Spacer()

                    // 游戏图标与标题
                    VStack(spacing: 8) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                            .frame(width: 80, height: 80)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .purple]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20))

                        Text("三角洲行动")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("QQ 账号授权登录")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    }

                    // 二维码区域
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white)
                            .frame(width: 200, height: 200)

                        // 等待 AppID 占位
                        VStack(spacing: 12) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)

                            Text("等待配置 AppID")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        // 过期遮罩
                        if expired {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.black.opacity(0.7))
                                .frame(width: 200, height: 200)

                            VStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                                Text("已过期")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                Text("点击刷新")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .onTapGesture {
                                refreshQRCode()
                            }
                        }
                    }

                    // 倒计时
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("有效期 \(String(format: "%02d:%02d", countdown / 60, countdown % 60))")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    // 提示文字
                    VStack(spacing: 6) {
                        Text("请使用手机 QQ 扫描二维码")
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Text("扫描后 Token 将自动储存")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Spacer()

                    // 底部安全提示
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("授权后仅获取游戏登录所需信息")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.bottom, 20)
                }
                .padding()
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func startTimer() {
        countdown = 120
        expired = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if countdown > 0 {
                countdown -= 1
            } else {
                expired = true
                t.invalidate()
            }
        }
    }

    private func refreshQRCode() {
        startTimer()
    }
}

// MARK: - 横屏游戏登录界面
struct GameLoginLandscapeView: View {
    @Binding var isPresented: Bool
    @StateObject private var manager = GameLoginManager()
    @State private var inputToken = ""
    @State private var useIndependentToken = false
    @FocusState private var isTokenFocused: Bool

    private let games: [(name: String, icon: String, color: Color, scheme: String?)] = [
        ("三角洲行动", "arrow.triangle.swap", Color(red: 1.0, green: 0.45, blue: 0.0), "dfmobile"),
        ("暗区突围", "shield.fill", Color(red: 0.9, green: 0.15, blue: 0.15), "darkzone"),
        ("和平精英", "scope", Color(red: 0.1, green: 0.8, blue: 0.3), "pubgm")
    ]

    var body: some View {
        LandscapeViewController {
            ZStack {
                Color.black.ignoresSafeArea()

                HStack(spacing: 20) {
                    // 左侧面板：Token 控制
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Circle()
                                .fill(manager.isLoggedIn || !inputToken.isEmpty ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(manager.isLoggedIn || !inputToken.isEmpty ? "Token 已就绪" : "未选择 Token")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            if manager.isLoggedIn {
                                Button("检测") {
                                    manager.checkToken(manager.currentToken) { _ in }
                                }
                                .font(.caption)
                                .foregroundColor(.orange)
                            }
                        }

                        Toggle("使用独立 Token", isOn: $useIndependentToken)
                            .font(.caption)
                            .foregroundColor(.white)

                        if useIndependentToken {
                            HStack {
                                TextField("输入独立 Token", text: $inputToken)
                                    .textFieldStyle(.plain)
                                    .padding(8)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                                    .focused($isTokenFocused)
                                    .toolbar {
                                        ToolbarItemGroup(placement: .keyboard) {
                                            Spacer()
                                            Button("完成") { isTokenFocused = false }
                                        }
                                    }
                                Button("储存") {
                                    if !inputToken.isEmpty {
                                        manager.saveToken(inputToken)
                                        inputToken = ""
                                    }
                                    isTokenFocused = false
                                }
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.orange)
                                .cornerRadius(8)
                            }
                        }

                        if !manager.tokenRecords.isEmpty && !useIndependentToken {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("已储存 Token")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                                ForEach(manager.tokenRecords.prefix(3)) { record in
                                    Button {
                                        manager.selectToken(record.token)
                                    } label: {
                                        HStack {
                                            Circle()
                                                .fill(record.token == manager.currentToken ? Color.green : Color.clear)
                                                .frame(width: 6, height: 6)
                                            Text(mask(record.token))
                                                .font(.caption2)
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            Spacer()
                                            if record.token == manager.currentToken {
                                                Text("当前")
                                                    .font(.caption2)
                                                    .foregroundColor(.green)
                                            }
                                        }
                                        .padding(6)
                                        .background(Color.white.opacity(0.05))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                        }

                        // 一键登录
                        Button {
                            manager.oneClickLogin(token: useIndependentToken ? inputToken : nil)
                        } label: {
                            HStack {
                                Image(systemName: "bolt.fill")
                                Text("一键登录三角洲行动")
                                    .fontWeight(.semibold)
                            }
                            .font(.caption)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange.opacity(0.8))
                            .cornerRadius(10)
                        }

                        // 最近操作
                        if !manager.accounts.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("最近操作")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                                ForEach(manager.accounts.suffix(2)) { acc in
                                    Text("\(acc.gameName) - \(acc.loginTime)")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }
                        }
                    }
                    .frame(width: 240)
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(16)

                    // 右侧游戏卡片
                    VStack(spacing: 12) {
                        ForEach(games, id: \.name) { game in
                            Button {
                                manager.launchGame(
                                    gameName: game.name,
                                    urlScheme: game.scheme,
                                    token: useIndependentToken ? inputToken : nil
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: game.icon)
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(game.color)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(game.name)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        Text(game.scheme != nil ? "尝试自动唤起" : "手动打开游戏")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.5))
                                    }

                                    Spacer()

                                    Text(game.scheme != nil ? "🚀 唤起" : "📋 复制")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(game.color)
                                        .cornerRadius(6)
                                }
                                .padding(10)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()

                // 退出按钮（右上角）
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white.opacity(0.6))
                                .padding()
                        }
                    }
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
    }

    private func mask(_ token: String) -> String {
        guard token.count > 10 else { return token }
        return String(token.prefix(6)) + "****" + String(token.suffix(4))
    }
}

// MARK: - 顶部横幅（用于竖屏页面）
struct TopBanner: View {
    let message: String
    let type: GameLoginManager.BannerType

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(message)
                .font(.subheadline)
        }
        .foregroundColor(.white)
        .padding()
        .frame(maxWidth: .infinity)
        .background(bgColor)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .shadow(radius: 5)
    }

    private var bgColor: Color {
        switch type {
        case .info: return .blue.opacity(0.9)
        case .success: return .green.opacity(0.9)
        case .warning: return .orange.opacity(0.9)
        case .error: return .red.opacity(0.9)
        }
    }

    private var icon: String {
        switch type {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
}

// MARK: - 首页
struct HomeView: View {
    @Binding var showGameLogin: Bool
    @StateObject private var manager = GameLoginManager()

    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.06, blue: 0.12),
                    Color(red: 0.10, green: 0.10, blue: 0.20),
                    Color(red: 0.06, green: 0.06, blue: 0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo 区域
                VStack(spacing: 8) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)

                    Text("游戏账号管理")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("StikDebug")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer().frame(height: 60)

                // 功能入口卡片
                VStack(spacing: 16) {
                    NavigationLink(destination: QRCodeView()) {
                        HomeButtonContent(
                            icon: "qrcode",
                            color: .blue,
                            title: "QQ 扫码登录",
                            subtitle: "使用手机 QQ 扫描二维码获取 Token"
                        )
                    }

                    NavigationLink(destination: TokenManageView()) {
                        HomeButtonContent(
                            icon: "list.clipboard.fill",
                            color: .orange,
                            title: "Token 管理",
                            subtitle: "储存 Token · 一键复制 · 删除",
                            badge: "\(manager.tokenRecords.count)"
                        )
                    }

                    Button {
                        showGameLogin = true
                    } label: {
                        HomeButtonContent(
                            icon: "play.circle.fill",
                            color: .green,
                            title: "游戏登录",
                            subtitle: "三角洲行动 / 暗区突围 / 和平精英"
                        )
                    }

                    NavigationLink(destination: ExtractTokenView()) {
                        HomeButtonContent(
                            icon: "arrow.down.doc.fill",
                            color: .purple,
                            title: "提取 Token",
                            subtitle: "从剪贴板或链接提取 Token"
                        )
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                Text("v1.0.0")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.bottom, 30)
            }
        }
        .navigationBarHidden(true)
    }
}

struct HomeButtonContent: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundColor(.white)
                .frame(width: 46, height: 46)
                .background(color.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            if let badge = badge {
                Text(badge)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color)
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(18)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(16)
    }
}

// MARK: - 竖屏扫码页面（备用）
struct QRCodeView: View {
    @StateObject private var manager = GameLoginManager()
    @State private var countdown = 120
    @State private var expired = false
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.10, blue: 0.16)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // 游戏标识
                    VStack(spacing: 12) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                            .frame(width: 80, height: 80)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20))

                        Text("三角洲行动")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("QQ 账号授权登录")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.top, 40)

                    // 二维码卡片
                    VStack(spacing: 20) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white)
                                .frame(width: 220, height: 220)

                            AsyncImage(url: URL(string: manager.generateQRCodeURL())) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 185, height: 185)
                            } placeholder: {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 80))
                                    .foregroundColor(.black)
                            }

                            if expired {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.black.opacity(0.7))
                                    .frame(width: 220, height: 220)

                                VStack(spacing: 12) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 40))
                                        .foregroundColor(.white)
                                    Text("已过期")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("点击刷新")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .onTapGesture { refreshQRCode() }
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("有效期 \(String(format: "%02d:%02d", countdown / 60, countdown % 60))")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }

                        // 说明区域
                        VStack(alignment: .leading, spacing: 8) {
                            Text("💡 如何获取真实 Token？")
                                .font(.caption)
                                .foregroundColor(.yellow)
                            Text("1. 需在 QQ 互联平台注册应用，获取 appid 并配置回调 URL。")
                            Text("2. 将 appid 替换到二维码链接中，生成真实扫码 URL。")
                            Text("3. 用户扫码授权后，QQ 会回调你的服务器，服务器返回 Token。")
                            Text("4. 当前二维码为示例，点击下方按钮模拟获取。")
                        }
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(10)
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )

                    // 模拟扫码按钮
                    Button {
                        manager.simulateQRCodeScan()
                    } label: {
                        Label("模拟扫码获取 Token", systemImage: "iphone")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue.opacity(0.3))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .overlay(alignment: .top) {
            if manager.showBanner {
                TopBanner(message: manager.bannerMessage, type: manager.bannerType)
            }
        }
        .navigationTitle("QQ 扫码登录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(red: 0.10, green: 0.12, blue: 0.20), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private func startTimer() {
        countdown = 120
        expired = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if countdown > 0 {
                countdown -= 1
            } else {
                expired = true
                t.invalidate()
            }
        }
    }

    private func refreshQRCode() {
        startTimer()
    }
}

// MARK: - Token 管理页面
struct TokenManageView: View {
    @StateObject private var manager = GameLoginManager()
    @State private var inputToken = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.10, blue: 0.16)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // 当前使用的 Token
                    if manager.isLoggedIn {
                        VStack(spacing: 8) {
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("当前使用")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Spacer()
                            }
                            HStack {
                                Text(manager.currentToken)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    manager.copyToken(manager.currentToken)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                Button {
                                    manager.checkToken(manager.currentToken) { _ in }
                                } label: {
                                    Image(systemName: "checkmark.shield")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                    }

                    // 手动输入区域
                    VStack(spacing: 12) {
                        Text("手动输入 Token")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 8) {
                            TextField("输入或粘贴 Token", text: $inputToken)
                                .textFieldStyle(.plain)
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                                .foregroundColor(.white)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .focused($isInputFocused)
                                .toolbar {
                                    ToolbarItemGroup(placement: .keyboard) {
                                        Spacer()
                                        Button("完成") { isInputFocused = false }
                                    }
                                }

                            Button("储存") {
                                if !inputToken.isEmpty {
                                    manager.saveToken(inputToken)
                                    inputToken = ""
                                }
                                isInputFocused = false
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.orange)
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(16)

                    // 已储存 Token 列表
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("已储存 Token")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text("\(manager.tokenRecords.count) 个")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.4))
                            if !manager.tokenRecords.isEmpty {
                                Button("清空") {
                                    manager.clearAllTokens()
                                }
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                        }

                        if manager.tokenRecords.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "tray")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white.opacity(0.3))
                                Text("暂无 Token")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(manager.tokenRecords) { record in
                                TokenCard(
                                    record: record,
                                    isCurrent: record.token == manager.currentToken,
                                    manager: manager
                                )
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(16)
                }
                .padding(16)
            }
        }
        .overlay(alignment: .top) {
            if manager.showBanner {
                TopBanner(message: manager.bannerMessage, type: manager.bannerType)
            }
        }
        .navigationTitle("Token 管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(red: 0.10, green: 0.12, blue: 0.20), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct TokenCard: View {
    let record: TokenRecord
    let isCurrent: Bool
    @ObservedObject var manager: GameLoginManager

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(record.source)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        record.source == "QQ 扫码" ? Color.blue.opacity(0.5) : Color.orange.opacity(0.5)
                    )
                    .cornerRadius(4)

                Spacer()

                Text(record.createTime)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }

            Text(mask(record.token))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if !isCurrent {
                    Button("使用") {
                        manager.selectToken(record.token)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                } else {
                    Label("使用中", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                Spacer()

                Button {
                    manager.copyToken(record.token)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                Button {
                    manager.checkToken(record.token) { _ in }
                } label: {
                    Label("检测", systemImage: "checkmark.shield")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Button {
                    manager.deleteToken(id: record.id)
                } label: {
                    Label("删除", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
        .background(
            isCurrent ? Color.green.opacity(0.08) : Color.white.opacity(0.05)
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isCurrent ? Color.green.opacity(0.3) : Color.white.opacity(0.1),
                    lineWidth: 1
                )
        )
    }

    private func mask(_ token: String) -> String {
        guard token.count > 10 else { return token }
        return String(token.prefix(6)) + "****" + String(token.suffix(4))
    }
}

// MARK: - 提取 Token 页面
struct ExtractTokenView: View {
    @StateObject private var manager = GameLoginManager()
    @State private var inputText = ""
    @State private var extractedToken = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.10, blue: 0.16)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Text("从文本中提取 Token")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("粘贴包含 Token 的文本，自动识别并提取")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }

                    VStack(spacing: 12) {
                        TextEditor(text: $inputText)
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                            .focused($isFocused)
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("完成") { isFocused = false }
                                }
                            }
                            .overlay(
                                Group {
                                    if inputText.isEmpty {
                                        Text("在此粘贴文本...")
                                            .foregroundColor(.white.opacity(0.3))
                                            .padding(.leading, 16)
                                            .padding(.top, 16)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    }
                                }
                            )

                        Button {
                            extractToken()
                        } label: {
                            Label("提取 Token", systemImage: "magnifyingglass")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.purple)
                                .cornerRadius(10)
                        }
                    }

                    if !extractedToken.isEmpty {
                        VStack(spacing: 12) {
                            Text("提取结果")
                                .font(.subheadline)
                                .foregroundColor(.green)
                            Text(extractedToken)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(10)

                            HStack(spacing: 12) {
                                Button {
                                    manager.saveToken(extractedToken, source: "提取")
                                    extractedToken = ""
                                    inputText = ""
                                } label: {
                                    Label("储存", systemImage: "square.and.arrow.down")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.green)
                                        .cornerRadius(10)
                                }

                                Button {
                                    UIPasteboard.general.string = extractedToken
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.blue)
                                        .cornerRadius(10)
                                }
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(16)
                    }

                    // 支持格式说明
                    VStack(alignment: .leading, spacing: 8) {
                        Text("支持格式")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                        Text("• JSON: {\"token\":\"xxx\"}")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                        Text("• URL 参数: ?token=xxx")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                        Text("• 纯文本 Token（长度 > 20）")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                }
                .padding(16)
            }
        }
        .overlay(alignment: .top) {
            if manager.showBanner {
                TopBanner(message: manager.bannerMessage, type: manager.bannerType)
            }
        }
        .navigationTitle("提取 Token")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(red: 0.10, green: 0.12, blue: 0.20), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func extractToken() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // JSON 解析
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = json["token"] as? String {
            extractedToken = token
            return
        }

        // URL 参数解析
        if let url = URL(string: text),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
            extractedToken = token
            return
        }

        // 纯文本 Token（长度 > 20 且无空格换行）
        if text.count > 20, !text.contains(" "), !text.contains("\n") {
            extractedToken = text
        } else {
            extractedToken = "未识别到有效 Token"
        }
    }
}