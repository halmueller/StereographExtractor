//
//  Stereograph_ExtractorApp.swift
//  Stereograph Extractor
//
//  Created by Hal Mueller on 8/30/25.
//

import SwiftUI

@main
struct Stereograph_ExtractorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 640)
        }
        // Optional: customize menus (leave New/Close as-is, keep your own Open/Save in UI)
        .commands {
            CommandGroup(replacing: .newItem) { /* no File > New */ }
            // You can also add custom menu items here if you want to trigger actions via Notifications
        }
    }
}
