//
//  Vibe_FoodApp.swift
//  Vibe Food
//
//  Created by Rogério Munhoz on 01/03/26.
//

import SwiftUI
import SwiftData

@main
struct Vibe_FoodApp: App {
    @StateObject private var appContainer = AppContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appContainer)
                .task {
                    appContainer.seedIfNeeded()
                }
        }
        .modelContainer(appContainer.modelContainer)
    }
}
