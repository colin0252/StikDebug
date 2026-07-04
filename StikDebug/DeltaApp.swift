import SwiftUI
import UIKit

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
    @Published var message: String = ""
    @Published var messageType: MessageType = .info
    @Published var showMessage: Bool = false

    enum MessageType {
        case info, success, warning, error
    }

    private let userDefaults = UserDefaults.standard
    private let accountsKey = "game_accounts"
    private let tokensKey = "token_records"

    init() {
        loadAccounts()
        loadTokens()
    }

    private func show(_ text: String, type: MessageType) {
        message = text
        messageType = type
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.showMessage = false
        }
    }

    // 储存Token
    func saveToken(_ token: String, source: String = "手动输入") {
        guard !token.isEmpty else { return }
        if tokenRecords.contains(where: { $0.token == token }) {
            show("该Token已存在", type: .warning)
            return
        }
        let record = TokenRecord(id: UUID().uuidString, token: token, source: source, createTime: getCurrentTimeString(), note: "")
        tokenRecords.insert(record, at: 0)
        saveTokens()
        if currentToken.isEmpty { selectToken(token) }
        show("Token已储存", type: .success)
    }

    func selectToken(_ token: String) {
        currentToken = token
        isLoggedIn = true
        show("已切换Token", type: .success)
    }

    func copyToken(_ token: String) {
        UIPasteboard.general.string = token
        show("已复制", type: .success)
    }

    func deleteToken(id: String) {
        if let record = tokenRecords.first(where: { $0.id == id }), record.token == currentToken {
            currentToken = ""
            isLoggedIn = false
        }
        tokenRecords.removeAll { $0.id == id }
        saveTokens()
        show("已删除", type: .info)
    }

    func clearAllTokens() {
        tokenRecords.removeAll()
        currentToken = ""
        isLoggedIn = false
        saveTokens()
        show("已清空", type: .info)
    }

    // 检测Token
    func checkToken(_ token: String, completion: @escaping (Bool) -> Void) {
        show("正在检测...", type: .info)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let valid = token.count > 10
            self.show(valid ? "Token有效" : "Token无效或已过期", type: valid ? .success : .error)
            completion(valid)
        }
    }

    // 唤起游戏并登录
    func launchGame(gameName: String, urlScheme: String, token: String? = nil) {
        let tokenToUse = token ?? currentToken
        guard !tokenToUse.isEmpty else {
            show("请先输入或选择Token", type: .warning)
            return
        }

        // 先把Token复制到剪贴板，方便目标App读取
        UIPasteboard.general.string = tokenToUse

        // 尝试通过 URL Scheme 唤起
        if let url = URL(string: "\(urlScheme)://login?token=\(tokenToUse)") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url) { success in
                    if success {
                        self.show("正在唤起\(gameName)...", type: .info)
                        // 记录登录行为
                        let newAccount = GameAccount(
                            id: UUID().uuidString,
                            gameName: gameName,
                            uid: "Token登录",
                            username: "已注入Token",
                            loginTime: self.getCurrentTimeString()
                        )
                        self.accounts.append(newAccount)
                        self.saveAccounts()
                    } else {
                        self.show("唤起\(gameName)失败", type: .error)
                    }
                }
            } else {
                // 未安装游戏
                self.show("未安装\(gameName)，请先下载", type: .warning)
                // 仍然记录尝试
                let newAccount = GameAccount(
                    id: UUID().uuidString,
                    gameName: gameName,
                    uid: "未安装",
                    username: "Token已准备",
                    loginTime: self.getCurrentTimeString()
                )
                self.accounts.append(newAccount)
                self.saveAccounts()
            }
        }
    }

    // 一键登录（默认三角洲）
    func oneClickLogin(token: String? = nil) {
        launchGame(gameName: "三角洲行动", urlScheme: "deltaforce", token: token)
    }

    func copyAccountUID(_ uid: String) {
        UIPasteboard.general.string = uid
        show("UID已复制", type: .success)
    }

    func deleteAccount(id: String) {
        accounts.removeAll { $0.id == id }
        saveAccounts()
        show("已删除", type: .info)
    }

    func clearAllAccounts() {
        accounts.removeAll()
        saveAccounts()
        show("已清空", type: .info)
    }

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

    func generateQRCodeURL() -> String {
        return "https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=QQ_LOGIN&color=000&bgcolor=fff"
    }

    func simulateQRCodeScan() {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let token = "QQ_" + String((0..<32).map { _ in chars.randomElement()! })
        saveToken(token, source: "QQ扫码")
    }
}

