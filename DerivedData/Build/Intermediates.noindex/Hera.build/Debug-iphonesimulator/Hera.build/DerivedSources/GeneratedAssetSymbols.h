#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"Tofu.Hera";

/// The "Background" asset catalog color resource.
static NSString * const ACColorNameBackground AC_SWIFT_PRIVATE = @"Background";

/// The "ButtonBackground" asset catalog color resource.
static NSString * const ACColorNameButtonBackground AC_SWIFT_PRIVATE = @"ButtonBackground";

/// The "CardBackground" asset catalog color resource.
static NSString * const ACColorNameCardBackground AC_SWIFT_PRIVATE = @"CardBackground";

/// The "DarkBackground" asset catalog color resource.
static NSString * const ACColorNameDarkBackground AC_SWIFT_PRIVATE = @"DarkBackground";

/// The "ListBackground" asset catalog color resource.
static NSString * const ACColorNameListBackground AC_SWIFT_PRIVATE = @"ListBackground";

/// The "PrimaryText" asset catalog color resource.
static NSString * const ACColorNamePrimaryText AC_SWIFT_PRIVATE = @"PrimaryText";

/// The "SecondaryText" asset catalog color resource.
static NSString * const ACColorNameSecondaryText AC_SWIFT_PRIVATE = @"SecondaryText";

#undef AC_SWIFT_PRIVATE
