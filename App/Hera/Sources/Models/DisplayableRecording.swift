// DisplayableRecording.swift
// Created by AI assistant.
// This struct represents a recording with displayable properties for listing and playback.

import Foundation
import SwiftData
import SwiftUI

/// Model for displaying recording details in the app
struct DisplayableRecording: Identifiable {
    let id: UUID
    var title: String
    var timestamp: Date
    var duration: TimeInterval
    var folderURL: URL    // URL of the recording folder
    var fileURL: URL      // URL of the audio file inside the folder
    var transcription: String? // Optional transcription text
    var analysis: String?      // Optional analysis result
    
    /// Initializes from an AudioRecording SwiftData entity
    init?(from audioRecording: AudioRecording) {
        guard let url = audioRecording.fileURL else { return nil }
        self.id = audioRecording.id
        self.title = audioRecording.title
        self.timestamp = audioRecording.timestamp
        self.duration = audioRecording.duration
        self.fileURL = url
        self.folderURL = url.deletingLastPathComponent()
        self.transcription = audioRecording.transcription
        self.analysis = audioRecording.analysis
    }
    
    /// Initializes from a file system folder URL and optional FileManager
    init?(id: UUID, folderURL: URL, fileManager: FileManager = .default) {
        let audioFileURL = folderURL.appendingPathComponent("audio.m4a")
        guard fileManager.fileExists(atPath: audioFileURL.path) else {
            return nil // Expected audio file not found
        }
        self.id = id
        self.folderURL = folderURL
        self.fileURL = audioFileURL
        
        // Default timestamp from folder creation date
        do {
            let attributes = try fileManager.attributesOfItem(atPath: folderURL.path)
            self.timestamp = attributes[.creationDate] as? Date ?? Date()
        } catch {
            self.timestamp = Date()
        }
        self.title = "Recording - \(id.uuidString.prefix(4))"
        self.duration = 0
        
        // Load transcription from file if available
        let transcriptionFileURL = folderURL.appendingPathComponent("transcription.txt")
        if fileManager.fileExists(atPath: transcriptionFileURL.path) {
            do {
                self.transcription = try String(contentsOf: transcriptionFileURL, encoding: .utf8)
            } catch {
                self.transcription = nil
            }
        } else {
            self.transcription = nil
        }
        
        // Load analysis from JSON file if available
        let analysisFileURL = folderURL.appendingPathComponent("analysis.json")
        if fileManager.fileExists(atPath: analysisFileURL.path) {
            do {
                let data = try Data(contentsOf: analysisFileURL)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    self.analysis = content
                } else {
                    self.analysis = nil
                }
            } catch {
                self.analysis = nil
            }
        } else {
            self.analysis = nil
        }
    }
} 