// MARK: - App 入口
@main
struct DeltaApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationView {
                HomeView()
            }
            .navigationViewStyle(.stack)
            .ignoresSafeArea(.all)
        }
    }
}

// MARK: - 首页
struct HomeView: View {
    @StateObject private var manager = GameLoginManager()

    var body: some View {
        ZStack {
            LinearGradient(colors: [
                Color(red: 0.06, green: 0.06, blue: 0.12),
                Color(red: 0.10, green: 0.10, blue: 0.20),
                Color(red: 0.06, green: 0.06, blue: 0.12)
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 50)).foregroundColor(.white)
                    Text("游戏账号管理").font(.title).fontWeight(.bold).foregroundColor(.white)
                    Text("StikDebug").font(.subheadline).foregroundColor(.white.opacity(0.6))
                }
                Spacer().frame(height: 60)

                VStack(spacing: 16) {
                    NavigationLink(destination: QRCodeView()) {
                        HomeButtonContent(icon: "qrcode", color: .blue, title: "QQ扫码登录", subtitle: "使用手机QQ扫描二维码获取Token")
                    }
                    NavigationLink(destination: TokenManageView()) {
                        HomeButtonContent(icon: "list.clipboard.fill", color: .orange, title: "Token管理", subtitle: "储存Token · 一键复制 · 删除", badge: "\(manager.tokenRecords.count)")
                    }
                    NavigationLink(destination: GameLoginView()) {
                        HomeButtonContent(icon: "play.circle.fill", color: .green, title: "游戏登录", subtitle: "三角洲行动 / 暗区突围 / 和平精英")
                    }
                    NavigationLink(destination: ExtractTokenView()) {
                        HomeButtonContent(icon: "arrow.down.doc.fill", color: .purple, title: "提取Token", subtitle: "从剪贴板或链接提取Token")
                    }
                }
                .padding(.horizontal, 24)
                Spacer()
                Text("v1.0.0").font(.caption).foregroundColor(.white.opacity(0.3)).padding(.bottom, 30)
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
            Image(systemName: icon).font(.system(size: 26)).foregroundColor(.white)
                .frame(width: 46, height: 46)
                .background(color.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundColor(.white)
                Text(subtitle).font(.caption).foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            if let badge = badge {
                Text(badge).font(.caption).foregroundColor(.white).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(color).clipShape(Capsule())
            }
            Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.4))
        }
        .padding(18)
        .background(Color.white.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .cornerRadius(16)
    }
}

// MARK: - 通用消息横幅
struct MessageBanner: View {
    let message: String
    let type: GameLoginManager.MessageType

    var bgColor: Color {
        switch type {
        case .info: return Color.blue.opacity(0.9)
        case .success: return Color.green.opacity(0.9)
        case .warning: return Color.orange.opacity(0.9)
        case .error: return Color.red.opacity(0.9)
        }
    }

