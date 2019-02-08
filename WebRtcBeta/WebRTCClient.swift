//
//  WebRTCClient.swift
//  WebRtcBeta
//
//  Created by Alif on 5/2/19.
//  Copyright © 2019 Alif. All rights reserved.
//

import Foundation
import WebRTC

fileprivate let defaultIceServers = [
    "stun:stun.l.google.com:19302",
    "stun:stun1.l.google.com:19302",
    "stun:stun2.l.google.com:19302",
    "stun:stun3.l.google.com:19302",
    "stun:stun4.l.google.com:19302"
]

public struct ErrorDomain {
    static let videoPermissionDenied = "Video permission denied"
    static let audioPermissionDenied = "Audio permission denied"
}

import WebRTC
import Foundation

private let audioTrackId = "audio0"
private let videoTrackId = "video0"
private let mediaStreamId = "AddaMS"

protocol WebRTCClientDelegate {
    func didGenerateCandidate(iceCandidate: RTCIceCandidate)
    func didIceConnectionStateChanged(iceConnectionState: RTCIceConnectionState)
    func didOpenDataChannel()
    func didReceiveData(data: Data)
    func didReceiveMessage(message: String)
    func didConnectWebRTC()
    func didDisconnectWebRTC()
}

class WebRTCClient: NSObject, RTCPeerConnectionDelegate {

    private var localRenderView: RTCEAGLVideoView?
    private var localView: UIView!
    
    private var remoteRenderView: RTCEAGLVideoView?
    private var remoteView: UIView!
    
    private var factory: RTCPeerConnectionFactory = RTCPeerConnectionFactory()
    private var peerConnection: RTCPeerConnection!
    private var localCandidates = [RTCIceCandidate]()
    
    private var videoCapturer: RTCVideoCapturer?
    private var remoteStream: RTCMediaStream?
    
    private var localAudioTrack: RTCAudioTrack!
    private var localVideoTrack: RTCVideoTrack!

    fileprivate let audioCallConstraint = RTCMediaConstraints(
        mandatoryConstraints: ["OfferToReceiveAudio" : "true"],
        optionalConstraints: nil
    )
    
    fileprivate let videoCallConstraint = RTCMediaConstraints(
        mandatoryConstraints: nil,
        optionalConstraints: [
            kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
            kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue
        ]
    )
    
    var callConstraint : RTCMediaConstraints {
        return self.channels.video ? self.audioCallConstraint : self.videoCallConstraint
    }
    
    private static var mainStream: RTCMediaStream?
    private var partnerId: String?
    
    private var dataChannel: RTCDataChannel?
    private var channels: (video: Bool, audio: Bool, datachannel: Bool) = (true, true, true)

    var delegate: WebRTCClientDelegate?
    public private(set) var isConnected: Bool = false

    override init() {
        super.init()
        print("WebRTC Client initialize")
    }

    deinit {
        print("WebRTC Client Deinit")
        self.peerConnection = nil
        //self.peerConnection = nil
    }
    
    func localVideoView() -> UIView {
        return localView
    }
    
    func remoteVideoView() -> UIView {
        return remoteView
    }
    
    func setupLocalViewFrame(frame: CGRect) {
        localView.frame = frame
        localRenderView?.frame = localView.frame
    }
    
    func setupRemoteViewFrame(frame: CGRect) {
        remoteView.frame = frame
        remoteRenderView?.frame = remoteView.frame
    }

    // MARK: - Public functions
    fileprivate func setupPeerConnection() -> RTCPeerConnection {
        let iceServers = [
            RTCIceServer(urlStrings: [
                "turn:173.194.203.127:19305?transport=udp",
                "turn:[2607:f8b0:400e:c05::7f]:19305?transport=udp",
                "turn:173.194.203.127:19305?transport=tcp",
                "turn:[2607:f8b0:400e:c05::7f]:19305?transport=tcp"
                ],
                username:    "CMrw7dwFEgbAETfdivQYzc/s6OMTIICjBQ",
                credential:  "Rdg4lTerPbdb9HDWPvBn7DgHXiA="
            )
        ]
        
        let config = RTCConfiguration()
        config.iceServers = iceServers
        
        // Unified plan is more superior than planB
        config.sdpSemantics = .unifiedPlan
        
        // gatherContinually will let WebRTC to listen to any network changes and send any new candidates to the other client
        config.continualGatheringPolicy = .gatherContinually
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement":kRTCMediaConstraintsValueTrue]
        )
        
