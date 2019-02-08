//
//  ViewController.swift
//  WebRtcBeta
//
//  Created by Alif on 5/2/19.
//  Copyright © 2019 Alif. All rights reserved.
//

import UIKit
import Starscream
import WebRTC

class ScreenSizeUtil {
    
    static func width() -> CGFloat {
        return UIScreen.main.bounds.width
    }
    
    static func height() -> CGFloat {
        return UIScreen.main.bounds.height
    }
}

class ViewController: UIViewController {

    private var webRTCClient: WebRTCClient!
    var socket: WebSocket!
    var tryToConnectWebSocket: Timer!
    
    let ipAddress: String = "10.0.1.3"

    @IBOutlet private weak var localVideoView: UIView!
    @IBOutlet weak var remoteVideoView: UIView!
     var rtcLocalView:      RTCEAGLVideoView?
    
    var speakerOn: Bool = false
    var mute: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        webRTCClient = WebRTCClient()
        webRTCClient.delegate = self
        webRTCClient.setup(videoTrack: true, audioTrack: true, dataChannel: true)
        
        socket = WebSocket(url: URL(string: "ws://" + ipAddress + ":8080/")!)
        socket?.delegate = self
        
        tryToConnectWebSocket = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { (timer) in
            if self.webRTCClient.isConnected || self.socket.isConnected {
                return
            }
            
            self.socket.connect()
        })
        
        #if arch(arm64)
        // Using metal (arm64 only)
            let localRenderer = RTCEAGLVideoView(
                frame: CGRect(x: 0, y: 0, width: localVideoView.frame.width, height: localVideoView.frame.height)
            )
            //localRenderer.videoContentMode = .scaleAspectFill
        
            let remoteRenderer = RTCEAGLVideoView(
                frame: CGRect(x: 0, y: 0, width: remoteVideoView.frame.width, height: remoteVideoView.frame.height)
            )
            //remoteRenderer.videoContentMode = .scaleAspectFill
        #else
        // Using OpenGLES for the rest
        print(#line, self, "simulator...")
            let localRenderer = RTCEAGLVideoView(
                frame: CGRect(x: 0, y: 0, width: localVideoView.frame.width, height: localVideoView.frame.height)
            )
            let remoteRenderer = RTCEAGLVideoView(
                frame: CGRect(x: 0, y: 0, width: remoteVideoView.frame.width, height: remoteVideoView.frame.height)
            )
        #endif
        
        self.webRTCClient.startCaptureLocalVideo(renderer: localRenderer)
        self.webRTCClient.renderRemoteVideo(to: remoteRenderer)
 
        localVideoView.addSubview(localRenderer)
        remoteVideoView.addSubview(remoteRenderer)
        
        // Do any additional setup after loading the view, typically from a nib.
    }
    
    override func viewDidAppear(_ animated: Bool) {

    }
    
    private func sendCandidate(iceCandidate: RTCIceCandidate) {
        let candidate = Candidate.init(
            sdp: iceCandidate.sdp,
            sdpMLineIndex: iceCandidate.sdpMLineIndex,
            sdpMid: iceCandidate.sdpMid!
        )
        
        let signalingMessage = SignalingMessage.init(type: "candidate", sessionDescription: nil, candidate: candidate)
        
        do {
            let data = try JSONEncoder().encode(signalingMessage)
            let message = String(data: data, encoding: String.Encoding.utf8)!
            
            if (self.socket?.isConnected)! {
                self.socket?.write(string: message)
            }
        }catch{
            print(error)
        }
    }

    @IBAction func callButtonTap(_ sender: Any) {

        if !webRTCClient.isConnected {
            webRTCClient.connect(onSuccess: { (offerSDP: RTCSessionDescription) -> Void in
                print(#line, offerSDP)
                self.sendSDP(sessionDescription: offerSDP)
            })

        }
    }
    
    @IBAction func hangoutBUttonTap(_ sender: Any) {
        if webRTCClient.isConnected {
            webRTCClient.disconnect()
        }
    }
    
    private func sendSDP(sessionDescription: RTCSessionDescription) {
        var type = ""
        if sessionDescription.type == .offer {
            type = "offer"
        }else if sessionDescription.type == .answer {
            type = "answer"
        }
        
        let sdp = SDP.init(sdp: sessionDescription.sdp)
        let signalingMessage = SignalingMessage.init(type: type, sessionDescription: sdp, candidate: nil)
        do {
            let data = try JSONEncoder().encode(signalingMessage)
            let message = String(data: data, encoding: String.Encoding.utf8)!
            
            if self.socket!.isConnected {
                self.socket?.write(string: message)
            }
        } catch {
            print(error)
        }
    }
    
    @IBAction func speakerDidTouch(_ sender: UIButton) {
        
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(
                AVAudioSession.Category.playAndRecord, mode: .default, options: []
            )
            
            self.speakerOn ? try session.overrideOutputAudioPort(.none) : try session.overrideOutputAudioPort(.speaker)
            
            try session.setActive(true)
            
            self.speakerOn = !self.speakerOn
        }
        catch let error {
            print("Couldn't set audio to speaker: \(error)")
        }
    }
    
    @IBAction func muteDidTap(_ sender: UIButton) {
        self.mute = !self.mute
        self.mute ? self.webRTCClient.muteAudio() : self.webRTCClient.unmuteAudio()
    }
}