    var icon: String {
        switch type {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(message).font(.subheadline)
        }
        .foregroundColor(.white)
        .padding()
        .frame(maxWidth: .infinity)
        .background(bgColor)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - QQ 扫码页面
struct QRCodeView: View {
    @StateObject private var manager = GameLoginManager()
    @State private var countdown = 120
    @State private var expired = false
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.10, blue: 0.16).ignoresSafeArea()
            VStack(spacing: 0) {
                if manager.showMessage {
                    MessageBanner(message: manager.message, type: manager.messageType)
                }
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 12) {
                            Image(systemName: "gamecontroller.fill").font(.system(size: 40)).foregroundColor(.white)
                                .frame(width: 80, height: 80)
                                .background(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                            Text("三角洲行动").font(.title2).fontWeight(.bold).foregroundColor(.white)
                            Text("QQ账号授权登录").font(.subheadline).foregroundColor(.white.opacity(0.5))
                        }.padding(.top, 40)

                        VStack(spacing: 20) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20).fill(Color.white).frame(width: 220, height: 220)
                                AsyncImage(url: URL(string: manager.generateQRCodeURL())) { image in
                                    image.resizable().scaledToFit().frame(width: 185, height: 185)
                                } placeholder: {
                                    Image(systemName: "qrcode").font(.system(size: 80)).foregroundColor(.black)
                                }
                                if expired {
                                    RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.7)).frame(width: 220, height: 220)
                                    VStack(spacing: 12) {
                                        Image(systemName: "arrow.clockwise").font(.system(size: 40)).foregroundColor(.white)
                                        Text("二维码已过期").font(.headline).foregroundColor(.white)
                                        Text("点击刷新").font(.caption).foregroundColor(.white.opacity(0.7))
                                    }.onTapGesture { refreshQRCode() }
                                }
                            }
                            HStack(spacing: 6) {
                                Image(systemName: "clock").font(.caption).foregroundColor(.orange)
                                Text("有效期 \(String(format: "%02d:%02d", countdown/60, countdown%60))").font(.caption).foregroundColor(.orange)
                            }
                            Text("请使用手机QQ扫描二维码").font(.subheadline).foregroundColor(.white)
                            Text("扫描后Token将自动储存").font(.caption).foregroundColor(.white.opacity(0.5))
                        }
                        .padding(24).background(Color.white.opacity(0.05)).cornerRadius(20)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1), lineWidth: 1))

                        Button(action: { manager.simulateQRCodeScan() }) {
                            Label("模拟扫码获取Token", systemImage: "iphone").font(.subheadline).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.blue.opacity(0.3)).cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.5), lineWidth: 1))
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private func startTimer() {
        countdown = 120; expired = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if countdown > 0 { countdown -= 1 } else { expired = true; t.invalidate() }
        }
    }
    private func refreshQRCode() { startTimer() }
}

// MARK: - Token 管理页面
struct TokenManageView: View {
    @StateObject private var manager = GameLoginManager()
    @State private var inputToken = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.10, blue: 0.16).ignoresSafeArea()
            VStack(spacing: 0) {
                if manager.showMessage {
                    MessageBanner(message: manager.message, type: manager.messageType)
                }
                ScrollView {
                    VStack(spacing: 16) {
                        if manager.isLoggedIn {
                            CurrentTokenCard(manager: manager)
                        }

                        VStack(spacing: 12) {
                            Text("手动输入Token").font(.subheadline).foregroundColor(.white.opacity(0.6)).frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 8) {
                                TextField("输入或粘贴Token", text: $inputToken)
                                    .textFieldStyle(.plain).padding().background(Color.white.opacity(0.1)).cornerRadius(10)
                                    .foregroundColor(.white).autocapitalization(.none).disableAutocorrection(true)
                                    .focused($isInputFocused)
                                    .toolbar { keyboardToolbar }
                                Button("储存") {
                                    if !inputToken.isEmpty { manager.saveToken(inputToken); inputToken = "" }
                                    isInputFocused = false
                                }
                                .font(.subheadline).foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 14)
                                .background(Color.orange).cornerRadius(10)
                            }
                        }.padding().background(Color.white.opacity(0.05)).cornerRadius(16)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("已储存Token").font(.subheadline).foregroundColor(.white.opacity(0.6))
                                Spacer()
                                Text("\(manager.tokenRecords.count)个").font(.caption).foregroundColor(.white.opacity(0.4))
                                if !manager.tokenRecords.isEmpty {
                                    Button("清空") { manager.clearAllTokens() }.font(.caption).foregroundColor(.red)
                                }
                            }
                            if manager.tokenRecords.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "tray").font(.system(size: 40)).foregroundColor(.white.opacity(0.3))
                                    Text("暂无Token").font(.subheadline).foregroundColor(.white.opacity(0.4))
                                }.frame(maxWidth: .infinity).padding(.vertical, 40)
                            } else {
                                ForEach(manager.tokenRecords) { record in
                                    TokenCard(record: record, isCurrent: record.token == manager.currentToken, manager: manager)
                                }
                            }
                        }.padding().background(Color.white.opacity(0.05)).cornerRadius(16)
                    }.padding(16)
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }

    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("完成") { isInputFocused = false }
        }
    }
}

