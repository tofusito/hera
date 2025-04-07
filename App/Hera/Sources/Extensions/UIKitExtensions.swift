import UIKit
import SwiftUI

// Extensión para configurar colores globales de la UI en modo oscuro
extension UIColor {
    static func configureGlobalAppearance() {
        // Configurar el color de fondo de navegación en modo oscuro
        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithOpaqueBackground()
        
        let isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
        
        // Configuración base para ambos modos
        navigationBarAppearance.backgroundColor = UIColor(named: "Background")
        navigationBarAppearance.titleTextAttributes = [.foregroundColor: UIColor(named: "PrimaryText") ?? .label]
        navigationBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(named: "PrimaryText") ?? .label]
        
        // Personalización específica para modo oscuro
        if isDarkMode {
            // Configurar colores para todo el sistema
            UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).backgroundColor = UIColor(named: "CardBackground")
            UITableView.appearance().backgroundColor = UIColor(named: "Background")
            UICollectionView.appearance().backgroundColor = UIColor(named: "Background")
            
            // Configurar colores de celdas
            UITableViewCell.appearance().backgroundColor = UIColor(named: "CardBackground")
            
            // Mejorar la separación entre celdas
            UITableView.appearance().separatorColor = UIColor(named: "SecondaryText")?.withAlphaComponent(0.3)
        } else {
            // Personalización para modo claro
            UITableView.appearance().backgroundColor = UIColor(named: "Background")
            UICollectionView.appearance().backgroundColor = UIColor(named: "Background")
            
            // Configurar colores de celdas
            UITableViewCell.appearance().backgroundColor = UIColor(named: "CardBackground")
            
            // Mejorar la separación entre celdas
            UITableView.appearance().separatorColor = UIColor(named: "SecondaryText")?.withAlphaComponent(0.2)
        }
            
        // Aplicar apariencia a barras de navegación
        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance
        UINavigationBar.appearance().compactAppearance = navigationBarAppearance
        
        // Configurar estilo de barras de búsqueda
        UISearchBar.appearance().backgroundColor = UIColor(named: "Background")
        UISearchBar.appearance().tintColor = UIColor(named: "AccentColor")
    }
}

// Estructura para inicializar la configuración global
struct UIKitAppearanceModifier: ViewModifier {
    init() {
        UIColor.configureGlobalAppearance()
    }
    
    func body(content: Content) -> some View {
        content
    }
}

// Extensión para SwiftUI View para aplicar la configuración
extension View {
    func configureGlobalUIKitAppearance() -> some View {
        self.modifier(UIKitAppearanceModifier())
    }
} 