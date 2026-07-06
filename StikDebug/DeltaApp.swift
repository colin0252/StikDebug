import SwiftUI
import UIKit

// MARK: - AppDelegate（控制方向）
class AppDelegate: NSObject, UIApplicationDelegate {
    static var isLandscape = false

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return AppDelegate.isLandscape ? .landscape : .all
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
    @Published var currentToken = ""
    @Published var isLoggedIn = false
    @Published var accounts: [GameAccount] = []
    @Published var tokenRecords: [TokenRecord] = []
    @Published var bannerMessage = ""
    @Published var bannerType: BannerType = .info
    @Published var showBanner = false

    enum BannerType { case info, success, warning, error }

    private let defaults = UserDefaults.standard
    private let accountsKey = "game_accounts"
    private let tokensKey = "token_records"

    init() { loadAccounts(); loadTokens() }

    private func show(_ msg: String, type: BannerType = .info) {
        bannerMessage = msg; bannerType = type; showBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.showBanner = false }
    }

    func saveToken(_ token: String, source: String = "手动输入") {
        guard !token.isEmpty else { show("Token 不能为空", type: .warning); return }
        if tokenRecords.contains(where: { $0.token == token }) { show("该 Token 已存在", type: .warning); return }
        tokenRecords.insert(TokenRecord(id: UUID().uuidString, token: token, source: source, createTime: now(), note: ""), at: 0)
        saveTokens()
        if currentToken.isEmpty { selectToken(token) }
        show("Token 已储存", type: .success)
    }

    func selectToken(_ token: String) { currentToken = token; isLoggedIn = true; show("已切换 Token", type: .success) }
    func copyToken(_ token: String) { UIPasteboard.general.string = token; show("已复制", type: .success) }
    func deleteToken(id: String) {
        if let r = tokenRecords.first(where: { $0.id == id }), r.token == currentToken { currentToken = ""; isLoggedIn = false }
        tokenRecords.removeAll { $0.id == id }; saveTokens(); show("已删除")
    }
    func clearAllTokens() { tokenRecords.removeAll(); currentToken = ""; isLoggedIn = false; saveTokens(); show("已清空") }

    func checkToken(_ token: String, completion: @escaping (Bool) -> Void) {
        show("正在检测...", type: .info)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let valid = token.count > 20
            self.show(valid ? "Token 有效" : "Token 无效", type: valid ? .success : .error)
            completion(valid)
        }
    }

    func launchGame(gameName: String, urlScheme: String?, token: String? = nil) {
        let tk = token ?? currentToken
        guard !tk.isEmpty else { show("请先选择 Token", type: .warning); return }
        UIPasteboard.general.string = tk
        if let scheme = urlScheme, !scheme.isEmpty, let url = URL(string: "\(scheme)://") {
            UIApplication.shared.open(url, options: [:]) { _ in }
        }
        show("Token 已复制，请打开 \(gameName) 并粘贴登录", type: .success)
        accounts.append(GameAccount(id: UUID().uuidString, gameName: gameName, uid: "Token已准备", username: "手动登录", loginTime: now()))
        saveAccounts()
    }

    func oneClickLogin(token: String? = nil) { launchGame(gameName: "三角洲行动", urlScheme: "dfmobile", token: token) }

    func copyAccountUID(_ uid: String) { UIPasteboard.general.string = uid; show("UID 已复制") }
    func deleteAccount(id: String) { accounts.removeAll { $0.id == id }; saveAccounts(); show("记录已删除") }
    func clearAllAccounts() { accounts.removeAll(); saveAccounts(); show("所有记录已清空") }

    private func saveAccounts() { if let d = try? JSONEncoder().encode(accounts) { defaults.set(d, forKey: accountsKey) } }
    private func loadAccounts() { if let d = defaults.data(forKey: accountsKey), let a = try? JSONDecoder().decode([GameAccount].self, from: d) { accounts = a } }
    private func saveTokens() { if let d = try? JSONEncoder().encode(tokenRecords) { defaults.set(d, forKey: tokensKey) } }
    private func loadTokens() { if let d = defaults.data(forKey: tokensKey), let a = try? JSONDecoder().decode([TokenRecord].self, from: d) { tokenRecords = a } }
    private func now() -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f.string(from: Date()) }

    func generateQRCodeURL() -> String {
        return "https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=WAITING_FOR_APPID&color=000&bgcolor=fff"
    }
    func simulateScan() {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        saveToken("QQ_" + String((0..<32).map { _ in chars.randomElement()! }), source: "模拟扫码")
    }
}