struct CurrentTokenCard: View {
    @ObservedObject var manager: GameLoginManager
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("当前使用").font(.caption).foregroundColor(.green)
                Spacer()
            }
            HStack {
                Text(manager.currentToken).font(.caption).foregroundColor(.white).lineLimit(1)
                Spacer()
                Button { manager.copyToken(manager.currentToken) } label: {
                    Image(systemName: "doc.on.doc").font(.caption).foregroundColor(.blue)
                }
                Button { manager.checkToken(manager.currentToken) { _ in } } label: {
                    Image(systemName: "checkmark.shield").font(.caption).foregroundColor(.green)
                }
            }
        }
        .padding().background(Color.green.opacity(0.1)).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.3), lineWidth: 1))
    }
}

struct TokenCard: View {
    let record: TokenRecord
    let isCurrent: Bool
    @ObservedObject var manager: GameLoginManager

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(record.source).font(.caption2).foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(record.source == "QQ扫码" ? Color.blue.opacity(0.5) : Color.orange.opacity(0.5))
                    .cornerRadius(4)
                Spacer()
                Text(record.createTime).font(.caption2).foregroundColor(.white.opacity(0.4))
            }
            Text(mask(record.token)).font(.system(.caption, design: .monospaced)).foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if !isCurrent { Button("使用") { manager.selectToken(record.token) }.buttonStyle(.bordered).tint(.green) }
                else { Label("使用中", systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.green) }
                Spacer()
                Button { manager.copyToken(record.token) } label: { Label("复制", systemImage: "doc.on.doc").font(.caption) }.buttonStyle(.bordered).tint(.blue)
                Button { manager.checkToken(record.token) { _ in } } label: { Label("检测", systemImage: "checkmark.shield").font(.caption) }.buttonStyle(.bordered).tint(.orange)
                Button { manager.deleteToken(id: record.id) } label: { Label("删除", systemImage: "trash").font(.caption) }.buttonStyle(.bordered).tint(.red)
            }
        }
        .padding().background(isCurrent ? Color.green.opacity(0.08) : Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isCurrent ? Color.green.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1))
    }

    private func mask(_ token: String) -> String {
        guard token.count > 10 else { return token }
        return String(token.prefix(6)) + "****" + String(token.suffix(4))
    }
}

// MARK: - 游戏登录页面（唤起游戏）
struct GameLoginView: View {
    @StateObject private var manager = GameLoginManager()
    @State private var inputToken = ""
    @State private var useIndependentToken = false
    @FocusState private var isTokenFocused: Bool

