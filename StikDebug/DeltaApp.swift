import SwiftUI
import Foundation
import CommonCrypto
import UIKit
import CoreImage

//AES加密模块 固定密钥 IENNSJFJWKSFJ
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

//账号结构体
struct Account: Codable, Identifiable {
    let id = UUID()
    let openid: String
    let seecoon_token: String
    let quid: String
    let refresh_token: String
    let createTime: Date
}

//全局数据存储（永久加密写入硬盘，读取自动解密）
class DataManager: ObservableObject {
    @Published var accounts: [Account] = []
    var docPath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("delta.dat")
    }
    init(){ loadAccounts() }
    
    //新增账号，自动加密存储
    func saveAccount(acc:Account){
        accounts.append(acc)
        let json = try! JSONEncoder().encode(accounts)
        let cipherText = AESHelper.encrypt(String(data:json,encoding:.utf8)!)
        try! cipherText.write(to:docPath,atomically:true,encoding:.utf8)
    }
    
    //读取文件自动解密到内存，硬盘不会明文
    func loadAccounts(){
        if FileManager.default.fileExists(atPath: docPath.path){
            let cipherText = try! String(contentsOf: docPath)
            let jsonPlain = AESHelper.decrypt(cipherText)
            let jsonData = jsonPlain.data(using:.utf8)!
            accounts = try! JSONDecoder().decode([Account].self,from:jsonData)
        }
    }
    
    func deleteAccount(id:UUID){
        accounts.removeAll{$0.id == id}
        let json = try! JSONEncoder().encode(accounts)
        let cipherText = AESHelper.encrypt(String(data:json,encoding:.utf8)!)
        try! cipherText.write(to:docPath,atomically:true,encoding:.utf8)
    }
}

//本地生成高清二维码
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

//首页
struct HomeView: View {
    @StateObject var dm = DataManager()
    @State var targetPage: Int? = nil
    var body: some View {
        NavigationStack {
            VStack(spacing:35) {
                Button { targetPage = 1 } label: {
                    Text("A：三角洲扫码获取Token")
                        .font(.title2)
                        .frame(width:320, height:85)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                Button { targetPage = 2 } label: {
                    Text("B：账号Token管理")
                        .font(.title2)
                        .frame(width:320, height:85)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                Button { targetPage = 3 } label: {
                    Text("C：Token登录与解密工具")
                        .font(.title2)
                        .frame(width:320, height:85)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
            }
            .navigationDestination(item:$targetPage) { page in
                switch page {
                case 1: ScanLoginView(dm: dm)
                case 2: AccountListView(dm: dm)
                case 3: TokenLoginView()
                default: EmptyView()
                }
            }
            .navigationTitle("三角洲工具箱")
        }
    }
}

//A页面：横屏扫码，抓到token加密保存，立刻刷新二维码，全程不跳转任何软件
struct ScanLoginView: View {
    @ObservedObject var dm: DataManager
    @Environment(\.dismiss) var dismiss
    @State var qrImage: UIImage = UIImage()
    @State var sessionId: String = ""
    @State var timer: Timer? = nil
    
    func createNewSession() {
        sessionId = UUID().uuidString
        let qrContent = "https://game.seecoon.com/h5/qqscan?session=\(sessionId)"
        qrImage = generateQRCode(from: qrContent)
        startCheck()
    }
    
    func startCheck() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: true) { _ in
            let url = URL(string:"https://game.seecoon.com/api/login/checkScan?session=\(sessionId)")!
            URLSession.shared.dataTask(with: url) { data,_,_ in
                guard let data = data else { return }
                let obj = try! JSONSerialization.jsonObject(with: data) as! [String:Any]
                //识别到扫码成功
                if let resData = obj["data"] as? [String:Any] {
                    DispatchQueue.main.async {
                        //加密存入本地，不会打开三角洲
                        let newAcc = Account(
                            id: UUID(),
                            openid: resData["openid"] as! String,
                            seecoon_token: resData["seecoon_token"] as! String,
                            quid: resData["quid"] as! String,
                            refresh_token: resData["refresh_token"] as! String,
                            createTime: Date()
                        )
                        dm.saveAccount(acc: newAcc)
                        //直接刷新二维码，无限扫号
                        createNewSession()
                    }
                }
            }.resume()
        }
    }
    
    var body: some View {
        HStack(spacing:0) {
            //左侧文字区域
            VStack(spacing:40) {
                HStack {
                    Button("关闭") { dismiss() }
                        .foregroundColor(Color.blue)
                        .font(.title3)
                    Spacer()
                }
                Spacer()
                HStack(spacing:12){
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
            .padding(.leading,30)
            
            //右侧二维码区域
            VStack{
                Spacer()
                Image(uiImage: qrImage)
                    .resizable()
                    .frame(width:340, height:340)
                Spacer()
            }
            .frame(maxWidth:.infinity)
        }
        .onAppear {
            createNewSession()
        }
        .onDisappear {
            timer?.invalidate()
        }
        //进入强制横屏，退出恢复竖屏
        .onAppear{
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        }
        .onDisappear{
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
        .supportedOrientations(.landscapeRight)
    }
}

//B页面：内存自动解密展示账号，硬盘全程密文存储
struct AccountListView: View {
    @ObservedObject var dm: DataManager
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack {
            HStack {
                Button("← 返回首页") { dismiss() }
                Spacer()
            }.padding()
            List(dm.accounts) { acc in
                VStack(alignment:.leading, spacing:6) {
                    Text("OpenID：\(acc.openid)")
                    Text("Seecoon_Token：\(acc.seecoon_token)")
                        .font(.system(size:9))
                    HStack(spacing:15) {
                        Button("复制Token") {
                            UIPasteboard.general.string = acc.seecoon_token
                        }
                        // ✅ 修复 iOS 14 兼容性：移除 role 参数，手动设置红色
                        Button("删除账号") {
                            dm.deleteAccount(id: acc.id)
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }
}

//C页面：唯一唤起三角洲的地方，输入token校验，登录按钮拉起游戏
struct TokenLoginView: View {
    @Environment(\.dismiss) var dismiss
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
    
    //整个软件唯一唤起三角洲的代码，只在这里生效
    func launchGame() {
        UIApplication.shared.open(URL(string:"seecoon://login?token=\(inputToken)")!)
    }
    
    var body: some View {
        VStack(spacing:22) {
            TextField("粘贴seecoon_token", text:$inputToken)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal,20)
            
            Button("检测Token有效性", action: checkTokenValid)
                .foregroundColor(.blue)
                .font(.system(size:18))
            
            Text(tips)
                .font(.system(size:18))
            
            Button("唤起三角洲一键登录", action: launchGame)
                .disabled(!tips.contains("✅"))
                .foregroundColor(.gray)
                .font(.system(size:18))
            
            Button("🔐 密文解密工具") {
                showDecryptSheet = true
            }
            .foregroundColor(.blue)
            .font(.system(size:18))
            
            Spacer()
        }
        .padding(.top,20)
        .sheet(isPresented:$showDecryptSheet) {
            VStack(spacing:14) {
                TextField("粘贴delta.dat全部密文内容", text:$cipherStr)
                    .textFieldStyle(.roundedBorder)
                TextField("输入解密密钥", text:$keyStr)
                Button("解密") {
                    decryptResult = AESHelper.customDecrypt(base64Str: cipherStr, keyStr: keyStr)
                }
                TextEditor(text:$decryptResult)
                    .frame(height:240)
            }
            .padding()
        }
    }
}

@main
struct DeltaMainApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.light)
        }
    }
}