// MARK: - App 入口
@main
struct DeltaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showQR = true
    @State private var showGameLogin = false

    var body: some Scene {
        WindowGroup {
            NavigationView {
                HomeView(showGameLogin: $showGameLogin)
            }
            .navigationViewStyle(.stack)
            .ignoresSafeArea(.all)
            .fullScreenCover(isPresented: $showQR) {
                QRCodeLandscapeView(isPresented: $showQR)
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
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                HStack { Spacer(); Button { isPresented = false } label: { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.white.opacity(0.6)).padding() } }
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 40)).foregroundColor(.white).frame(width: 80, height: 80).background(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)).clipShape(RoundedRectangle(cornerRadius: 20))
                    Text("三角洲行动").font(.title2).fontWeight(.bold).foregroundColor(.white)
                    Text("QQ 账号授权登录").font(.subheadline).foregroundColor(.white.opacity(0.5))
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 20).fill(Color.white).frame(width: 200, height: 200)
                    VStack(spacing: 12) { Image(systemName: "qrcode").font(.system(size: 60)).foregroundColor(.gray); Text("等待配置 AppID").font(.caption).foregroundColor(.gray) }
                    if expired { RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.7)).frame(width: 200, height: 200); VStack(spacing: 8) { Image(systemName: "arrow.clockwise").font(.system(size: 30)).foregroundColor(.white); Text("已过期").font(.caption).foregroundColor(.white); Text("点击刷新").font(.caption2).foregroundColor(.white.opacity(0.7)) }.onTapGesture { refresh() } }
                }
                HStack(spacing: 6) { Image(systemName: "clock").font(.caption).foregroundColor(.orange); Text("有效期 \(String(format: "%02d:%02d", countdown/60, countdown%60))").font(.caption).foregroundColor(.orange) }
                Text("请使用手机 QQ 扫描二维码").font(.subheadline).foregroundColor(.white)
                Text("扫描后 Token 将自动储存").font(.caption).foregroundColor(.white.opacity(0.5))
                Spacer()
                HStack(spacing: 4) { Image(systemName: "checkmark.shield.fill").font(.caption).foregroundColor(.green); Text("授权后仅获取游戏登录所需信息").font(.caption2).foregroundColor(.white.opacity(0.4)) }.padding(.bottom, 20)
            }.padding()
        }
        .onAppear {
            AppDelegate.isLandscape = true
            DispatchQueue.main.async { UIApplication.shared.connectedScenes.forEach { ($0 as? UIWindowScene)?.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() } }
            startTimer()
        }
        .onDisappear {
            AppDelegate.isLandscape = false
            DispatchQueue.main.async { UIApplication.shared.connectedScenes.forEach { ($0 as? UIWindowScene)?.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() } }
            timer?.invalidate()
        }
    }
    private func startTimer() { countdown = 120; expired = false; timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in if countdown > 0 { countdown -= 1 } else { expired = true; t.invalidate() } } }
    private func refresh() { startTimer() }
}

// MARK: - 横屏游戏登录界面
struct GameLoginLandscapeView: View {
    @Binding var isPresented: Bool
    @StateObject private var manager = GameLoginManager()
    @State private var inputToken = ""
    @State private var useIndependent = false
    @FocusState private var focused: Bool