        let peerC = self.factory.peerConnection(
            with: config, constraints: constraints, delegate: nil
        )
        // self.peerConnection.delegate = self
        return peerC
        
    }
    
    func setup(videoTrack: Bool, audioTrack: Bool, dataChannel: Bool){
        print("set up")
        self.channels.video = videoTrack
        self.channels.audio = audioTrack
        self.channels.datachannel = dataChannel
        
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )

        setupView()
        setupLocalTracks()
        
        if self.channels.video {
            //startCaptureLocalVideo(cameraPositon: .front, videoWidth: 640, videoHeight: 640*16/9, videoFps: 30)
            self.localVideoTrack?.add(self.localRenderView!)
        }
    }

    private func setupView(){
        // local
        localRenderView = RTCEAGLVideoView()
        localRenderView!.delegate = self
        localView = UIView()
        localView.addSubview(localRenderView!)
        // remote
        remoteRenderView = RTCEAGLVideoView()
        remoteRenderView?.delegate = self
        remoteView = UIView()
        remoteView.addSubview(remoteRenderView!)
    }
    
    var isVideoDisabled: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        return status == .restricted || status == .denied
    }

    var isAudioDisabled: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.audio)
        return status == .restricted || status == .denied
    }


    // MARK: Connect
    func connect(onSuccess: @escaping (RTCSessionDescription) -> Void){
        self.peerConnection = setupPeerConnection()
        self.peerConnection!.delegate = self
        
        if self.channels.video {
            self.peerConnection!.add(localVideoTrack, streamIds: ["stream0"])
        }
        
        if self.channels.audio {
            self.peerConnection!.add(localAudioTrack, streamIds: ["stream0"])
        }
        
        if self.channels.datachannel {
            self.dataChannel = self.setupDataChannel()
            self.dataChannel?.delegate = self
        }
        
        makeOffer(onSuccess: onSuccess)
    }

    // MARK: HangUp
    func disconnect(){
        if self.peerConnection != nil{
            self.peerConnection.close()
        }
    }

    // MARK: Signaling Event
    
    func set(remoteSdp: RTCSessionDescription, completion: @escaping (Error?) -> ()) {
        self.peerConnection.setRemoteDescription(remoteSdp, completionHandler: completion)
    }
    
    func set(remoteCandidate: RTCIceCandidate) {
        self.peerConnection.add(remoteCandidate)
    }

    func receiveCandidate(candidate: RTCIceCandidate){
        self.peerConnection.add(candidate)
    }
    
    func renderRemoteVideo(to renderer: RTCVideoRenderer) {
        self.remoteStream?.videoTracks.first?.add(renderer)
    }
    
    func muteAudio() {
        self.setAudioEnabled(false)
    }
    
    func unmuteAudio() {
        self.setAudioEnabled(true)
    }
    
    func startCaptureLocalVideo(renderer: RTCVideoRenderer) {
        guard let capturer = self.videoCapturer as? RTCCameraVideoCapturer else {
            return
        }
        
        guard
            let frontCamera = (RTCCameraVideoCapturer.captureDevices().first { $0.position == .front }),
            
            // choose highest res
            let format = (RTCCameraVideoCapturer.supportedFormats(for: frontCamera).sorted { (f1, f2) -> Bool in
                let width1 = CMVideoFormatDescriptionGetDimensions(f1.formatDescription).width
                let width2 = CMVideoFormatDescriptionGetDimensions(f2.formatDescription).width
                return width1 < width2
            }).last,
            
            // choose highest fps
            let fps = (format.videoSupportedFrameRateRanges.sorted { return $0.maxFrameRate < $1.maxFrameRate }.last) else {
                return
        }
        
        capturer.startCapture(
            with: frontCamera, format: format, fps: Int(fps.maxFrameRate)
        )
        
        self.localVideoTrack?.add(renderer)
    }
    