extension ViewController: WebSocketDelegate {
    func websocketDidConnect(socket: WebSocketClient) {
        //
    }
    
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        //
    }
    
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        do {
            let signalingMessage = try JSONDecoder().decode(SignalingMessage.self, from: text.data(using: .utf8)!)
            
            if signalingMessage.type == "offer" {
            
                webRTCClient.receiveOffer(offerSDP: RTCSessionDescription(type: .offer, sdp: (signalingMessage.sessionDescription?.sdp)!), onCreateAnswer: {(answerSDP: RTCSessionDescription) -> Void in
                    self.sendSDP(sessionDescription: answerSDP)
                })
                
            } else if signalingMessage.type == "answer" {
                print(#line, "answer")
                webRTCClient.receiveAnswer(
                    answerSDP: RTCSessionDescription(
                        type: .answer,
                        sdp: (signalingMessage.sessionDescription?.sdp)!
                    )
                )
                
            } else if signalingMessage.type == "candidate" {
                
                let candidate = signalingMessage.candidate!
                webRTCClient.receiveCandidate(
                    candidate: RTCIceCandidate(
                        sdp: candidate.sdp,
                        sdpMLineIndex: candidate.sdpMLineIndex,
                        sdpMid: candidate.sdpMid
                    )
                )
            }
            
            print(#line, signalingMessage)
        } catch {
            print(error)
        }
    }
    
    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        //
    }
    

}
extension ViewController: WebRTCClientDelegate {
    func didGenerateCandidate(iceCandidate: RTCIceCandidate) {
        self.sendCandidate(iceCandidate: iceCandidate)
    }
    
    func didIceConnectionStateChanged(iceConnectionState: RTCIceConnectionState) {
        var state = ""
        
        switch iceConnectionState {
        case .checking:
            state = "checking..."
        case .closed:
            state = "closed"
        case .completed:
            state = "completed"
        case .connected:
            state = "connected"
        case .count:
            state = "count..."
        case .disconnected:
            state = "disconnected"
        case .failed:
            state = "failed"
        case .new:
            state = "new..."
        }
    }
    
    func didOpenDataChannel() {
        //
    }
    
    func didReceiveData(data: Data) {
        //
    }
    
    func didReceiveMessage(message: String) {
        //
    }
    
    func didConnectWebRTC() {
        self.socket?.disconnect()
    }
    
    func didDisconnectWebRTC() {
        print("did open data channel")
    }
    
}

func createButton(frame: CGRect, title: String?, imageName: String?, target: Any?, action: Selector) -> UIButton {
    let button = UIButton(frame: frame)
    button.setTitle(title, for: .normal)
    
    if let imageName = imageName {
        button.setBackgroundImage(UIImage(named: imageName), for: .normal)
    }
    
    button.addTarget(target, action: action, for: .touchUpInside)
    return button
}