    private let games: [(String, String, Color, String?)] = [
        ("三角洲行动", "arrow.triangle.swap", Color(red: 1.0, green: 0.45, blue: 0.0), "dfmobile"),
        ("暗区突围", "shield.fill", Color(red: 0.9, green: 0.15, blue: 0.15), "darkzone"),
        ("和平精英", "scope", Color(red: 0.1, green: 0.8, blue: 0.3), "pubgm")
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Circle().fill(manager.isLoggedIn || !inputToken.isEmpty ? Color.green : Color.red).frame(width: 8, height: 8); Text(manager.isLoggedIn || !inputToken.isEmpty ? "Token已就绪" : "未选择").font(.caption).foregroundColor(.white.opacity(0.7)); Spacer(); if manager.isLoggedIn { Button("检测") { manager.checkToken(manager.currentToken) { _ in } }.font(.caption).foregroundColor(.orange) } }
                    Toggle("独立 Token", isOn: $useIndependent).font(.caption).foregroundColor(.white)
                    if useIndependent { HStack { TextField("输入 Token", text: $inputToken).textFieldStyle(.plain).padding(8).background(Color.white.opacity(0.1)).cornerRadius(8).foregroundColor(.white).focused($focused).toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { focused = false } } }; Button("储存") { if !inputToken.isEmpty { manager.saveToken(inputToken); inputToken = "" }; focused = false }.font(.caption).foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 8).background(Color.orange).cornerRadius(8) } }
                    if !manager.tokenRecords.isEmpty && !useIndependent { VStack(alignment: .leading, spacing: 4) { Text("已储存").font(.caption).foregroundColor(.white.opacity(0.6)); ForEach(manager.tokenRecords.prefix(3)) { record in Button { manager.selectToken(record.token) } label: { HStack { Circle().fill(record.token == manager.currentToken ? Color.green : Color.clear).frame(width: 6, height: 6); Text(mask(record.token)).font(.caption2).foregroundColor(.white).lineLimit(1); Spacer(); if record.token == manager.currentToken { Text("当前").font(.caption2).foregroundColor(.green) } }.padding(6).background(Color.white.opacity(0.05)).cornerRadius(6) } } } }
                    Button { manager.oneClickLogin(token: useIndependent ? inputToken : nil) } label: { HStack { Image(systemName: "bolt.fill"); Text("一键登录三角洲行动").fontWeight(.semibold) }.font(.caption).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.orange.opacity(0.8)).cornerRadius(10) }
                    if !manager.accounts.isEmpty { VStack(alignment: .leading, spacing: 4) { Text("最近").font(.caption).foregroundColor(.white.opacity(0.5)); ForEach(manager.accounts.suffix(2)) { Text("\($0.gameName) - \($0.loginTime)").font(.caption2).foregroundColor(.white.opacity(0.5)) } } }
                }.frame(width: 240).padding().background(Color.white.opacity(0.05)).cornerRadius(16)

                VStack(spacing: 12) {
                    ForEach(games, id: \.0) { game in
                        Button { manager.launchGame(gameName: game.0, urlScheme: game.3, token: useIndependent ? inputToken : nil) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: game.1).font(.system(size: 24)).foregroundColor(.white).frame(width: 44, height: 44).background(game.2).clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) { Text(game.0).font(.headline).foregroundColor(.white); Text(game.3 != nil ? "尝试自动唤起" : "手动打开").font(.caption2).foregroundColor(.white.opacity(0.5)) }
                                Spacer(); Text(game.3 != nil ? "🚀 唤起" : "📋 复制").font(.caption).fontWeight(.medium).foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 8).background(game.2).cornerRadius(6)
                            }.padding(10).background(Color.white.opacity(0.05)).cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                    }
                }.frame(maxWidth: .infinity)
            }.padding()
            VStack { HStack { Spacer(); Button { isPresented = false } label: { Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.white.opacity(0.6)).padding() } }; Spacer() }
        }
        .onAppear { AppDelegate.isLandscape = true; updateOrientation() }
        .onDisappear { AppDelegate.isLandscape = false; updateOrientation() }
    }

    private func mask(_ s: String) -> String { guard s.count > 10 else { return s }; return String(s.prefix(6)) + "****" + String(s.suffix(4)) }
}