//    private func startCaptureLocalVideo(cameraPositon: AVCaptureDevice.Position, videoWidth: Int, videoHeight: Int?, videoFps: Int) {
//        if let capturer = self.videoCapturer as? RTCCameraVideoCapturer {
//            var targetDevice: AVCaptureDevice?
//            var targetFormat: AVCaptureDevice.Format?
//
//            // find target device
//            let devicies = RTCCameraVideoCapturer.captureDevices()
//            devicies.forEach { (device) in
//                if device.position ==  cameraPositon{
//                    targetDevice = device
//                }
//            }
//
//            // find target format
//            let formats = RTCCameraVideoCapturer.supportedFormats(for: targetDevice!)
//            formats.forEach { (format) in
//                for _ in format.videoSupportedFrameRateRanges {
//                    let description = format.formatDescription as CMFormatDescription
//                    let dimensions = CMVideoFormatDescriptionGetDimensions(description)
//
//                    if dimensions.width == videoWidth && dimensions.height == videoHeight ?? 0 {
//                        targetFormat = format
//                    } else if dimensions.width == videoWidth {
//                        targetFormat = format
//                    }
//                }
//            }
//
//            capturer.startCapture(
//                with: targetDevice!,
//                format: targetFormat!,
//                fps: videoFps
//            )
//
//        } else if let capturer = self.videoCapturer as? RTCFileVideoCapturer {
//            print("setup file video capturer")
//            if let _ = Bundle.main.path( forResource: "sample.mp4", ofType: nil ) {
//                capturer.startCapturing(fromFileNamed: "sample.mp4") { (err) in
//                    print(err)
//                }
//            } else {
//                print("file did not faund")
//            }
//        }
//    }

    // MARK: DataChannel Event
    func sendMessge(message: String){
        if let _dataChannel = self.dataChannel {
            if _dataChannel.readyState == .open {
                let buffer = RTCDataBuffer(data: message.data(using: String.Encoding.utf8)!, isBinary: false)
                _dataChannel.sendData(buffer)
            }else {

                print("data channel is not ready state")
            }
        } else {
            print("no data channel")
        }
    }

    func sendData(data: Data){
        if let _dataChannel = self.dataChannel {
            if _dataChannel.readyState == .open {
                let buffer = RTCDataBuffer(data: data, isBinary: true)
                _dataChannel.sendData(buffer)
            }
        }
    }

    //MARK: - Local Media
    private func setupLocalTracks() {
        if self.channels.audio == true {
            self.localAudioTrack = createAudioTrack()
        }
        
        if self.channels.video == true {
            self.localVideoTrack = createVideoTrack()
        }
    }
    
    private func createAudioTrack() -> RTCAudioTrack {
        let audioSource = self.factory.audioSource(with: audioCallConstraint)
        let audioTrack = self.factory.audioTrack(with: audioSource, trackId: audioTrackId)
        audioTrack.source.volume = 10.0
        return audioTrack
    }

    private func createVideoTrack() -> RTCVideoTrack {
        let videoSource = self.factory.videoSource()

        if TARGET_OS_SIMULATOR != 0 {
            print(#line, "now runnnig on simulator...")
            self.videoCapturer = RTCFileVideoCapturer(delegate: videoSource)
        } else {
            self.videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        }

        let videoTrack = self.factory.videoTrack(with: videoSource, trackId: videoTrackId)
        return videoTrack
    }

    private func setAudioEnabled(_ isEnabled: Bool) {
        let audioTracks = self.peerConnection.senders.compactMap { return $0.track as? RTCAudioTrack }
        audioTracks.forEach { $0.isEnabled = isEnabled }
    }

    // MARK: - Local Data
    private func setupDataChannel() -> RTCDataChannel {
        let dataChannelConfig = RTCDataChannelConfiguration()
        dataChannelConfig.channelId = 0
        
        let _dataChannel = self.peerConnection?.dataChannel(forLabel: "dataChannel", configuration: dataChannelConfig)
        return _dataChannel!
    }

    // MARK: - Signaling Offer/Answer
    func receiveOffer(offerSDP: RTCSessionDescription, onCreateAnswer: @escaping (RTCSessionDescription) -> Void){
        if (self.peerConnection == nil) {
            print("offer received, create peerconnection")
            
            self.peerConnection = setupPeerConnection()
            self.peerConnection!.delegate = self
            
            if self.channels.audio {
                self.peerConnection!.add(localAudioTrack, streamIds: ["stream-0"])
            }
            
            if self.channels.video {
                self.peerConnection!.add(localVideoTrack, streamIds: ["stream-0"])
            }
            
            if self.channels.datachannel {
                self.dataChannel = self.setupDataChannel()
                self.dataChannel?.delegate = self
            }
        }
        
        self.peerConnection!.setRemoteDescription(offerSDP) { (err) in
            if let error = err {
                print("failed to set remote offer SDP")
                print(error)
                return
            }
            
            print("succeed to set remote offer SDP")
            self.makeAnswer(onCreateAnswer: onCreateAnswer)
        }
    }
    
    func receiveAnswer(answerSDP: RTCSessionDescription){
        self.peerConnection!.setRemoteDescription(answerSDP) { (err) in
            if let error = err {
                print("failed to set remote answer SDP")
                print(error)
                return
            }
        }
    }
    
    // MARK: - Signaling Offer/Answer
    func makeOffer(onSuccess: @escaping (RTCSessionDescription) -> Void) {

        self.peerConnection.offer(for: callConstraint) { (sdp, err) in
            if let error = err {
                print("error with make offer")
                print(error)
                return
            }

            if let offerSDP = sdp {
                print("make offer, created local sdp")
                self.peerConnection.setLocalDescription(offerSDP, completionHandler: { (err) in
                    if let error = err {
                        print("error with set local offer sdp")
                        print(error)
                        return
                    }
                    print("succeed to set local offer SDP")
                    onSuccess(offerSDP)
                })
            }

        }
    }

    func makeAnswer(onCreateAnswer: @escaping (RTCSessionDescription) -> Void){
  
        self.peerConnection.answer(for: callConstraint, completionHandler: { (answerSessionDescription, err) in
            if let error = err {
                print("failed to create local answer SDP")
                print(error)
                return
            }

            print("succeed to create local answer SDP")
            if let answerSDP = answerSessionDescription{
                self.peerConnection.setLocalDescription( answerSDP, completionHandler: { (err) in
                    if let error = err {
                        print("failed to set local ansewr SDP")
                        print(error)
                        return
                    }

                    print("succeed to set local answer SDP")
                    onCreateAnswer(answerSDP)
                })
            }
        })
    }

    // MARK: - Connection Events
    private func onConnected() {
        self.isConnected = true
        
        DispatchQueue.main.async {
            self.remoteRenderView?.isHidden = false
            self.delegate?.didConnectWebRTC()
        }
    }
    
    private func onDisConnected(){
        self.isConnected = false
        
        DispatchQueue.main.async {
            print("--- on dis connected ---")
            self.peerConnection!.close()
            self.peerConnection = nil
            self.remoteRenderView?.isHidden = true
            self.dataChannel = nil
            self.delegate?.didDisconnectWebRTC()
        }
    }
}

