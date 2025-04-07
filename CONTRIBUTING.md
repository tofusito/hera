# Contributing to Hera

Thank you for your interest in contributing to Hera! This document provides information on how to contribute to the project.

## Project Structure

The project is organized as follows:

```
App/                          # Main application directory
├── Hera.xcodeproj/           # Xcode project file
├── Hera/                     # Main app code
│   ├── Sources/
│   │   ├── App/              # App entry point
│   │   ├── Models/           # Data models
│   │   ├── Views/            # SwiftUI views
│   │   ├── Services/         # Services (OpenAI, Audio, etc.)
│   │   ├── Utils/            # Common utilities
│   │   └── Extensions/       # Swift/UIKit extensions
│   ├── Assets.xcassets/      # App graphic resources
│   ├── Info.plist            # App configuration
│   └── Hera.entitlements     # App entitlements
├── HeraTests/                # Unit tests
├── HeraUITests/              # UI tests
└── Resources/                # App resources
    ├── Banner/               # Banner images for README
    └── Icon/                 # App icons
```

## Code Guidelines

- Use SwiftUI for user interfaces when possible
- Follow the MVVM (Model-View-ViewModel) architecture
- Use services for complex or network operations
- Comment your code appropriately
- Write descriptive names for variables and functions

## Pull Request Process

1. Fork the repository
2. Create a branch with a descriptive name
3. Make your changes
4. Ensure tests pass
5. Submit a Pull Request with a clear description of the changes

## Commit Conventions

Please follow these conventions for commit messages:

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Formatting, missing semicolons, etc.
- `refactor`: Code refactoring
- `test`: Adding or refactoring tests
- `chore`: Changes to the build process, tools, etc.

Example: `feat: add calendar detection in transcriptions`

## License

By contributing to this project, you agree that your contributions will be licensed under the same MIT license that covers the project. 