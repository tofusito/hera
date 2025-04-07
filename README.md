<p align="center">
  <img src="Resources/Banner/banner.png" alt="Hera Banner" width="600" />
</p>

# 🐾 Hera – Your Voice, Turned Into Action

<p align="center">
  <img src="Resources/Icon/icon_resource.png" alt="Hera Logo" width="150" />
</p>

<p align="center">
  <a href="https://www.buymeacoffee.com/tofusito"><img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-%E2%98%95-lightgrey" alt="Buy Me A Coffee" /></a>
  <img src="https://img.shields.io/badge/version-0.1.0-blue" alt="Version">
  <img src="https://img.shields.io/badge/license-Custom-green" alt="License">
  <img src="https://img.shields.io/badge/made%20with-Swift-orange" alt="Swift">
</p>

**Minimalist AI voice note app, lovingly inspired by a tuxedo cat.**  
Capture your thoughts. Convert them into documents. Organize your life.

---

## 📑 Table of Contents

- [✨ What is Hera?](#-what-is-hera)
- [🧠 What Can Hera Do?](#-what-can-hera-do)
- [☕ Help Bring Hera to the App Store](#-help-bring-hera-to-the-app-store)
- [🛠️ Tech Stack & Architecture](#️-tech-stack--architecture)
- [💡 Smart Features](#-smart-features)
- [🚀 Getting Started](#-getting-started)
- [🧪 Testing](#-testing)
- [📁 Project Structure](#-project-structure)
- [🐈 Who's Hera?](#-whos-hera)
- [🛣️ What's Next?](#️-whats-next)
- [🤝 Contributing](#-contributing)
- [📝 License](#-license)

---

## ✨ What is Hera?

**Hera** is more than a voice recording app.  
It's your intelligent, cat-powered productivity assistant — turning messy voice notes into structured documents, reminders, and calendar events — all in a calming, minimalist UI.

Inspired by Hera, my feline muse with perfect listening skills and zero tolerance for chaos, this app brings clarity to your thoughts and purrfection to your day.

---

## 🧠 What Can Hera Do?

- 🎙️ Record voice notes with visual feedback and high quality  
- 📝 Transcribe your recordings using OpenAI  
- 🧾 Generate full documents from your ramblings – summaries, structured notes, even meeting minutes  
- 📅 Detect calendar events and to-dos and suggest adding them to your system  
- 📤 Integrate with iOS Calendar & Reminders in one tap  
- 💾 Import audio from other sources and process it like magic  
- 🎨 Minimalist interface inspired by Hera's quiet dignity  
- 🌗 Dark and light mode with adaptive pawprint themes

---

## ☕ Help Bring Hera to the App Store

Currently, Hera lives only on my iPhone, silently judging me and saving my productivity.

But to release it to the world, I need to join the Apple Developer Program (99€/year – yes, I cried too).

If this app sounds useful, charming, or at least less annoying than your own brain, consider supporting the launch:

### 👉 [Buy me a coffee so Hera can go global](https://www.buymeacoffee.com/tofusito)

<p align="center">
  <a href="https://www.buymeacoffee.com/tofusito">
    <img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Coffee" width="200"/>
  </a>
</p>

**Your support helps me:**
- 🚀 Publish the app on the App Store  
- 🧪 Add new features, polish existing ones  
- 🐛 Feed the developer (me, not Hera)  
- 🧼 Keep the UX clean and cat-approved

---

## 🛠️ Tech Stack & Architecture

### 🔧 Core Technologies

- Swift & SwiftUI – for beautiful native UI  
- SwiftData – clean local data persistence  
- AVFoundation – audio recording & playback  
- OpenAI API – for transcription, summarization, and content generation

### 📂 File Structure

Each recording is stored in a self-contained folder:

```UUID/
├── audio.m4a
├── transcription.txt
└── analysis.json
```

### 🧩 MVVM Structure

- `AudioRecording`: SwiftData model for voice notes  
- `DisplayableRecording`: View-ready struct with metadata  
- `AudioManager`: Handles recording, playback, folder structure  
- `OpenAIService`: Sends audio to AI and parses response  
- `CalendarManager`: Manages calendar events and reminders integration

---

## 💡 Smart Features

### 🧾 Document Generation

Turn voice notes into:
- Blog drafts  
- Meeting minutes  
- Daily journals  
- Cleanly formatted Markdown documents

### 📆 Event & Reminder Detection

Say things like "remind me to call Alex on Friday" or "meeting at 3pm with Marta" and Hera will:
- Detect it  
- Suggest it  
- Let you add it to your Calendar or Reminders with one tap

### 🌈 Adaptive UI

- Light/Dark mode with cat-themed details  
- Pawprint icon shifts color based on system appearance  
- Smooth visualizers while recording/playback

---

## 🚀 Getting Started

1. Clone the repo
   ```bash
   git clone https://github.com/yourusername/hera.git
   cd hera
   ```

2. Open the project in Xcode
   ```bash
   open App/Hera.xcodeproj
   ```

3. OpenAI API key configuration
   - The app includes a settings screen to configure your OpenAI API key directly
   - You'll be prompted to add your API key when attempting to transcribe a recording
   - API keys are securely stored in the device's keychain

4. Build and run the project (⌘+R)

---

## 🧪 Testing

Run tests using Xcode's testing framework (⌘+U).

The project contains:
- Unit tests in `HeraTests/`
- UI tests in `HeraUITests/`

---

## 📁 Project Structure

This project follows a modular architecture to keep code organized:

```
App/                          # Main application directory
├── Hera.xcodeproj/           # Xcode project file
├── Hera/                     # Main app code
│   ├── Sources/
│   │   ├── App/              # App entry point
│   │   ├── Models/           # Data models
│   │   ├── Views/            # SwiftUI views
│   │   ├── Services/         # Services (OpenAI, Audio)
│   │   ├── Utils/            # Common utilities
│   │   └── Extensions/       # Swift/UIKit extensions
│   ├── Assets.xcassets/      # App assets
│   ├── Info.plist            # App configuration
│   └── Hera.entitlements     # App entitlements
├── HeraTests/                # Unit tests
├── HeraUITests/              # UI tests
└── Resources/                # App resources
```

---

## 🐈 Who's Hera?

Hera is my tuxedo cat. She listens more than most humans.  
She inspired this app with her calm presence, sharp focus, and general refusal to tolerate nonsense.  
So I built an app that pays attention like she does.

---

## 🛣️ What's Next?

- ☁️ iCloud sync  
- 📄 Export to PDF  
- 🔗 Share recordings & docs with friends  
- 🐈 Animated Hera mood tracker (yes, seriously)

---

## 🤝 Contributing

Contributions are welcome! Please check out our [Contributing Guidelines](CONTRIBUTING.md) for more details on how to participate in this project.

---

## 📝 License

Custom license - Source code is available for viewing and educational purposes, but commercial usage and distribution rights are reserved by the author. See the [LICENSE](LICENSE) file for details.

---

**Made with ❤️, 🍵 and 🐾 by [Manuel Gutiérrez](https://www.buymeacoffee.com/tofusito)**

