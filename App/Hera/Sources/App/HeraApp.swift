//
//  MemoApp.swift
//  Memo
//
//  Created by Manuel Jesús Gutiérrez Fernández on 27/3/25.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct HeraApp: App {
    @StateObject var audioManager = AudioManager()
    @AppStorage("forced_theme") private var forcedTheme = 0 // 0 = System, 1 = Light, 2 = Dark
    
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
        configureAppAppearance()
    }
    
    private func configureAppAppearance() {
        // NavigationBar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(named: "Background")
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor(named: "PrimaryText") ?? .label]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(named: "PrimaryText") ?? .label]
        
        // Shadow para navegación (eliminar línea de borde)
        navBarAppearance.shadowColor = .clear
        
        // Aplicar a la UI
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        
        // Estilo de la barra de tablas
        UITableView.appearance().backgroundColor = UIColor(named: "Background")
        UITableView.appearance().separatorStyle = .none
        
        // Estilo de celdas de tabla
        UITableViewCell.appearance().backgroundColor = .clear
        
        // Estilo de barras de búsqueda
        UISearchBar.appearance().backgroundColor = UIColor(named: "Background")
        
        // Color para los segmentedControl
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(named: "AccentColor")
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(named: "PrimaryText") ?? .label], for: .normal)
    }
    
    private func getPreferredColorScheme() -> ColorScheme? {
        switch forcedTheme {
        case 1:
            return .light
        case 2:
            return .dark
        default:
            return nil // system default
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(sharedModelContainer)
                .environmentObject(audioManager)
                .preferredColorScheme(getPreferredColorScheme())
                .tint(AppColors.accent) // Color de acento global
                .configureGlobalUIKitAppearance() // Aplicar configuración global de UIKit
        }
    }
}
