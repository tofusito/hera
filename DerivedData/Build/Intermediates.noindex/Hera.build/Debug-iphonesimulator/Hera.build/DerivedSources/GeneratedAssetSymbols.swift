import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

    /// The "Background" asset catalog color resource.
    static let background = DeveloperToolsSupport.ColorResource(name: "Background", bundle: resourceBundle)

    /// The "ButtonBackground" asset catalog color resource.
    static let buttonBackground = DeveloperToolsSupport.ColorResource(name: "ButtonBackground", bundle: resourceBundle)

    /// The "CardBackground" asset catalog color resource.
    static let cardBackground = DeveloperToolsSupport.ColorResource(name: "CardBackground", bundle: resourceBundle)

    /// The "DarkBackground" asset catalog color resource.
    static let darkBackground = DeveloperToolsSupport.ColorResource(name: "DarkBackground", bundle: resourceBundle)

    /// The "ListBackground" asset catalog color resource.
    static let listBackground = DeveloperToolsSupport.ColorResource(name: "ListBackground", bundle: resourceBundle)

    /// The "PrimaryText" asset catalog color resource.
    static let primaryText = DeveloperToolsSupport.ColorResource(name: "PrimaryText", bundle: resourceBundle)

    /// The "SecondaryText" asset catalog color resource.
    static let secondaryText = DeveloperToolsSupport.ColorResource(name: "SecondaryText", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// The "Background" asset catalog color.
    static var background: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .background)
#else
        .init()
#endif
    }

    /// The "ButtonBackground" asset catalog color.
    static var buttonBackground: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .buttonBackground)
#else
        .init()
#endif
    }

    /// The "CardBackground" asset catalog color.
    static var cardBackground: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .cardBackground)
#else
        .init()
#endif
    }

    /// The "DarkBackground" asset catalog color.
    static var darkBackground: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .darkBackground)
#else
        .init()
#endif
    }

    /// The "ListBackground" asset catalog color.
    static var listBackground: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .listBackground)
#else
        .init()
#endif
    }

    /// The "PrimaryText" asset catalog color.
    static var primaryText: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .primaryText)
#else
        .init()
#endif
    }

    /// The "SecondaryText" asset catalog color.
    static var secondaryText: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .secondaryText)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// The "Background" asset catalog color.
    static var background: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .background)
#else
        .init()
#endif
    }

    /// The "ButtonBackground" asset catalog color.
    static var buttonBackground: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .buttonBackground)
#else
        .init()
#endif
    }

    /// The "CardBackground" asset catalog color.
    static var cardBackground: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .cardBackground)
#else
        .init()
#endif
    }

    /// The "DarkBackground" asset catalog color.
    static var darkBackground: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .darkBackground)
#else
        .init()
#endif
    }

    /// The "ListBackground" asset catalog color.
    static var listBackground: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .listBackground)
#else
        .init()
#endif
    }

    /// The "PrimaryText" asset catalog color.
    static var primaryText: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .primaryText)
#else
        .init()
#endif
    }

    /// The "SecondaryText" asset catalog color.
    static var secondaryText: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .secondaryText)
#else
        .init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    /// The "Background" asset catalog color.
    static var background: SwiftUI.Color { .init(.background) }

    /// The "ButtonBackground" asset catalog color.
    static var buttonBackground: SwiftUI.Color { .init(.buttonBackground) }

    /// The "CardBackground" asset catalog color.
    static var cardBackground: SwiftUI.Color { .init(.cardBackground) }

    /// The "DarkBackground" asset catalog color.
    static var darkBackground: SwiftUI.Color { .init(.darkBackground) }

    /// The "ListBackground" asset catalog color.
    static var listBackground: SwiftUI.Color { .init(.listBackground) }

    /// The "PrimaryText" asset catalog color.
    static var primaryText: SwiftUI.Color { .init(.primaryText) }

    /// The "SecondaryText" asset catalog color.
    static var secondaryText: SwiftUI.Color { .init(.secondaryText) }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    /// The "Background" asset catalog color.
    static var background: SwiftUI.Color { .init(.background) }

    /// The "ButtonBackground" asset catalog color.
    static var buttonBackground: SwiftUI.Color { .init(.buttonBackground) }

    /// The "CardBackground" asset catalog color.
    static var cardBackground: SwiftUI.Color { .init(.cardBackground) }

    /// The "DarkBackground" asset catalog color.
    static var darkBackground: SwiftUI.Color { .init(.darkBackground) }

    /// The "ListBackground" asset catalog color.
    static var listBackground: SwiftUI.Color { .init(.listBackground) }

    /// The "PrimaryText" asset catalog color.
    static var primaryText: SwiftUI.Color { .init(.primaryText) }

    /// The "SecondaryText" asset catalog color.
    static var secondaryText: SwiftUI.Color { .init(.secondaryText) }

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