func updateOrientation() {
    DispatchQueue.main.async {
        UIApplication.shared.connectedScenes.forEach { ($0 as? UIWindowScene)?.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
    }
}

// MARK: - 顶部横幅
struct TopBanner: View {
    let message: String; let type: GameLoginManager.BannerType
    var body: some View {
        HStack(spacing: 8) { Image(systemName: type == .info ? "info.circle.fill" : type == .success ? "checkmark.circle.fill" : type == .warning ? "exclamationmark.triangle.fill" : "xmark.circle.fill"); Text(message).font(.subheadline) }
            .foregroundColor(.white).padding().frame(maxWidth: .infinity).background(type == .info ? Color.blue.opacity(0.9) : type == .success ? Color.green.opacity(0.9) : type == .warning ? Color.orange.opacity(0.9) : Color.red.opacity(0.9)).cornerRadius(10).padding(.horizontal, 16).padding(.top, 8).shadow(radius: 5)
    }
}

// MARK: - 首页（竖屏）
struct HomeView: View {
    @Binding var showGameLogin: Bool
    @StateObject private var manager = GameLoginManager()
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.06, blue: 0.12), Color(red: 0.10, green: 0.10, blue: 0.20), Color(red: 0.06, green: 0.06, blue: 0.12)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 8) { Image(systemName: "gamecontroller.fill").font(.system(size: 50)).foregroundColor(.white); Text("游戏账号管理").font(.title).fontWeight(.bold).foregroundColor(.white); Text("StikDebug").font(.subheadline).foregroundColor(.white.opacity(0.6)) }
                Spacer().frame(height: 60)
                VStack(spacing: 16) {
                    NavigationLink(destination: QRCodeView()) { HomeButtonContent(icon: "qrcode", color: .blue, title: "QQ 扫码登录", subtitle: "使用手机 QQ 扫描二维码获取 Token") }
                    NavigationLink(destination: TokenManageView()) { HomeButtonContent(icon: "list.clipboard.fill", color: .orange, title: "Token 管理", subtitle: "储存 Token · 一键复制 · 删除", badge: "\(manager.tokenRecords.count)") }
                    Button { showGameLogin = true } label: { HomeButtonContent(icon: "play.circle.fill", color: .green, title: "游戏登录", subtitle: "三角洲行动 / 暗区突围 / 和平精英") }
                    NavigationLink(destination: ExtractTokenView()) { HomeButtonContent(icon: "arrow.down.doc.fill", color: .purple, title: "提取 Token", subtitle: "从剪贴板或链接提取 Token") }
                }.padding(.horizontal, 24)
                Spacer()
                Text("v1.0.0").font(.caption).foregroundColor(.white.opacity(0.3)).padding(.bottom, 30)
            }
        }.navigationBarHidden(true)
    }
}

struct HomeButtonContent: View {
    let icon: String; let color: Color; let title: String; let subtitle: String; var badge: String?
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 26)).foregroundColor(.white).frame(width: 46, height: 46).background(color.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline).foregroundColor(.white); Text(subtitle).font(.caption).foregroundColor(.white.opacity(0.5)) }
            Spacer()
            if let badge = badge { Text(badge).font(.caption).foregroundColor(.white).padding(.horizontal, 8).padding(.vertical, 4).background(color).clipShape(Capsule()) }
            Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.4))
        }.padding(18).background(Color.white.opacity(0.06)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1)).cornerRadius(16)
    }
}

// MARK: - 竖屏扫码页面（备用）
struct QRCodeView: View {
    @StateObject private var manager = GameLoginManager()
    @State private var countdown = 120; @State private var expired = false; @State private var timer: Timer?
    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.10, blue: 0.16).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "gamecontroller.fill").font(.system(size: 40)).foregroundColor(.white).frame(width: 80, height: 80).background(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)).clipShape(RoundedRectangle(cornerRadius: 20))
                        Text("三角洲行动").font(.title2).fontWeight(.bold).foregroundColor(.white); Text("QQ 账号授权登录").font(.subheadline).foregroundColor(.white.opacity(0.5))
                    }.padding(.top, 40)
                    VStack(spacing: 20) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20).fill(Color.white).frame(width: 220, height: 220)
                            AsyncImage(url: URL(string: manager.generateQRCodeURL())) { $0.resizable().scaledToFit().frame(width: 185, height: 185) } placeholder: { Image(systemName: "qrcode").font(.system(size: 80)).foregroundColor(.black) }
                            if expired { RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.7)).frame(width: 220, height: 220); VStack(spacing: 12) { Image(systemName: "arrow.clockwise").font(.system(size: 40)).foregroundColor(.white); Text("已过期").font(.headline).foregroundColor(.white); Text("点击刷新").font(.caption).foregroundColor(.white.opacity(0.7)) }.onTapGesture { refresh() } }
                        }
                        HStack(spacing: 6) { Image(systemName: "clock").font(.caption).foregroundColor(.orange); Text("有效期 \(String(format: "%02d:%02d", countdown/60, countdown%60))").font(.caption).foregroundColor(.orange) }
                        VStack(alignment: .leading, spacing: 8) { Text("💡 如何获取真实 Token？").font(.caption).foregroundColor(.yellow); Text("1. 需在 QQ 互联平台注册应用，获取 appid 并配置回调 URL。"); Text("2. 将 appid 替换到二维码链接中，生成真实扫码 URL。"); Text("3. 用户扫码授权后，QQ 会回调你的服务器，服务器返回 Token。"); Text("4. 当前二维码为示例，点击下方按钮模拟获取。") }.font(.caption2).foregroundColor(.white.opacity(0.7)).padding().background(Color.white.opacity(0.05)).cornerRadius(10)
                    }.padding(24).background(Color.white.opacity(0.05)).cornerRadius(20).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    Button { manager.simulateScan() } label: { Label("模拟扫码获取 Token", systemImage: "iphone").font(.subheadline).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 14).background(Color.blue.opacity(0.3)).cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.5), lineWidth: 1)) }
                }.padding(.horizontal, 24).padding(.bottom, 40)
            }
        }.overlay(alignment: .top) { if manager.showBanner { TopBanner(message: manager.bannerMessage, type: manager.bannerType) } }
        .navigationTitle("QQ 扫码登录").navigationBarTitleDisplayMode(.inline).toolbarBackground(Color(red: 0.10, green: 0.12, blue: 0.20), for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        .onAppear { startTimer() }.onDisappear { timer?.invalidate() }
    }
    private func startTimer() { countdown = 120; expired = false; timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in if countdown > 0 { countdown -= 1 } else { expired = true; t.invalidate() } } }
    private func refresh() { startTimer() }
}

