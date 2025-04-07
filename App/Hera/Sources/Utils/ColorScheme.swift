import SwiftUI

struct AppColors {
    // Colores principales de la aplicación
    static let primaryText = Color("PrimaryText")
    static let secondaryText = Color("SecondaryText")
    static let background = Color("Background")
    static let cardBackground = Color("CardBackground")
    static let listBackground = Color("ListBackground")
    static let accent = Color("AccentColor")
    static let buttonBackground = Color("ButtonBackground")
    static let darkBackground = Color("DarkBackground")
    
    // Uso adaptativo directo
    static var adaptiveText: Color {
        Color(.label)
    }
    
    static var adaptiveBackground: Color {
        Color(.systemBackground)
    }
    
    static var adaptiveSecondaryBackground: Color {
        Color(.secondarySystemBackground)
    }
    
    static var adaptiveTertiaryBackground: Color {
        Color(.tertiarySystemBackground)
    }
    
    static var adaptiveGroupedBackground: Color {
        Color(.systemGroupedBackground)
    }
    
    static var adaptiveSecondaryGroupedBackground: Color {
        Color(.secondarySystemGroupedBackground)
    }
    
    static var adaptiveTint: Color {
        Color(.tintColor)
    }
    
    // Elementos de UI comunes
    static var actionButtonBackground: Color {
        accent
    }
    
    static var actionButtonForeground: Color {
        Color.white
    }
    
    // Obtener color con opacidad personalizada
    static func primaryText(opacity: Double) -> Color {
        primaryText.opacity(opacity)
    }
    
    static func secondaryText(opacity: Double) -> Color {
        secondaryText.opacity(opacity)
    }
} 