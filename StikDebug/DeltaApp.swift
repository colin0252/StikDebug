import SwiftUI
import Foundation
import CommonCrypto
import UIKit
import CoreImage

// MARK: - AES 加密（使用 CCCrypt 稳定实现，全版本兼容）
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
        let options = CCOptions(kCCOptionPKCS7Padding)
        
        if isEncrypt {
            guard let inputData = text.data(using: .utf8) else { return "" }
            var outLength = Int(inputData.count) + kCCBlockSizeAES128
            var outData = Data(count: outLength)
            var moved = 0
            let status = outData.withUnsafeMutableBytes { outBytes in
                inputData.withUnsafeBytes { inBytes in
                    CCCrypt(CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            options,
                            keyData.withUnsafeBytes { $0.baseAddress },
                            keyData.count,
                            iv.withUnsafeBytes { $0.baseAddress },
                            inBytes.baseAddress, inputData.count,
                            outBytes.baseAddress, outLength,
                            &moved)
                }
            }
            guard status == kCCSuccess else { return "" }
            outData.count = moved
            return outData.base64EncodedString()
        } else {
            guard let inputData = Data(base64Encoded: text) else { return "解密失败" }
            var outLength = Int(inputData.count) + kCCBlockSizeAES128
            var outData = Data(count: outLength)
            var moved = 0
            let status = outData.withUnsafeMutableBytes { outBytes in
                inputData.withUnsafeBytes { inBytes in
                    CCCrypt(CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            options,
                            keyData.withUnsafeBytes { $0.baseAddress },
                            keyData.count,
                            iv.withUnsafeBytes { $0.baseAddress },
                            inBytes.baseAddress, inputData.count,
                            outBytes.baseAddress, outLength,
                            &moved)
                }
            }
            guard status == kCCSuccess else { return "解密失败" }
            outData.count = moved
            return String(data: outData, encoding: .utf8) ?? "解密失败"
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

// MARK: - 二维码生成
func generateQRCode(from string: String) -> UIImage {
    let data = string.data(using: String.Encoding.utf8)!
    let filter = CIFilter(name: "CIQRCodeGenerator")
    filter?.setValue(data, forKey: "inputMessage")
    filter?.setValue("H", forKey: "inputCorrectionLevel")
    let ciImage = filter!.outputImage!
    let transform = CGAffineTransform(scaleX: 15, y: 15)
    let scaled = ciImage.transformed(by: transform)
    return UIImage(ciImage: scaled)
}

// MARK: - 首页（使用 NavigationView 兼容所有版本）
struct HomeView: View {
    @StateObject var dm = DataManager()
    var body: some View {
        NavigationView {
            VStack(spacing: 35) {
                NavigationLink(destination: ScanLoginView(dm: dm)) {
                    Text("A：三角洲扫码获取Token")
                        .font(.title2)
                        .frame(width: 320, height: 85)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                NavigationLink(destination: AccountListView(dm: dm)) {
                    Text("B：账号Token管理")
                        .font(.title2)
                        .frame(width: 320, height: 85)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                NavigationLink(destination: TokenLoginView()) {
                    Text("C：Token登录与解密工具")
                        .font(.title2)
                        .frame(width: 320, height: 85)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
            }
            .navigationTitle("三角洲工具箱")
        }
        .navigationViewStyle(StackNavigationViewStyle()) // 保证在 iPad 上也是单栏
    }
}

// MARK: - A 页面：扫码登录
struct ScanLoginView: View {
    @ObservedObject var dm: DataManager
    @Environment(\.presentationMode) var presentationMode
    @State var qrImage: UIImage = UIImage()
    @State var sessionId: String = ""
    @State var timer: Timer? = nil
    @State var showSuccess: Bool = false
    
    func createNewSession() {
        timer?.invalidate()
        sessionId = UUID().uuidString
        let qrContent = "seecoon://qqscan?session=\(sessionId)"
        qrImage = generateQRCode(from: qrContent)
        showSuccess = false
        startCheck()
    }
    
    func startCheck() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: true) { _ in
            let url = URL(string:"https://game.seecoon.com/api/login/checkScan?session=\(sessionId)")!
            URLSession.shared.dataTask(with: url) { data,_,_ in
                guard let data = data else { return }
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String:Any],
                   let resData = obj["data"] as? [String:Any] {
                    DispatchQueue.main.async {
                        let newAcc = Account(
                            openid: resData["openid"] as! String,
                            seecoon_token: resData["seecoon_token"] as! String,
                            quid: resData["quid"] as! String,
                            refresh_token: resData["refresh_token"] as! String,
                            createTime: Date()
                        )
                        dm.saveAccount(acc: newAcc)
                        timer?.invalidate()
                        showSuccess = true
                        // 延迟 2 秒后自动刷新二维码
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            createNewSession()
                        }
                    }
                }
            }.resume()
        }
    }
    
    var body: some View {
        VStack {
            HStack {
                Button("关闭") { presentationMode.wrappedValue.dismiss() }
                    .foregroundColor(.blue)
                    .font(.title3)
                Spacer()
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            HStack(spacing: 12) {
                Image(systemName: "penguin.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.black)
                Text("QQ 授权登录")
                    .font(.system(size: 36, weight: .medium))
            }
            
            ZStack {
                Image(uiImage: qrImage)
                    .resizable()
                    .frame(width: 320, height: 320)
                    .padding(.vertical, 30)
                    .opacity(showSuccess ? 0.3 : 1.0)
                
                if showSuccess {
                    VStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        Text("授权成功！")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                }
            }
            
            Text(showSuccess ? "已获取Token，即将刷新" : "使用QQ手机版扫码授权登录")
                .font(.system(size: 22))
                .foregroundColor(.gray)
            
            Spacer()
            Spacer()
        }
        .onAppear {
            createNewSession()
            if let url = URL(string: "mqqapi://auth?appname=三角洲行动") {
                UIApplication.shared.open(url)
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}

// MARK: - B 页面：账号列表
struct AccountListView: View {
    @ObservedObject var dm: DataManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack {
            HStack {
                Button("← 返回首页") { presentationMode.wrappedValue.dismiss() }
                Spacer()
            }.padding()
            List(dm.accounts) { acc in
                VStack(alignment: .leading, spacing: 6) {
                    Text("OpenID：\(acc.openid)")
                    Text("Seecoon_Token：\(acc.seecoon_token)")
                        .font(.system(size: 9))
                    HStack(spacing: 15) {
                        Button("复制Token") {
                            UIPasteboard.general.string = acc.seecoon_token
                        }
                        Button("删除账号", role: .destructive) {
                            dm.deleteAccount(id: acc.id)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - C 页面：Token 登录与解密
struct TokenLoginView: View {
    @Environment(\.presentationMode) var presentationMode
    @State var inputToken = ""
    @State var tips = ""
    @State var showDecryptSheet = false
    @State var cipherStr = ""
    @State var keyStr = ""
    @State var decryptResult = ""
    
    func checkTokenValid() {
        tips = "请求中..."
        let header: [String:String] = [
            "Authorization":"seecoon_token=\(inputToken)",
            "User-Agent":"SeecoonGame",
            "Content-Type":"application/json"
        ]
        var req = URLRequest(url: URL(string:"https://game.seecoon.com/api/user/checkLogin")!)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = header
        req.httpBody = "{}".data(using:.utf8)
        req.timeoutInterval = 3
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if error != nil {
                    tips = "网络异常"
                    return
                }
                guard let d = data else {
                    tips = "网络异常"
                    return
                }
                do{
                    let json = try JSONSerialization.jsonObject(with:d) as! [String:Any]
                    let ok = json["data"] as? Bool ?? false
                    tips = ok ? "✅ Token有效，可以一键登录" : "❌ Token已经失效"
                }catch{
                    tips = "网络异常"
                }
            }
        }.resume()
    }
    
    func launchGame() {
        if let url = URL(string:"seecoon://login?token=\(inputToken)") {
            UIApplication.shared.open(url)
        }
    }
    
    var body: some View {
        VStack(spacing: 22) {
            TextField("粘贴seecoon_token", text: $inputToken)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
            
            Button("检测Token有效性", action: checkTokenValid)
                .foregroundColor(.blue)
                .font(.system(size: 18))
            
            Text(tips)
                .font(.system(size: 18))
            
            Button("唤起三角洲一键登录", action: launchGame)
                .disabled(!tips.contains("✅"))
                .foregroundColor(.gray)
                .font(.system(size: 18))
            
            Button("🔐 密文解密工具") {
                showDecryptSheet = true
            }
            .foregroundColor(.blue)
            .font(.system(size: 18))
            
            Spacer()
        }
        .padding(.top, 20)
        .sheet(isPresented: $showDecryptSheet) {
            VStack(spacing: 14) {
                TextField("粘贴delta.dat全部密文内容", text: $cipherStr)
                    .textFieldStyle(.roundedBorder)
                TextField("输入解密密钥", text: $keyStr)
                    .textFieldStyle(.roundedBorder)
                Button("解密") {
                    decryptResult = AESHelper.customDecrypt(base64Str: cipherStr, keyStr: keyStr)
                }
                TextEditor(text: $decryptResult)
                    .frame(height: 240)
            }
            .padding()
        }
    }
}

// MARK: - App 入口
@main
struct DeltaMainApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.light)
        }
    }
}