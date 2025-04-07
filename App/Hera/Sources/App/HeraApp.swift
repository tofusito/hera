//
//  MemoApp.swift
//  Memo
//
//  Created by Manuel Jesús Gutiérrez Fernández on 27/3/25.
//

import SwiftUI
import SwiftData

@main
struct HeraApp: App {
    @StateObject var audioManager = AudioManager()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            AudioRecording.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    init() {
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(named: "Background")
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor(named: "PrimaryText") ?? .label]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(named: "PrimaryText") ?? .label]
        
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(sharedModelContainer)
        }
    }
}