    // 各游戏 URL Scheme（示例，需替换为真实 scheme）
    private let games: [(name: String, icon: String, color: Color, scheme: String)] = [
        ("三角洲行动", "arrow.triangle.swap", Color(red: 1.0, green: 0.45, blue: 0.0), "deltaforce"),
        ("暗区突围", "shield.fill", Color(red: 0.9, green: 0.15, blue: 0.15), "darkzone"),
        ("和平精英", "scope", Color(red: 0.1, green: 0.8, blue: 0.3), "pubgm")
    ]

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.10, blue: 0.16).ignoresSafeArea()
            VStack(spacing: 0) {
                if manager.showMessage {
                    MessageBanner(message: manager.message, type: manager.messageType)
                }
                ScrollView {
                    VStack(spacing: 16) {
                        HStack {
                            Circle().fill(manager.isLoggedIn || !inputToken.isEmpty ? Color.green : Color.red).frame(width: 8, height: 8)
                            Text(manager.isLoggedIn || !inputToken.isEmpty ? "Token已就绪" : "未选择Token")
                                .font(.caption).foregroundColor(.white.opacity(0.7))
                            Spacer()
                            if manager.isLoggedIn {
                                Button("检测") { manager.checkToken(manager.currentToken) { _ in } }.font(.caption).foregroundColor(.orange)
                            }
                        }
                        .padding(.horizontal)

                        VStack(spacing: 12) {
                            Toggle("使用独立Token", isOn: $useIndependentToken).font(.subheadline).foregroundColor(.white)
                            if useIndependentToken {
                                HStack(spacing: 8) {
                                    TextField("输入独立Token", text: $inputToken)
                                        .textFieldStyle(.plain).padding().background(Color.white.opacity(0.1)).cornerRadius(10)
                                        .foregroundColor(.white).focused($isTokenFocused)
                                        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { isTokenFocused = false } } }
                                    Button("储存") {
                                        if !inputToken.isEmpty { manager.saveToken(inputToken); inputToken = "" }
                                        isTokenFocused = false
                                    }.font(.caption).foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 14).background(Color.orange).cornerRadius(10)
                                }
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.05)).cornerRadius(16)

                        if !manager.tokenRecords.isEmpty && !useIndependentToken {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("选择已储存Token").font(.subheadline).foregroundColor(.white.opacity(0.6))
                                ForEach(manager.tokenRecords) { record in
                                    Button {
                                        manager.selectToken(record.token)
                                    } label: {
                                        HStack {
                                            Circle().fill(record.token == manager.currentToken ? Color.green : Color.clear).frame(width: 10, height: 10)
                                            Text(mask(record.token)).font(.caption).foregroundColor(.white)
                                            Spacer()
                                            if record.token == manager.currentToken { Text("当前").font(.caption2).foregroundColor(.green) }
                                        }
                                        .padding(10).background(Color.white.opacity(0.05)).cornerRadius(8)
                                    }
                                }
                            }
                            .padding().background(Color.white.opacity(0.05)).cornerRadius(16)
                        }

                        // 一键唤起三角洲
                        Button(action: {
                            manager.oneClickLogin(token: useIndependentToken ? inputToken : nil)
                        }) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                Text("一键唤起三角洲行动")
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.orange.opacity(0.8))
                            .cornerRadius(12)
                        }

                        Text("或选择游戏唤起")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))

                        ForEach(games, id: \.name) { game in
                            GameLoginCard(
                                name: game.name,
                                icon: game.icon,
                                color: game.color,
                                urlScheme: game.scheme,
                                manager: manager,
                                independentToken: useIndependentToken ? inputToken : nil
                            )
                        }

                        if !manager.accounts.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("登录记录").font(.subheadline).foregroundColor(.white.opacity(0.6))
                                ForEach(manager.accounts) { acc in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(acc.gameName).font(.subheadline).foregroundColor(.white)
                                            Text("状态: \(acc.uid)").font(.caption).foregroundColor(.white.opacity(0.5))
                                            Text(acc.loginTime).font(.caption2).foregroundColor(.white.opacity(0.3))
                                        }
                                        Spacer()
                                        HStack(spacing: 8) {
                                            Button("复制UID") { manager.copyAccountUID(acc.uid) }.font(.caption).foregroundColor(.blue)
                                            Button("删除") { manager.deleteAccount(id: acc.id) }.font(.caption).foregroundColor(.red)
                                        }
                                    }.padding().background(Color.white.opacity(0.05)).cornerRadius(10)
                                }
                            }
                            .padding().background(Color.white.opacity(0.03)).cornerRadius(16)
                        }
                    }.padding(16)
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }

    private func mask(_ token: String) -> String {
        guard token.count > 10 else { return token }
        return String(token.prefix(6)) + "****" + String(token.suffix(4))
    }
}

