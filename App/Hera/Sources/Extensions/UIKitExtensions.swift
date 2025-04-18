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

// Controlador para detectar cambios en el tema del sistema
class ThemeObserverViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.isHidden = true
        view.isUserInteractionEnabled = false
        UIColor.configureGlobalAppearance()
    }
    
    @available(iOS, deprecated: 17.0, message: "Use UITraitChangeObservable protocol for trait updates")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        // Verificar si el estilo de interfaz de usuario (oscuro/claro) ha cambiado
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            print("🎨 Theme changed - applying new appearance")
            UIColor.configureGlobalAppearance()
        }
    }
}

// UIViewControllerRepresentable para usar el observador de tema en SwiftUI
struct ThemeObserver: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ThemeObserverViewController {
        return ThemeObserverViewController()
    }
    
    func updateUIViewController(_ uiViewController: ThemeObserverViewController, context: Context) {
        // No se necesita actualizar
    }
}

// Estructura para inicializar la configuración global
struct UIKitAppearanceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ThemeObserver().frame(width: 0, height: 0))
            .onAppear {
                // Configuración inicial al aparecer
                UIColor.configureGlobalAppearance()
            }
    }
}

// Extensión para SwiftUI View para aplicar la configuración
extension View {
    func configureGlobalUIKitAppearance() -> some View {
        self.modifier(UIKitAppearanceModifier())
    }
} 