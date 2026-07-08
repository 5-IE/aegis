//
//  Aegis_AdminApp.swift
//  Aegis-Admin
//
//  Created by William Antoline's Workspace on 01/07/26.
//

import SwiftUI

@main
struct Aegis_AdminApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 760)
        .windowStyle(.hiddenTitleBar)
    }
}
