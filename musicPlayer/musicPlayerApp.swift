//
//  musicPlayerApp.swift
//  musicPlayer
//
//  Created by jjguoxh@gmail.com on 2026/2/9.
//

import SwiftUI
import AVFoundation

@main
struct musicPlayerApp: App {
    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
