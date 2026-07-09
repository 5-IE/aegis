//
//  AegisApp.swift
//  Aegis
//  test
//
//  Created by William Antoline's Workspace on 01/07/26.
//

import SwiftUI

@main
struct AegisApp: App {
    init() {
        SentrySetup.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
