import UIKit
import SwiftUI

// Extensión para configurar colores globales de la UI en modo oscuro
extension UIColor {
    static func configureGlobalAppearance() {
        // Configurar el color de fondo de navegación en modo oscuro
        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithOpaqueBackground()
        
        let isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
        
        // Usar colores más claros para modo oscuro
        if isDarkMode {
            // Personalización específica para modo oscuro
            navigationBarAppearance.backgroundColor = UIColor(named: "Background")
            
            // Configurar colores para todo el sistema
            UIView.appearance().backgroundColor = UIColor(named: "Background")
            UITableView.appearance().backgroundColor = UIColor(named: "Background")
            UICollectionView.appearance().backgroundColor = UIColor(named: "Background")
            
            // Configurar colores de celdas
            UITableViewCell.appearance().backgroundColor = UIColor(named: "CardBackground")
        }
            
        // Aplicar apariencia a barras de navegación
        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance
        UINavigationBar.appearance().compactAppearance = navigationBarAppearance
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