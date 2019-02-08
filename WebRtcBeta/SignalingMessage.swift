//
//  SignalingMessage.swift
//  WebRtcBeta
//
//  Created by Alif on 6/2/19.
//  Copyright © 2019 Alif. All rights reserved.
//

import Foundation

struct SignalingMessage: Codable {
    let type: String
    let sessionDescription: SDP?
    let candidate: Candidate?
}

struct SDP: Codable {
    let sdp: String
}

struct Candidate: Codable {
    let sdp: String
    let sdpMLineIndex: Int32
    let sdpMid: String
}