// MARK: - PeerConnection Delegeates
extension WebRTCClient {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        var state = ""
        if stateChanged == .stable {
            state = "stable"
        }
        
        if stateChanged == .closed {
            state = "closed"
        }
        
        print("signaling state changed: ", state)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        
        switch newState {
        case .connected, .completed:
            if !self.isConnected {
                self.onConnected()
            }
        default:
            if self.isConnected{
                self.onDisConnected()
            }
        }
        
        DispatchQueue.main.async {
            self.delegate?.didIceConnectionStateChanged(iceConnectionState: newState)
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("did add stream")
        self.remoteStream = stream
        
        if let track = stream.videoTracks.first {
            print("video track faund")
            track.add(remoteRenderView!)
        }
        
        if let _ = stream.audioTracks.first {
            print("audio track faund")
            //audioTrack.source.volume = 8
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        self.delegate?.didGenerateCandidate(iceCandidate: candidate)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("--- did remove stream ---")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        self.delegate?.didOpenDataChannel()
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

}

// MARK: - RTCVideoView Delegate
extension WebRTCClient: RTCVideoViewDelegate {
    func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        let isLandScape = size.width < size.height
        var renderView: RTCEAGLVideoView?
        var parentView: UIView?
        if videoView.isEqual(localRenderView){
            print("local video size changed")
            renderView = localRenderView
            parentView = localView
        }
        
        if videoView.isEqual(remoteRenderView!){
            print("remote video size changed to: ", size)
            renderView = remoteRenderView
            parentView = remoteView
        }
        
        guard let _renderView = renderView, let _parentView = parentView else {
            return
        }
        
        if(isLandScape) {
            let ratio = _parentView.frame.height / size.height
            _renderView.frame = CGRect(x: 0, y: 0, width: size.width * ratio, height: _parentView.frame.height)
            _renderView.center.x = _parentView.frame.width/2
        } else {
            let ratio = _parentView.frame.width / size.width
            _renderView.frame = CGRect(x: 0, y: 0, width: _parentView.frame.width, height: size.height * ratio)
            _renderView.center.y = _parentView.frame.height/2
        }
    }
}

// MARK: - RTCDataChannelDelegate
extension WebRTCClient: RTCDataChannelDelegate {
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        DispatchQueue.main.async {
            if buffer.isBinary {
                self.delegate?.didReceiveData(data: buffer.data)
            }else {
                self.delegate?.didReceiveMessage(message: String(data: buffer.data, encoding: String.Encoding.utf8)!)
            }
        }
    }
    
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("data channel did change state")
    }
}