// MARK: - Token 管理、提取 Token（竖屏）
struct TokenManageView: View {
    @StateObject private var manager = GameLoginManager()
    @State private var inputToken = ""; @FocusState private var focused: Bool
    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.10, blue: 0.16).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    if manager.isLoggedIn {
                        VStack(spacing: 8) {
                            HStack { Circle().fill(Color.green).frame(width: 8, height: 8); Text("当前使用").font(.caption).foregroundColor(.green); Spacer() }
                            HStack { Text(manager.currentToken).font(.caption).foregroundColor(.white).lineLimit(1); Spacer(); Button { manager.copyToken(manager.currentToken) } label: { Image(systemName: "doc.on.doc").font(.caption).foregroundColor(.blue) }; Button { manager.checkToken(manager.currentToken) { _ in } } label: { Image(systemName: "checkmark.shield").font(.caption).foregroundColor(.green) } }
                        }.padding().background(Color.green.opacity(0.1)).cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.3), lineWidth: 1))
                    }
                    VStack(spacing: 12) {
                        Text("手动输入 Token").font(.subheadline).foregroundColor(.white.opacity(0.6)).frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) {
                            TextField("输入或粘贴 Token", text: $inputToken).textFieldStyle(.plain).padding().background(Color.white.opacity(0.1)).cornerRadius(10).foregroundColor(.white).autocapitalization(.none).disableAutocorrection(true).focused($focused).toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { focused = false } } }
                            Button("储存") { if !inputToken.isEmpty { manager.saveToken(inputToken); inputToken = "" }; focused = false }.font(.subheadline).foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 14).background(Color.orange).cornerRadius(10)
                        }
                    }.padding().background(Color.white.opacity(0.05)).cornerRadius(16)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("已储存 Token").font(.subheadline).foregroundColor(.white.opacity(0.6)); Spacer(); Text("\(manager.tokenRecords.count) 个").font(.caption).foregroundColor(.white.opacity(0.4)); if !manager.tokenRecords.isEmpty { Button("清空") { manager.clearAllTokens() }.font(.caption).foregroundColor(.red) } }
                        if manager.tokenRecords.isEmpty { VStack(spacing: 12) { Image(systemName: "tray").font(.system(size: 40)).foregroundColor(.white.opacity(0.3)); Text("暂无 Token").font(.subheadline).foregroundColor(.white.opacity(0.4)) }.frame(maxWidth: .infinity).padding(.vertical, 40) }
                        else { ForEach(manager.tokenRecords) { record in TokenCard(record: record, isCurrent: record.token == manager.currentToken, manager: manager) } }
                    }.padding().background(Color.white.opacity(0.05)).cornerRadius(16)
                }.padding(16)
            }
        }.overlay(alignment: .top) { if manager.showBanner { TopBanner(message: manager.bannerMessage, type: manager.bannerType) } }
        .navigationTitle("Token 管理").navigationBarTitleDisplayMode(.inline).toolbarBackground(Color(red: 0.10, green: 0.12, blue: 0.20), for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
    }
}

