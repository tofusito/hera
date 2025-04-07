import Foundation
import AVFoundation
import SwiftUI

class AudioManager: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var recordingTime: TimeInterval = 0
    @Published var currentAudioRecording: AudioRecording?
    @Published var audioLevel: Float = 0.0
    
    private var audioRecorder: AVAudioRecorder?
    internal var audioPlayer: AVAudioPlayer?
    internal var player: AVAudioPlayer? { return audioPlayer }
    private var timer: Timer?
    private var levelTimer: Timer?
    
    deinit {
        cleanupTimers()
    }
    
    override init() {
        super.init()
        verifyAndRepairDirectoryStructure()
    }
    
    private func cleanupTimers() {
        // Dedicated method to clean up timers
        if let timer = self.timer {
            timer.invalidate()
            self.timer = nil
        }
        
        if let levelTimer = self.levelTimer {
            levelTimer.invalidate()
            self.levelTimer = nil
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func startRecording() {
        // Stop any existing recording first
        if isRecording {
            _ = stopRecording()
        }
        
        // Stop any existing playback
        if isPlaying {
            stopPlayback()
        }
        
        // Clean up existing timers
        cleanupTimers()
        
        let recordingSession = AVAudioSession.sharedInstance()
        
        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default)
            try recordingSession.setActive(true)
            
            let timestamp = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "dd-MM-yyyy HH:mm:ss"
            let dateTimeString = formatter.string(from: timestamp)
            
            // Create a UUID for this recording
            let recordingId = UUID()
            
            // Create directory for this recording
            guard let recordingDirectory = createRecordingDirectory(for: recordingId) else {
                print("Error: Could not create directory for recording")
                return
            }
            
            // Save the file inside the specific folder
            let audioFileName = "audio.m4a"
            let fileURL = recordingDirectory.appendingPathComponent(audioFileName)
            
            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            let success = audioRecorder?.record() ?? false
            
            if !success {
                print("Error starting recording")
                return
            }
            
            // Create a new AudioRecording object
            let newRecording = AudioRecording(
                id: recordingId,
                title: dateTimeString,
                timestamp: timestamp,
                fileURL: fileURL
            )
            currentAudioRecording = newRecording
            isRecording = true
            recordingTime = 0
            audioLevel = 0.0
            
            // Start timer to update duration with a delay to ensure the recorder is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self, self.isRecording else { return }
                
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    guard let self = self, let recorder = self.audioRecorder, self.isRecording else { return }
                    self.recordingTime = recorder.currentTime
                }
                
                // Ensure the timer runs in the common run mode
                RunLoop.current.add(self.timer!, forMode: .common)
                
                // Start timer to update audio level
                self.levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    guard let self = self, let recorder = self.audioRecorder, self.isRecording else { return }
                    
                    recorder.updateMeters()
                    
                    // Get audio level from channel 0
                    let level = recorder.averagePower(forChannel: 0)
                    
                    // Convert dB level to a normalized value (0-1)
                    // dB values are typically between -160 and 0
                    let normalizedLevel = max(0.0, min(1.0, (level + 60) / 60))
                    
                    // Update on the main thread
                    DispatchQueue.main.async {
                        self.audioLevel = normalizedLevel
                    }
                }
                
                // Ensure the levelTimer runs in the common run mode
                RunLoop.current.add(self.levelTimer!, forMode: .common)
            }
            
        } catch {
            print("Could not start recording: \(error)")
            isRecording = false
            audioLevel = 0.0
        }
    }
    
    func stopRecording() -> AudioRecording? {
        // Verify we are actually recording
        guard isRecording, let recorder = audioRecorder else {
            isRecording = false
            audioLevel = 0.0
            cleanupTimers()
            return nil
        }
        
        // Capture the recording before stopping
        let capturedRecording = currentAudioRecording
        let capturedDuration = recordingTime
        
        // Stop recorder and clean up
        recorder.stop()
        audioRecorder = nil
        isRecording = false
        
        // Clean up timers
        cleanupTimers()
        
        // Update duration and return the recording
        if let recording = capturedRecording {
            // Use let instead of var, and create a new instance for modification
            let updatedRecording = AudioRecording(
                id: recording.id,
                title: recording.title,
                timestamp: recording.timestamp,
                duration: capturedDuration,
                fileURL: recording.fileURL
            )
            recordingTime = 0
            audioLevel = 0.0
            currentAudioRecording = nil
            return updatedRecording
        }
        
        return nil
    }
    
    func startPlayback(url: URL) {
        // Stop any existing playback
        if isPlaying {
            stopPlayback()
        }
        
        // Print URL for debugging
        print("Attempting to play file at: \(url.path)")
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("⚠️ ERROR: Audio file does not exist during startPlayback: \(url.path)")
            DispatchQueue.main.async {
                self.isPlaying = false
            }
            return
        }
        
        let playbackSession = AVAudioSession.sharedInstance()
        
        do {
            try playbackSession.setCategory(.playback, mode: .default)
            try playbackSession.setActive(true)
            
            // If we already have a player loaded, check if it's for the same URL
            if let existingPlayer = audioPlayer, existingPlayer.url == url {
                print("🔄 Using existing player already prepared")
                existingPlayer.currentTime = 0
                existingPlayer.play()
                
                DispatchQueue.main.async {
                    self.isPlaying = true
                    print("✅ Playback started with existing player")
                }
                return
            }
            
            // Create a new player
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            guard let player = audioPlayer else {
                print("Could not create audio player")
                return
            }
            
            player.delegate = self
            player.prepareToPlay()
            let success = player.play()
            
            if success {
                // Use DispatchQueue to update state after starting playback
                DispatchQueue.main.async {
                    self.isPlaying = true
                    print("✅ Playback started successfully")
                }
            } else {
                print("⚠️ The play() method returned false - Player is in invalid state")
                DispatchQueue.main.async {
                    self.isPlaying = false
                }
            }
        } catch {
            print("❌ Could not play audio: \(error)")
            DispatchQueue.main.async {
                self.isPlaying = false
            }
        }
    }
    
    func stopPlayback() {
        // Verify there is actually active playback
        guard isPlaying, let player = audioPlayer else {
            print("⚠️ stopPlayback: No active playback to stop")
            DispatchQueue.main.async {
                self.isPlaying = false
            }
            return
        }
        
        print("⏹️ Stopping playback explicitly")
        player.stop()
        // Only free resources if really necessary
        // audioPlayer = nil // Commented to allow reuse
        
        // Use DispatchQueue to update state after stopping playback
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }
    
    func prepareToPlay(url: URL, completion: @escaping (Bool, TimeInterval) -> Void) {
        // Stop any existing playback
        if isPlaying {
            stopPlayback()
        }
        
        // Print URL for debugging
        print("Preparing audio at: \(url.path)")
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("⚠️ ERROR: Audio file does not exist during prepareToPlay: \(url.path)")
            completion(false, 0)
            return
        }
        
        let playbackSession = AVAudioSession.sharedInstance()
        
        do {
            try playbackSession.setCategory(.playback, mode: .default)
            try playbackSession.setActive(true)
            
            let tempPlayer = try AVAudioPlayer(contentsOf: url)
            tempPlayer.prepareToPlay()
            
            // Record duration for later use
            let audioDuration = tempPlayer.duration
            
            // Make sure tempPlayer is not released too early
            self.audioPlayer = tempPlayer
            
            print("✅ Audio prepared successfully - Duration: \(audioDuration)s")
            completion(true, audioDuration)
        } catch {
            print("❌ Error preparing audio: \(error)")
            audioPlayer = nil
            completion(false, 0)
        }
    }
    
    // Delegates
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording finished with an error")
        }
        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0.0
            self.cleanupTimers()
        }
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("🏁 Playback naturally finished")
        // Don't immediately stop the player, allow it to be reused
        DispatchQueue.main.async {
            self.isPlaying = false
            // Don't clean up audioPlayer = nil here to allow reuse
        }
    }
    
    // Function to create folder structure for recordings
    func createRecordingDirectory(for recordingId: UUID) -> URL? {
        guard let voiceMemosURL = getVoiceMemosDirectoryURL() else {
            return nil
        }
        
        let recordingDirectoryURL = voiceMemosURL.appendingPathComponent(recordingId.uuidString, isDirectory: true)
        
        // Create specific directory for this recording with its UUID
        if !FileManager.default.fileExists(atPath: recordingDirectoryURL.path) {
            do {
                try FileManager.default.createDirectory(at: recordingDirectoryURL, withIntermediateDirectories: true)
            } catch {
                print("Error creating directory for recording: \(error)")
                return nil
            }
        }
        
        return recordingDirectoryURL
    }

    // Method to get the URL of the directory where recordings are saved
    func getVoiceMemosDirectoryURL() -> URL? {
        // Documents directory
        let documentsURL = getDocumentsDirectory()
        
        // Create main Hera directory if it doesn't exist
        let heraDirectoryURL = documentsURL.appendingPathComponent("Hera", isDirectory: true)
        if !FileManager.default.fileExists(atPath: heraDirectoryURL.path) {
            do {
                try FileManager.default.createDirectory(at: heraDirectoryURL, withIntermediateDirectories: true)
            } catch {
                print("Error creating Hera directory: \(error)")
                return nil
            }
        }
        
        // Create VoiceNotes directory inside Hera
        let voiceNotesURL = heraDirectoryURL.appendingPathComponent("VoiceNotes", isDirectory: true)
        if !FileManager.default.fileExists(atPath: voiceNotesURL.path) {
            do {
                try FileManager.default.createDirectory(at: voiceNotesURL, withIntermediateDirectories: true)
            } catch {
                print("Error creating VoiceNotes directory: \(error)")
                return nil
            }
        }
        
        return voiceNotesURL
    }
    
    // Create Hera directory for processing files
    // This is a helper function for internal use
    func getOrCreateHeraDirectory() -> URL? {
        let documentsURL = getDocumentsDirectory()
        let heraDirectoryURL = documentsURL.appendingPathComponent("Hera", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: heraDirectoryURL.path) {
            do {
                try FileManager.default.createDirectory(at: heraDirectoryURL, withIntermediateDirectories: true)
            } catch {
                print("Error creating Hera directory: \(error)")
                return nil
            }
        }
        
        return heraDirectoryURL
    }
    
    // Verify and repair directory structure
    func verifyAndRepairDirectoryStructure() {
        print("📂 Verifying directory structure...")
        
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ Could not access documents directory")
            return
        }
        
        // Verify/create main Hera directory
        let heraDirectoryURL = documentsDirectory.appendingPathComponent("Hera", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: heraDirectoryURL.path) {
            do {
                try FileManager.default.createDirectory(at: heraDirectoryURL, withIntermediateDirectories: true)
                print("✅ Created main Hera directory: \(heraDirectoryURL.path)")
            } catch {
                print("❌ Error creating main Hera directory: \(error)")
            }
        } else {
            print("✓ Main Hera directory exists: \(heraDirectoryURL.path)")
        }
        
        // Verify/create VoiceNotes directory inside Hera
        let voiceNotesURL = heraDirectoryURL.appendingPathComponent("VoiceNotes", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: voiceNotesURL.path) {
            do {
                try FileManager.default.createDirectory(at: voiceNotesURL, withIntermediateDirectories: true)
                print("✅ Created VoiceNotes directory: \(voiceNotesURL.path)")
            } catch {
                print("❌ Error creating VoiceNotes directory: \(error)")
            }
        } else {
            print("✓ VoiceNotes directory exists: \(voiceNotesURL.path)")
        }
        
        // Verify write permissions
        if FileManager.default.isWritableFile(atPath: voiceNotesURL.path) {
            print("✓ VoiceNotes directory has write permissions")
            
            // Create a temporary file to test
            let testFile = voiceNotesURL.appendingPathComponent("test_write.txt")
            do {
                try "Test write".write(to: testFile, atomically: true, encoding: .utf8)
                print("✓ Write test successful")
                
                // Delete temporary file
                try FileManager.default.removeItem(at: testFile)
            } catch {
                print("❌ Error in write test: \(error)")
            }
        } else {
            print("❌ VoiceNotes directory does not have write permissions")
        }
        
        // Migrate files from old structure if it exists
        let oldVoiceRecordingsURL = documentsDirectory.appendingPathComponent("VoiceRecordings", isDirectory: true)
        if FileManager.default.fileExists(atPath: oldVoiceRecordingsURL.path) {
            print("🔄 Found old VoiceRecordings directory, migrating files...")
            
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: oldVoiceRecordingsURL, includingPropertiesForKeys: nil)
                
                if contents.isEmpty {
                    print("✓ Old directory empty, deleting...")
                    try FileManager.default.removeItem(at: oldVoiceRecordingsURL)
                } else {
                    print("🔄 Migrating \(contents.count) items...")
                    
                    for itemURL in contents {
                        let destURL = voiceNotesURL.appendingPathComponent(itemURL.lastPathComponent)
                        
                        if !FileManager.default.fileExists(atPath: destURL.path) {
                            try FileManager.default.moveItem(at: itemURL, to: destURL)
                            print("  ✓ Migrated: \(itemURL.lastPathComponent)")
                        } else {
                            print("  ⚠️ Already exists in destination: \(itemURL.lastPathComponent)")
                        }
                    }
                    
                    // Check if it's empty now to delete
                    let remainingContents = try FileManager.default.contentsOfDirectory(at: oldVoiceRecordingsURL, includingPropertiesForKeys: nil)
                    if remainingContents.isEmpty {
                        try FileManager.default.removeItem(at: oldVoiceRecordingsURL)
                        print("✅ Old directory deleted after migration")
                    }
                }
            } catch {
                print("❌ Error during migration: \(error)")
            }
        }
    }
    
    // Public method to list and verify recordings
    func listAndVerifyRecordings() {
        print("📊 Verifying existing recordings...")
        
        guard let voiceMemosURL = getVoiceMemosDirectoryURL() else {
            print("❌ Could not access recordings directory")
            return
        }
        
        do {
            // Get all items in the main directory
            let contents = try FileManager.default.contentsOfDirectory(at: voiceMemosURL, includingPropertiesForKeys: nil)
            
            print("📁 Found \(contents.count) recording folders.")
            
            // Verify each recording folder
            for folderURL in contents {
                if folderURL.hasDirectoryPath {
                    let folderName = folderURL.lastPathComponent
                    print("  📂 Folder: \(folderName)")
                    
                    // List folder contents
                    do {
                        let folderContents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                        print("    📄 Contains \(folderContents.count) files:")
                        
                        // Check each file
                        for fileURL in folderContents {
                            let fileName = fileURL.lastPathComponent
                            print("      - \(fileName) (\(getSizeString(for: fileURL)))")
                        }
                        
                        // Verify audio file
                        let audioURL = folderURL.appendingPathComponent("audio.m4a")
                        if FileManager.default.fileExists(atPath: audioURL.path) {
                            print("    ✅ Audio file exists")
                        } else {
                            print("    ❌ Audio file does NOT exist")
                        }
                        
                        // Verify transcription
                        let transcriptionURL = folderURL.appendingPathComponent("transcription.txt")
                        if FileManager.default.fileExists(atPath: transcriptionURL.path) {
                            print("    ✅ Transcription file exists")
                        } else {
                            print("    ⚠️ Transcription file does NOT exist")
                        }
                        
                        // Verify analysis
                        let analysisURL = folderURL.appendingPathComponent("analysis.json")
                        if FileManager.default.fileExists(atPath: analysisURL.path) {
                            print("    ✅ Analysis file exists")
                        } else {
                            print("    ⚠️ Analysis file does NOT exist")
                        }
                    } catch {
                        print("    ❌ Error listing contents: \(error)")
                    }
                }
            }
        } catch {
            print("❌ Error listing recordings: \(error)")
        }
    }
    
    // Get readable size of a file
    private func getSizeString(for fileURL: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let size = attributes[.size] as? NSNumber {
                let sizeBytes = size.int64Value
                
                if sizeBytes < 1024 {
                    return "\(sizeBytes) bytes"
                } else if sizeBytes < 1024 * 1024 {
                    let sizeKB = Double(sizeBytes) / 1024.0
                    return String(format: "%.1f KB", sizeKB)
                } else {
                    let sizeMB = Double(sizeBytes) / (1024.0 * 1024.0)
                    return String(format: "%.2f MB", sizeMB)
                }
            }
        } catch {
            // Silent error
        }
        return "unknown size"
    }
} 
