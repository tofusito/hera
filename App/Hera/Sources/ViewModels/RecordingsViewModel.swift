// RecordingsViewModel.swift

import Foundation
import SwiftData
import AVFoundation
import Combine

/// ViewModel responsible for loading, filtering, and deleting recordings using MVVM.
class RecordingsViewModel: ObservableObject {
    @Published var displayableRecordings: [DisplayableRecording] = []
    @Published var filteredRecordings: [DisplayableRecording] = []
    @Published var searchText: String = ""

    private let audioManager: AudioManager
    private let modelContext: ModelContext
    private var cancellables = Set<AnyCancellable>()

    /// Initialize with dependencies: AudioManager and SwiftData ModelContext.
    init(audioManager: AudioManager, modelContext: ModelContext) {
        self.audioManager = audioManager
        self.modelContext = modelContext
        setupBindings()
        loadRecordings()
    }

    /// Configure Combine binding to update filtered list on search text changes.
    private func setupBindings() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                self?.filterRecordings(text)
            }
            .store(in: &cancellables)
    }

    /// Load recordings from filesystem and SwiftData, updating published properties.
    func loadRecordings() {
        guard let voiceMemosURL = audioManager.getVoiceMemosDirectoryURL() else {
            DispatchQueue.main.async {
                self.displayableRecordings = []
                self.filteredRecordings = []
            }
            return
        }

        let fileManager = FileManager.default
        var foundRecordings: [DisplayableRecording] = []
        var modified = false

        do {
            let folderURLs = try fileManager.contentsOfDirectory(at: voiceMemosURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles)

            for folderURL in folderURLs {
                guard let resourceValues = try? folderURL.resourceValues(forKeys: [.isDirectoryKey]),
                      resourceValues.isDirectory == true,
                      let recordingId = UUID(uuidString: folderURL.lastPathComponent)
                else { continue }

                let audioFileURL = folderURL.appendingPathComponent("audio.m4a")
                guard fileManager.fileExists(atPath: audioFileURL.path) else { continue }

                // Fetch existing SwiftData entry
                let fetchDescriptor = FetchDescriptor<AudioRecording>(predicate: #Predicate { $0.id == recordingId })
                if let existingData = try modelContext.fetch(fetchDescriptor).first {
                    // Update stored file URL if changed
                    if existingData.fileURL?.path != audioFileURL.path {
                        existingData.fileURL = audioFileURL
                        modified = true
                    }
                    // Update or clear transcription based on filesystem
                    let transcriptionFileURL = folderURL.appendingPathComponent("transcription.txt")
                    if fileManager.fileExists(atPath: transcriptionFileURL.path) {
                        let transcriptionText = (try? String(contentsOf: transcriptionFileURL, encoding: .utf8)) ?? ""
                        if existingData.transcription != transcriptionText {
                            existingData.transcription = transcriptionText
                            modified = true
                        }
                    } else if existingData.transcription != nil {
                        existingData.transcription = nil
                        modified = true
                    }

                    if let displayable = DisplayableRecording(from: existingData) {
                        foundRecordings.append(displayable)
                    }
                } else if let displayable = DisplayableRecording(id: recordingId, folderURL: folderURL) {
                    foundRecordings.append(displayable)
                    // Insert new SwiftData entry
                    let newRecording = AudioRecording(
                        id: displayable.id,
                        title: displayable.title,
                        timestamp: displayable.timestamp,
                        duration: displayable.duration,
                        fileURL: displayable.fileURL,
                        transcription: displayable.transcription,
                        analysis: displayable.analysis
                    )
                    modelContext.insert(newRecording)
                    modified = true
                }
            }

            if modelContext.hasChanges {
                try modelContext.save()
            }
        } catch {
            print("[RecordingsViewModel] Error loading recordings: \(error)")
        }

        // Sort by most recent first
        foundRecordings.sort { $0.timestamp > $1.timestamp }

        // Publish updates on the main thread
        DispatchQueue.main.async {
            self.displayableRecordings = foundRecordings
            self.filterRecordings(self.searchText)
        }

        // Clean up orphan SwiftData entries
        cleanupOrphanedSwiftDataEntries(filesystemIds: Set(foundRecordings.map { $0.id }))

        // If metadata changed, reload to reflect updates
        if modified {
            loadRecordings()
        }
    }

    /// Delete recordings at specified offsets: removes files and SwiftData entries.
    func deleteRecordings(at offsets: IndexSet) {
        let idsToDelete = offsets.compactMap { displayableRecordings[$0].id }
        let urlsToDelete = offsets.compactMap { displayableRecordings[$0].folderURL }

        for url in urlsToDelete {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // Remove from SwiftData
        let fetchDescriptor = FetchDescriptor<AudioRecording>(predicate: #Predicate { idsToDelete.contains($0.id) })
        do {
            let items = try modelContext.fetch(fetchDescriptor)
            for item in items {
                modelContext.delete(item)
            }
            try modelContext.save()
        } catch {
            print("[RecordingsViewModel] Error deleting data: \(error)")
        }

        // Update published properties
        DispatchQueue.main.async {
            self.displayableRecordings.remove(atOffsets: offsets)
            self.filterRecordings(self.searchText)
        }
    }

    /// Clears SwiftData entries without a corresponding folder on disk.
    private func cleanupOrphanedSwiftDataEntries(filesystemIds: Set<UUID>) {
        let fetchDescriptor = FetchDescriptor<AudioRecording>()
        do {
            let allItems = try modelContext.fetch(fetchDescriptor)
            let orphaned = allItems.filter { !filesystemIds.contains($0.id) }
            for item in orphaned {
                modelContext.delete(item)
            }
            if modelContext.hasChanges {
                try modelContext.save()
            }
        } catch {
            print("[RecordingsViewModel] Error cleaning orphan data: \(error)")
        }
    }

    /// Filter the displayable recordings based on a search query.
    func filterRecordings(_ query: String) {
        DispatchQueue.main.async {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                self.filteredRecordings = self.displayableRecordings
            } else {
                self.filteredRecordings = self.displayableRecordings.filter { recording in
                    recording.title.localizedCaseInsensitiveContains(trimmed)
                }
            }
        }
    }
} 