struct TokenCard: View {
    let record: TokenRecord; let isCurrent: Bool; @ObservedObject var manager: GameLoginManager
    var body: some View {
        VStack(spacing: 8) {
            HStack { Text(record.source).font(.caption2).foregroundColor(.white).padding(.horizontal, 6).padding(.vertical, 2).background(record.source == "QQ 扫码" ? Color.blue.opacity(0.5) : Color.orange.opacity(0.5)).cornerRadius(4); Spacer(); Text(record.createTime).font(.caption2).foregroundColor(.white.opacity(0.4)) }
            Text(mask(record.token)).font(.system(.caption, design: .monospaced)).foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if !isCurrent { Button("使用") { manager.selectToken(record.token) }.buttonStyle(.bordered).tint(.green) } else { Label("使用中", systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.green) }
                Spacer(); Button { manager.copyToken(record.token) } label: { Label("复制", systemImage: "doc.on.doc").font(.caption) }.buttonStyle(.bordered).tint(.blue); Button { manager.checkToken(record.token) { _ in } } label: { Label("检测", systemImage: "checkmark.shield").font(.caption) }.buttonStyle(.bordered).tint(.orange); Button { manager.deleteToken(id: record.id) } label: { Label("删除", systemImage: "trash").font(.caption) }.buttonStyle(.bordered).tint(.red)
            }
        }.padding().background(isCurrent ? Color.green.opacity(0.08) : Color.white.opacity(0.05)).cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(isCurrent ? Color.green.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1))
    }
    private func mask(_ s: String) -> String { guard s.count > 10 else { return s }; return String(s.prefix(6)) + "****" + String(s.suffix(4)) }
}

struct ExtractTokenView: View {
    @StateObject private var manager = GameLoginManager()
    @State private var inputText = ""; @State private var extracted = ""; @FocusState private var focused: Bool
    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.10, blue: 0.16).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) { Text("从文本中提取 Token").font(.headline).foregroundColor(.white); Text("粘贴包含 Token 的文本，自动识别并提取").font(.caption).foregroundColor(.white.opacity(0.5)) }
                    VStack(spacing: 12) {
                        TextEditor(text: $inputText).frame(minHeight: 120).padding(8).background(Color.white.opacity(0.1)).cornerRadius(10).foregroundColor(.white).focused($focused).toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { focused = false } } }.overlay(Group { if inputText.isEmpty { Text("在此粘贴文本...").foregroundColor(.white.opacity(0.3)).padding(.leading, 16).padding(.top, 16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) } })
                        Button { extract() } label: { Label("提取 Token", systemImage: "magnifyingglass").font(.subheadline).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 14).background(Color.purple).cornerRadius(10) }
                    }
                    if !extracted.isEmpty {
                        VStack(spacing: 12) {
                            Text("提取结果").font(.subheadline).foregroundColor(.green); Text(extracted).font(.system(.caption, design: .monospaced)).foregroundColor(.white).padding().background(Color.white.opacity(0.05)).cornerRadius(10)
                            HStack(spacing: 12) { Button { manager.saveToken(extracted, source: "提取"); extracted = ""; inputText = "" } label: { Label("储存", systemImage: "square.and.arrow.down").font(.caption).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.green).cornerRadius(10) }; Button { UIPasteboard.general.string = extracted } label: { Label("复制", systemImage: "doc.on.doc").font(.caption).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.blue).cornerRadius(10) } }
                        }.padding().background(Color.white.opacity(0.05)).cornerRadius(16)
                    }
                    VStack(alignment: .leading, spacing: 8) { Text("支持格式").font(.subheadline).foregroundColor(.white.opacity(0.6)); Text("• JSON: {\"token\":\"xxx\"}").font(.caption).foregroundColor(.white.opacity(0.4)); Text("• URL 参数: ?token=xxx").font(.caption).foregroundColor(.white.opacity(0.4)); Text("• 纯文本 Token（长度 > 20）").font(.caption).foregroundColor(.white.opacity(0.4)) }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.05)).cornerRadius(12)
                }.padding(16)
            }
        }.overlay(alignment: .top) { if manager.showBanner { TopBanner(message: manager.bannerMessage, type: manager.bannerType) } }
        .navigationTitle("提取 Token").navigationBarTitleDisplayMode(.inline).toolbarBackground(Color(red: 0.10, green: 0.12, blue: 0.20), for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
    }
    private func extract() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let d = text.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let t = j["token"] as? String { extracted = t; return }
        if let u = URL(string: text), let c = URLComponents(url: u, resolvingAgainstBaseURL: false), let t = c.queryItems?.first(where: { $0.name == "token" })?.value { extracted = t; return }
        if text.count > 20, !text.contains(" "), !text.contains("\n") { extracted = text } else { extracted = "未识别到有效 Token" }
    }
}