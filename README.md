# 🐱 Hera - Voice Recording & AI Analysis App

![Hera Logo](https://via.placeholder.com/150x150.png?text=Hera)

## 🌟 About Hera

Hera is a powerful voice recording application inspired by and named after my beloved cat, Hera. Just as she listens attentively to every sound in her environment, this app captures and understands your voice with precision and elegance.

## 🔥 Features

- 🎙️ **High-quality audio recording** with visual feedback
- 📝 **AI-powered transcription** of your recordings
- 🧠 **Intelligent analysis** of transcribed content
- 📊 **Summary generation** of key points from your recordings
- 📅 **Event detection** and calendar integration
- 📱 **Minimalist design** with pawprint-inspired UI elements
- 🌓 **Dark & light mode** support with adaptive colors
- 💾 **Import audio files** from other apps

## 🛠️ Technical Architecture

### Core Technologies
- **Swift & SwiftUI**: Modern UI framework for iOS
- **SwiftData**: For persistent data storage
- **AVFoundation**: For audio recording and playback
- **AI Integration**: OpenAI, Google Gemini, and Anthropic Claude API support

### App Structure

#### Data Models
- `AudioRecording`: SwiftData model for storing recording metadata
- `DisplayableRecording`: Structure for UI representation with additional metadata

#### Main Components
- **Content View**: Main interface with recording list and navigation
- **Record View**: UI for capturing new recordings with visual feedback
- **Playback View**: For listening to recordings with visualization
- **Transcription System**: Sends audio to AI APIs for text conversion
- **Analysis System**: Processes transcriptions to extract insights

### File System Structure
The app organizes recordings in a smart directory structure:
- Each recording has its own folder with a UUID identifier
- Inside each folder:
  - `audio.m4a`: The actual audio recording
  - `transcription.txt`: Plain text of the transcription (when available)
  - `analysis.json`: JSON data with AI analysis (when available)

## 🧩 Architecture Patterns

### MVVM Design
- **Models**: SwiftData entities like `AudioRecording`
- **Views**: SwiftUI components structured hierarchically
- **ViewModels**: Logic encapsulated in classes like `AudioManager`

### State Management
- `@StateObject` for view-local observable objects
- `@Environment` for accessing environment values
- `@AppStorage` for persistent user preferences
- `@Query` for SwiftData access

## 💡 Special Features

### Advanced Audio Management
The app maintains precise control over the audio lifecycle with the `AudioManager` class that:
- Handles recording sessions with proper permissions
- Manages audio levels for visualization
- Creates folder structures for new recordings
- Handles audio playback with timer synchronization

### Filesystem/Database Synchronization
The app implements a robust system to:
- Keep filesystem data and SwiftData in sync
- Clean up orphaned entries
- Detect and repair inconsistencies
- Import external audio files

### Adaptive UI
- Custom color schemes that adjust to light/dark mode
- Pawprint icon that changes color based on appearance
- Smooth animations and transitions for recording visualization

## 🐈 Inspiration: My Cat Hera

This project is a loving tribute to my cat Hera, whose attentive nature and discerning ear inspired the app's focus on listening and understanding. The minimalist pawprint logo represents her gentle presence, while the app's functionality mirrors her ability to pay attention to the important details in her environment.

## 🚀 Getting Started

1. Clone the repository
2. Open the project in Xcode
3. Build and run on your iOS device or simulator
4. For AI features, configure API keys in the settings

## 🔮 Future Plans

- Voice recognition for speaker identification
- Enhanced ML capabilities for more detailed analysis
- Cloud synchronization for recordings
- Sharing capabilities with other users
- Additional themes and UI customizations

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgements

- Apple for SwiftUI and SwiftData
- OpenAI, Google, and Anthropic for their AI APIs
- My cat Hera, for being my constant companion during development

---

*Made with ❤️ by Manuel Jesús Gutiérrez Fernández* 