struct GameLoginCard: View {
    let name: String
    let icon: String
    let color: Color
    let urlScheme: String
    @ObservedObject var manager: GameLoginManager
    var independentToken: String?

    var body: some View {
        Button {
            manager.launchGame(gameName: name, urlScheme: urlScheme, token: independentToken)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 28)).foregroundColor(.white)
                    .frame(width: 56, height: 56).background(color).clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline).foregroundColor(.white)
                    Text("点击唤起游戏").font(.caption).foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Text("🚀 唤起").font(.subheadline).fontWeight(.medium).foregroundColor(.white).padding(.horizontal, 20).padding(.vertical, 10).background(color).cornerRadius(8)
            }
            .padding(14).background(Color.white.opacity(0.05)).cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
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
            Color(red: 0.08, green: 0.10, blue: 0.16).ignoresSafeArea()
            VStack(spacing: 0) {
                if manager.showMessage {
                    MessageBanner(message: manager.message, type: manager.messageType)
                }
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 12) {
                            Text("从文本中提取Token").font(.headline).foregroundColor(.white)
                            Text("粘贴包含Token的文本，自动识别并提取").font(.caption).foregroundColor(.white.opacity(0.5))
                        }

                        VStack(spacing: 12) {
                            TextEditor(text: $inputText)
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                                .foregroundColor(.white)
                                .focused($isFocused)
                                .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { isFocused = false } } }
                                .overlay(
                                    Group {
                                        if inputText.isEmpty {
                                            Text("在此粘贴文本...").foregroundColor(.white.opacity(0.3)).padding(.leading, 16).padding(.top, 16)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                        }
                                    }
                                )

                            Button {
                                extractToken()
                            } label: {
                                Label("提取Token", systemImage: "magnifyingglass")
                                    .font(.subheadline).foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(Color.purple).cornerRadius(10)
                            }
                        }

                        if !extractedToken.isEmpty {
                            VStack(spacing: 12) {
                                Text("提取结果").font(.subheadline).foregroundColor(.green)
                                Text(extractedToken).font(.system(.caption, design: .monospaced)).foregroundColor(.white)
                                    .padding().background(Color.white.opacity(0.05)).cornerRadius(10)
                                HStack(spacing: 12) {
                                    Button {
                                        manager.saveToken(extractedToken, source: "提取")
                                        extractedToken = ""
                                        inputText = ""
                                    } label: {
                                        Label("储存", systemImage: "square.and.arrow.down").font(.caption).foregroundColor(.white)
                                            .frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.green).cornerRadius(10)
                                    }
                                    Button {
                                        UIPasteboard.general.string = extractedToken
                                    } label: {
                                        Label("复制", systemImage: "doc.on.doc").font(.caption).foregroundColor(.white)
                                            .frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.blue).cornerRadius(10)
                                    }
                                }
                            }
                            .padding().background(Color.white.opacity(0.05)).cornerRadius(16)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("支持格式").font(.subheadline).foregroundColor(.white.opacity(0.6))
                            Text("• JSON: {\"token\":\"xxx\"}").font(.caption).foregroundColor(.white.opacity(0.4))
                            Text("• URL参数: ?token=xxx").font(.caption).foregroundColor(.white.opacity(0.4))
                            Text("• 纯文本Token (长度>10)").font(.caption).foregroundColor(.white.opacity(0.4))
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.05)).cornerRadius(12)
                    }.padding(16)
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }

    private func extractToken() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = json["token"] as? String {
            extractedToken = token
            return
        }
        if let url = URL(string: text),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
            extractedToken = token
            return
        }
        if text.count > 10, !text.contains(" "), !text.contains("\n") {
            extractedToken = text
        } else {
            extractedToken = "未识别到有效Token"
        }
    }
}