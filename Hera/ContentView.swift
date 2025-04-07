//
//  ContentView.swift
//  Memo
//
//  Created by Manuel Jesús Gutiérrez Fernández on 27/3/25.
//

import SwiftUI
import SwiftData
import AVFoundation
import UniformTypeIdentifiers

// Estructura para la información combinada a mostrar
struct DisplayableRecording: Identifiable {
    let id: UUID
    var title: String
    var timestamp: Date
    var duration: TimeInterval
    var folderURL: URL // La URL de la carpeta de la grabación
    var fileURL: URL   // La URL del archivo audio.m4a dentro de la carpeta
    var transcription: String? // Añadido para la vista de reproducción
    var analysis: String? // Análisis procesado de la transcripción
    
    // Inicializador desde AudioRecording (SwiftData)
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
    
    // Inicializador desde datos del sistema de archivos
    init?(id: UUID, folderURL: URL, fileManager: FileManager = .default) {
        let audioFileURL = folderURL.appendingPathComponent("audio.m4a")
        guard fileManager.fileExists(atPath: audioFileURL.path) else {
            return nil // No existe el archivo de audio esperado
        }
        
        self.id = id
        self.folderURL = folderURL
        self.fileURL = audioFileURL
        
        // Valores por defecto (se podrían leer metadatos si existieran)
        // Intentamos obtener la fecha de creación de la carpeta como timestamp
        do {
            let attributes = try fileManager.attributesOfItem(atPath: folderURL.path)
            self.timestamp = attributes[.creationDate] as? Date ?? Date()
        } catch {
            self.timestamp = Date()
        }
        self.title = "Grabación - \(id.uuidString.prefix(4))"
        self.duration = 0 // Se podría cargar desde AVAsset si fuera necesario aquí
        
        // Comprobar si existe el archivo de transcripción
        let transcriptionFileURL = folderURL.appendingPathComponent("transcription.txt")
        if fileManager.fileExists(atPath: transcriptionFileURL.path) {
            do {
                // Leer transcripción desde el archivo
                self.transcription = try String(contentsOf: transcriptionFileURL, encoding: .utf8)
                print("📄 Transcripción cargada desde archivo: \(transcriptionFileURL.path)")
            } catch {
                print("⚠️ No se pudo leer el archivo de transcripción: \(error)")
                self.transcription = nil
            }
        } else {
            self.transcription = nil
        }
        
        // Comprobar si existe el archivo de análisis
        let analysisFileURL = folderURL.appendingPathComponent("analysis.json")
        if fileManager.fileExists(atPath: analysisFileURL.path) {
            do {
                // Leer análisis desde el archivo
                let analysisData = try Data(contentsOf: analysisFileURL)
                if let json = try JSONSerialization.jsonObject(with: analysisData, options: []) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    self.analysis = content
                    print("📄 Análisis cargado desde archivo: \(analysisFileURL.path)")
                } else {
                    self.analysis = nil
                }
            } catch {
                print("⚠️ No se pudo leer el archivo de análisis: \(error)")
                self.analysis = nil
            }
        } else {
            self.analysis = nil
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var allRecordingsData: [AudioRecording] // Todas las grabaciones de SwiftData
    @StateObject private var audioManager = AudioManager()
    @State private var isShowingRecordView = false
    @State private var selectedRecordingForPlayback: DisplayableRecording? // Cambiado a DisplayableRecording
    @State private var showingSettingsSheet = false
    @State private var showingNotesList = false
    @State private var showingImportSheet = false
    @State private var isImporting = false
    
    @State private var displayableRecordings: [DisplayableRecording] = [] // Estado para la lista
    @State private var filteredRecordings: [DisplayableRecording] = [] // Grabaciones filtradas
    @State private var searchText: String = "" // Texto de búsqueda
    
    @State private var playbackViewKey = UUID() // Añadir una clave única y estable para el PlaybackViewWrapper
    
    @State private var isDebugModeEnabled = true // Variables para diagnóstico
    
    // Colores personalizados
    private let iconColor = Color("PrimaryText") // Color adaptativo para iconos
    
    var body: some View {
        // Extraer el contenido principal en una función separada
        mainContentView()
            .sheet(isPresented: $isShowingRecordView, onDismiss: {
                // Asegurar que audioManager está en un estado limpio después de cerrar
                if audioManager.isRecording {
                    _ = audioManager.stopRecording() // Uso explícito del resultado con _ para evitar warning
                }
                // Recargar las grabaciones al volver
                loadRecordingsFromFilesystem()
            }) {
                RecordView(audioManager: audioManager, modelContext: modelContext)
            }
            .sheet(item: $selectedRecordingForPlayback) { recording in
                playbackSheetView(for: recording)
                    .onDisappear {
                        // Recargar las grabaciones al volver para reflejar cualquier cambio de título
                        loadRecordingsFromFilesystem()
                    }
            }
            .sheet(isPresented: $showingSettingsSheet) {
                APISettingsView()
            }
            .sheet(isPresented: $showingNotesList) {
                NotesListView()
            }
            .sheet(isPresented: $showingImportSheet) {
                ImportOptionsView(modelContext: modelContext)
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [UTType.audio, UTType.mp3, UTType.wav, UTType(filenameExtension: "m4a")!, UTType.mpeg4Audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let selectedURL = urls.first else { return }
                    importAudioFile(from: selectedURL)
                case .failure(let error):
                    print("Error al importar audio: \(error.localizedDescription)")
                }
            }
            .onOpenURL { url in
                // Este método se llama cuando otra app comparte un archivo con esta app
                if url.pathExtension.lowercased() == "m4a" ||
                   url.pathExtension.lowercased() == "mp3" ||
                   url.pathExtension.lowercased() == "wav" {
                    importAudioFile(from: url)
                }
            }
            .onAppear {
                loadRecordingsFromFilesystem() // Carga inicial
                
                // Configurar observador para importar audio
                let notificationCenter = NotificationCenter.default
                notificationCenter.addObserver(forName: .importAudio, object: nil, queue: .main) { _ in
                    isImporting = true
                }
                
                // Añadir observador para mostrar la configuración de API
                notificationCenter.addObserver(forName: Notification.Name("ShowAPISettings"), object: nil, queue: .main) { _ in
                    showingSettingsSheet = true
                }
                
                // Añadir observador para refrescar la lista de grabaciones (para actualizaciones de títulos)
                notificationCenter.addObserver(forName: Notification.Name("RefreshRecordingsList"), object: nil, queue: .main) { _ in
                    loadRecordingsFromFilesystem()
                }
            }
            .onChange(of: allRecordingsData) { _, _ in // Recargar si SwiftData cambia
                loadRecordingsFromFilesystem()
            }
            .onDisappear {
                // Eliminar observador cuando la vista desaparezca
                NotificationCenter.default.removeObserver(self)
            }
            .tint(AppColors.adaptiveTint) // Color de acento adaptativo
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Menu con opciones
                    Menu {
                        Button(action: {
                            showingSettingsSheet = true
                        }) {
                            Label("API Key", systemImage: "key")
                        }
                        
                        Divider()
                        
                        Button(action: {
                            loadRecordingsFromFilesystem()
                        }) {
                            Label("Reload Recordings", systemImage: "arrow.clockwise")
                        }
                        
                        if isDebugModeEnabled {
                            Divider()
                            
                            Button(action: {
                                debugRun()
                            }) {
                                Label("Run Debug", systemImage: "ladybug")
                            }
                            
                            Button(action: {
                                verifyFilesystem()
                            }) {
                                Label("Check Files", systemImage: "folder.badge.questionmark")
                            }
                        }
                    } label: {
                        Label("Menu", systemImage: "ellipsis.circle")
                    }
                }
            }
    }
    
    // MARK: - Vista principal separada
    @ViewBuilder
    private func mainContentView() -> some View {
        ZStack {
            // Usar explícitamente nuestro color Background definido
            Color("Background").ignoresSafeArea()
            
            VStack {
                // Título navegación personalizado con botón de importar
                titleBarView()
                
                if displayableRecordings.isEmpty {
                    emptyStateView()
                } else {
                    recordingListView()
                }
            }
            
            // Botón flotante de importar
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        showingImportSheet = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(colorScheme == .dark ? Color.gray.opacity(0.3) : Color.gray.opacity(0.8))
                                .frame(width: 56, height: 56)
                                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                            
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? Color(white: 0.9) : Color.white)
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 120) // Espacio aumentado para que no quede tapado por la barra
                }
            }
            
            // Barra inferior
            bottomBarView()
        }
        .background(Color("Background"))
    }
    
    // MARK: - Componentes de UI
    @ViewBuilder
    private func titleBarView() -> some View {
        VStack {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 28))
                .foregroundColor(colorScheme == .dark ? Color(white: 0.9) : Color(white: 0.2))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
    
    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "waveform").font(.system(size: 50)).foregroundColor(AppColors.adaptiveText)
            Text("No recordings")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.adaptiveText)
            Text("Tap the microphone button to start recording")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
    }
    
    @ViewBuilder
    private func recordingListView() -> some View {
        VStack {
            // Search bar
            SearchBar(text: $searchText, placeholder: "Search recordings")
                .padding(.horizontal)
                .padding(.top, 8)
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    let recordingsToShow = searchText.isEmpty ? displayableRecordings : filteredRecordings
                    
                    ForEach(recordingsToShow) { recording in
                        DisplayableRecordingCell(recording: recording)
                            .contentShape(Rectangle())
                            .shadow(color: colorScheme == .dark ?
                                    Color.black.opacity(0.08) :
                                    Color.black.opacity(0.12),
                                    radius: 3, x: 0, y: 2)
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                            .onTapGesture {
                                handleRecordingTap(recording)
                            }
                    }
                    .onDelete(perform: deleteRecordingsFromFilesystem)
                }
                .padding(.vertical)
            }
            .scrollIndicators(.hidden)
        }
        .onChange(of: searchText) { newValue in
            filterRecordings()
        }
    }
    
    @ViewBuilder
    private func bottomBarView() -> some View {
        VStack {
            Spacer()
            
            HStack {
                // Notes list icon (left) with shadow
                Button {
                    showingNotesList = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(.thinMaterial)
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "list.bullet")
                            .font(.title3)
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : iconColor)
                    }
                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                }
                .padding(.leading, 30)
                
                Spacer()
                
                // Central recording button (with shadow)
                Button {
                    isShowingRecordView = true
                } label: {
                    ZStack {
                        // Background material with glass effect
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 74, height: 74)
                        
                        // Main circle with soft border
                        Circle()
                            .fill(Color(.white).opacity(colorScheme == .dark ? 0.2 : 0.9))
                            .frame(width: 66, height: 66)
                            .overlay(
                                Circle()
                                    .stroke(Color(.white), lineWidth: colorScheme == .dark ? 1.5 : 0.5)
                                    .opacity(colorScheme == .dark ? 0.5 : 0.8)
                            )
                            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                    }
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.18),
                            radius: 12, x: 0, y: 4)
                    .offset(y: -2) // Slightly elevated to give a relief sensation
                }
                
                Spacer()
                
                // Settings icon (right) with shadow
                Button {
                    showingSettingsSheet = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(.thinMaterial)
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "gear")
                            .font(.title3)
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : iconColor)
                    }
                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                }
                .padding(.trailing, 30)
            }
            .padding(.bottom, 20)
            .padding(.top, 8)
            .background(
                Rectangle()
                    .fill(.regularMaterial)
                    .opacity(colorScheme == .dark ? 0.6 : 0.7)
                    .ignoresSafeArea(edges: .bottom)
                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: -1)
            )
        }
    }
    
    // MARK: - Playback View
    @ViewBuilder
    private func playbackSheetView(for recording: DisplayableRecording) -> some View {
        NavigationView {
            // Find recording in SwiftData with separate function
            let originalRecording = findOrCreateRecording(from: recording)
            
            // Show playback view
            PlaybackView(audioManager: audioManager, recording: originalRecording)
                .id(recording.id) // Fixed ID to prevent regeneration
        }
    }
    
    // MARK: - Helper Functions
    private func findOrCreateRecording(from displayableRecording: DisplayableRecording) -> AudioRecording {
        // Search for recording in SwiftData
        let fetchDescriptor = FetchDescriptor<AudioRecording>()
        let allRecordings = (try? modelContext.fetch(fetchDescriptor)) ?? []
        
        // Search by ID
        if let found = allRecordings.first(where: { $0.id == displayableRecording.id }) {
            return found
        }
        
        // If it doesn't exist, create a new one
        return AudioRecording(
            id: displayableRecording.id,
            title: displayableRecording.title,
            timestamp: displayableRecording.timestamp,
            duration: displayableRecording.duration,
            fileURL: displayableRecording.fileURL,
            transcription: displayableRecording.transcription,
            analysis: displayableRecording.analysis
        )
    }
    
    private func handleRecordingTap(_ recording: DisplayableRecording) {
        // First stop any current playback to avoid conflicts
        if audioManager.isPlaying {
            audioManager.stopPlayback()
        }
        
        // Use DispatchQueue to avoid state changes during updates
        DispatchQueue.main.async {
            selectedRecordingForPlayback = recording
            print("🔍 Selected recording: \(recording.id.uuidString)")
        }
    }
    
    // Function to load recordings from filesystem
    private func loadRecordingsFromFilesystem() {
        guard let voiceMemosURL = audioManager.getVoiceMemosDirectoryURL() else {
            displayableRecordings = []
            return
        }
        
        print("📂 Looking for recordings in: \(voiceMemosURL.path)")
        
        var foundRecordings: [DisplayableRecording] = []
        let fileManager = FileManager.default
        var modified = false
        
        do {
            let folderURLs = try fileManager.contentsOfDirectory(at: voiceMemosURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
            
            print("🔍 Found \(folderURLs.count) folders")
            
            for folderURL in folderURLs {
                // Make sure it's a directory and its name is a valid UUID
                let resourceValues = try? folderURL.resourceValues(forKeys: [.isDirectoryKey])
                guard resourceValues?.isDirectory == true else { continue }
                
                guard let recordingId = UUID(uuidString: folderURL.lastPathComponent) else {
                    print("⚠️ Folder with invalid name: \(folderURL.lastPathComponent)")
                    continue
                }
                
                // Check if an audio file exists
                let audioFileURL = folderURL.appendingPathComponent("audio.m4a")
                guard fileManager.fileExists(atPath: audioFileURL.path) else {
                    print("⚠️ audio.m4a not found in: \(folderURL.path)")
                    continue
                }
                
                // Try to find metadata in SwiftData
                if let existingData = allRecordingsData.first(where: { $0.id == recordingId }) {
                    // Verify if the URL stored in SwiftData is correct
                    if existingData.fileURL?.path != audioFileURL.path {
                        print("🔄 Correcting path in SwiftData for \(recordingId)")
                        print("   - Old: \(existingData.fileURL?.path ?? "nil")")
                        print("   - New: \(audioFileURL.path)")
                        
                        // Update the path in SwiftData
                        existingData.fileURL = audioFileURL
                        modified = true
                    }
                    
                    // Check if a transcription file exists
                    let transcriptionFileURL = folderURL.appendingPathComponent("transcription.txt")
                    if fileManager.fileExists(atPath: transcriptionFileURL.path) {
                        do {
                            // If there is transcription in file but not in SwiftData or it's different
                            let transcriptionText = try String(contentsOf: transcriptionFileURL, encoding: .utf8)
                            if existingData.transcription != transcriptionText {
                                print("🔄 Updating transcription for recording: \(recordingId)")
                                existingData.transcription = transcriptionText
                                modified = true
                            }
                        } catch {
                            print("⚠️ Error reading transcription for \(recordingId): \(error)")
                        }
                    } else if existingData.transcription != nil {
                        // If there's no file but there is transcription in SwiftData
                        // In this case, we clear the transcription in SwiftData to maintain consistency
                        print("🧹 Removing transcription without file for: \(recordingId)")
                        existingData.transcription = nil
                        modified = true
                    }
                    
                    if let displayable = DisplayableRecording(from: existingData) {
                        // Use data from SwiftData
                        foundRecordings.append(displayable)
                    }
                } else {
                    // If there's no data in SwiftData, create from filesystem
                    if let displayable = DisplayableRecording(id: recordingId, folderURL: folderURL) {
                        foundRecordings.append(displayable)
                        
                        print("➕ Creating new record in SwiftData for \(recordingId)")
                        // Create entry in SwiftData with possible transcription
                        let newRecordingData = AudioRecording(
                            id: recordingId,
                            title: displayable.title,
                            timestamp: displayable.timestamp,
                            duration: displayable.duration,
                            fileURL: displayable.fileURL,
                            transcription: displayable.transcription,  // Include transcription if it exists
                            analysis: displayable.analysis  // Include analysis if it exists
                        )
                        modelContext.insert(newRecordingData)
                        modified = true
                    }
                }
            }
            
            // Try to save changes to SwiftData
            if modelContext.hasChanges {
                do {
                    try modelContext.save()
                    print("✅ Changes saved to SwiftData")
                } catch {
                    print("❌ Error saving changes to SwiftData: \(error)")
                }
            }
            
        } catch {
            print("❌ Error reading Hera directory: \(error)")
        }
        
        // Sort by date (most recent first)
        foundRecordings.sort { $0.timestamp > $1.timestamp }
        
        // Update state
        displayableRecordings = foundRecordings
        
        print("📊 Total recordings loaded: \(foundRecordings.count)")
        
        // Optional cleanup: Remove SwiftData entries that don't have a corresponding folder
        cleanupOrphanedSwiftDataEntries(filesystemIds: Set(foundRecordings.map { $0.id }))
        
        if modified {
            loadRecordingsFromFilesystem()
        }
        
        // After updating displayableRecordings
        if !searchText.isEmpty {
            filterRecordings()
        }
    }
    
    // Function to delete recordings
    private func deleteRecordingsFromFilesystem(offsets: IndexSet) {
        withAnimation {
            let idsToDelete = offsets.map { displayableRecordings[$0].id }
            let foldersToDelete = offsets.map { displayableRecordings[$0].folderURL }
            
            for folderURL in foldersToDelete {
                do {
                    if FileManager.default.fileExists(atPath: folderURL.path) {
                        try FileManager.default.removeItem(at: folderURL)
                        print("Deleted folder: \(folderURL.lastPathComponent)")
                    }
                } catch {
                    print("Error deleting folder \(folderURL.lastPathComponent): \(error)")
                }
            }
            
            // Also delete from SwiftData
            let fetchDescriptor = FetchDescriptor<AudioRecording>(predicate: #Predicate { idsToDelete.contains($0.id) })
            do {
                let dataToDelete = try modelContext.fetch(fetchDescriptor)
                for item in dataToDelete {
                    modelContext.delete(item)
                }
                try modelContext.save()
            } catch {
                 print("Error deleting from SwiftData: \(error)")
            }
            
            // Update UI list
            displayableRecordings.remove(atOffsets: offsets)
        }
    }
    
    // Optional function to clean up SwiftData
    private func cleanupOrphanedSwiftDataEntries(filesystemIds: Set<UUID>) {
        let dataIds = Set(allRecordingsData.map { $0.id })
        let orphanedIds = dataIds.subtracting(filesystemIds)
        
        if !orphanedIds.isEmpty {
            print("Removing orphaned entries from SwiftData: \(orphanedIds)")
            let fetchDescriptor = FetchDescriptor<AudioRecording>(predicate: #Predicate { orphanedIds.contains($0.id) })
            do {
                let dataToDelete = try modelContext.fetch(fetchDescriptor)
                for item in dataToDelete {
                    modelContext.delete(item)
                }
                try modelContext.save()
            } catch {
                 print("Error cleaning SwiftData: \(error)")
            }
        }
    }
    
    // Function to import audio files
    private func importAudioFile(from sourceURL: URL) {
        // Create a unique ID for this imported recording
        let recordingId = UUID()
        
        // Create the directory for the imported recording
        guard let recordingDirectory = audioManager.createRecordingDirectory(for: recordingId) else {
            print("Error: Could not create directory for imported recording")
            return
        }
        
        // Name destination file as audio.m4a to follow convention
        let destinationURL = recordingDirectory.appendingPathComponent("audio.m4a")
        
        do {
            // If a file with that name already exists, delete it first
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            // Copy the file to the specific directory of this recording
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            
            // Get audio duration
            let asset = AVURLAsset(url: destinationURL)
            
            // Use Task for handling asynchronous operations
            Task {
                var duration: TimeInterval = 0
                
                do {
                    let durationValue = try await asset.load(.duration)
                    duration = CMTimeGetSeconds(durationValue)
                } catch {
                    print("Error getting duration: \(error)")
                }
                
                // Create a readable name for the recording
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
                dateFormatter.locale = Locale(identifier: "es_ES")
                let title = "Imported at \(dateFormatter.string(from: Date()))"
                
                // Create and save the new AudioRecording object
                DispatchQueue.main.async {
                    let newRecording = AudioRecording(
                        id: recordingId,
                        title: title,
                        timestamp: Date(),
                        duration: duration,
                        fileURL: destinationURL
                    )
                    
                    modelContext.insert(newRecording)
                    try? modelContext.save()
                    
                    // Reload the list to show the new file
                    loadRecordingsFromFilesystem()
                }
            }
            
        } catch {
            print("Error importing audio file: \(error)")
        }
    }
    
    // Function to format relative date
    private func formatRelativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            return dateFormatter.string(from: date)
        }
    }
    
    // MARK: - Debug Functions
    
    // Functions for debugging and development
    private func debugRun() {
        print("🔍 Executing debug function...")
        // Add any debug code here if needed
    }
    
    private func verifyFilesystem() {
        print("🔍 Verifying file system...")
        audioManager.verifyAndRepairDirectoryStructure()
        audioManager.listAndVerifyRecordings()
    }
    
    // Filter recordings based on search text
    private func filterRecordings() {
        if searchText.isEmpty {
            filteredRecordings = displayableRecordings
        } else {
            filteredRecordings = displayableRecordings.filter { recording in
                recording.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

// Nueva celda para DisplayableRecording
struct DisplayableRecordingCell: View {
    let recording: DisplayableRecording
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.headline)
                    .foregroundColor(AppColors.adaptiveText)
                
                HStack {
                    Text(formatRelativeDate(recording.timestamp))
                        .font(.caption)
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .secondary)
                    Text("•").font(.caption).foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .secondary)
                    Text(formatDuration(recording.duration))
                        .font(.caption)
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(colorScheme == .dark ? Color("CardBackground") : .white)
        .cornerRadius(12)
    }

    // Formatting functions
    private func formatRelativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            return dateFormatter.string(from: date)
        }
    }
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// Vista de opciones de importación
struct ImportOptionsView: View {
    var modelContext: ModelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isImportingFromFiles = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Fondo general más claro en modo oscuro
                colorScheme == .dark ? Color("ListBackground") : Color(UIColor.systemGroupedBackground)
                
                List {
                    Button {
                        isImportingFromFiles = true
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                                .font(.title2)
                                .foregroundColor(AppColors.adaptiveText)
                                .frame(width: 30)
                            
                            Text("Import from Files")
                                .foregroundColor(.primary)
                        }
                    }
                    .listRowBackground(colorScheme == .dark ? Color("ListBackground") : Color(UIColor.systemBackground))
                }
                .scrollIndicators(.hidden)
                .background(Color.clear)
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Import Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.adaptiveText)
                }
            }
        }
        .onDisappear {
            if isImportingFromFiles {
                // Usamos un pequeño delay para asegurar que la vista se ha cerrado
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(name: .importAudio, object: nil)
                }
            }
        }
        .tint(AppColors.adaptiveTint)
    }
}

// Extensión para notificaciones personalizadas
extension Notification.Name {
    static let importAudio = Notification.Name("importAudio")
}

// Vista de configuración de API keys
struct APISettingsView: View {
    @AppStorage("openai_api_key") private var openAIKey = ""
    @AppStorage("gemini_api_key") private var geminiKey = ""
    @AppStorage("anthropic_api_key") private var anthropicKey = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // Valores originales para restaurar si se cierra sin guardar
    @State private var originalOpenAIKey = ""
    @State private var originalGeminiKey = ""
    @State private var originalAnthropicKey = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Fondo general más claro en modo oscuro
                colorScheme == .dark ? Color("ListBackground") : Color(UIColor.systemGroupedBackground)
                
                Form {
                    Section(header: Text("OpenAI API Key")) {
                        SecureField("API Key", text: $openAIKey)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    // Explicación
                    Section(header: Text("Information")) {
                        Text("An API key is required for transcription and analysis features. You can get one from [openai.com](https://platform.openai.com/account/api-keys)")
                            .font(.footnote)
                    }
                }
                .scrollIndicators(.hidden)
                .background(Color.clear)
            }
            .navigationTitle("API Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Save") {
                        // Keys are automatically saved with @AppStorage
                        dismiss()
                    }
                    .foregroundColor(AppColors.adaptiveText)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        // Restore original values before closing
                        openAIKey = originalOpenAIKey
                        geminiKey = originalGeminiKey
                        anthropicKey = originalAnthropicKey
                        dismiss()
                    }
                    .foregroundColor(AppColors.adaptiveText)
                }
            }
            .onAppear {
                // Save the original values when the view appears
                originalOpenAIKey = openAIKey
                originalGeminiKey = geminiKey
                originalAnthropicKey = anthropicKey
            }
        }
        .tint(AppColors.adaptiveTint)
    }
}

// Notes list view
struct NotesListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var analyzedNotes: [AnalyzedNote] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var selectedNote: AnalyzedNote? = nil
    @State private var showDetailView = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()
                
                VStack {
                    if isLoading {
                        ProgressView("Cargando notas...")
                            .padding()
                    } else if analyzedNotes.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "note.text")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            
                            Text("No hay notas")
                                .font(.title2)
                                .foregroundColor(.gray)
                            
                            Text("Las notas aparecerán aquí después de procesar tus grabaciones")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(analyzedNotes) { note in
                                    NoteCell(note: note)
                                        .contentShape(Rectangle())
                                        .shadow(color: Color.black.opacity(0.12),
                                                radius: 3, x: 0, y: 2)
                                        .padding(.horizontal)
                                        .padding(.vertical, 2)
                                        .onTapGesture {
                                            print("🔍 Nota seleccionada: \(note.title)")
                                            selectedNote = note
                                            showDetailView = true
                                        }
                                }
                            }
                            .padding(.vertical)
                        }
                        .searchable(text: $searchText, prompt: "Search notes")
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .navigationTitle("My Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.adaptiveText)
                }
            }
            .onAppear {
                loadNotes()
            }
            .onChange(of: searchText) { newValue in
                // Filter notes when search text changes
                filterNotes()
            }
            .fullScreenCover(item: $selectedNote) { note in
                NavigationStack {
                    NoteDetailView(note: note)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Cerrar") {
                                    selectedNote = nil
                                }
                            }
                            ToolbarItem(placement: .principal) {
                                Text("Nota")
                                    .font(.headline)
                            }
                        }
                }
                .accentColor(AppColors.adaptiveTint)
            }
        }
        .tint(AppColors.adaptiveTint)
    }
    
    // Filter notes based on search text
    private func filterNotes() {
        DispatchQueue.global(qos: .userInitiated).async {
            let notes = loadNotesFromFilesystem()
            
            // Filter by search term if it exists
            let filteredNotes = searchText.isEmpty ? notes : notes.filter { 
                $0.title.localizedCaseInsensitiveContains(searchText) || 
                $0.summary.localizedCaseInsensitiveContains(searchText) ||
                $0.suggestedTitle.localizedCaseInsensitiveContains(searchText)
            }
            
            // Sort by date, most recent first
            let sortedNotes = filteredNotes.sorted { $0.created > $1.created }
            
            DispatchQueue.main.async {
                self.analyzedNotes = sortedNotes
            }
        }
    }
    
    // Load notes
    private func loadNotes() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let notes = loadNotesFromFilesystem()
            
            // Filter by search term if it exists
            let filteredNotes = searchText.isEmpty ? notes : notes.filter { 
                $0.title.localizedCaseInsensitiveContains(searchText) || 
                $0.summary.localizedCaseInsensitiveContains(searchText) ||
                $0.suggestedTitle.localizedCaseInsensitiveContains(searchText)
            }
            
            // Sort by date, most recent first
            let sortedNotes = filteredNotes.sorted { $0.created > $1.created }
            
            DispatchQueue.main.async {
                self.analyzedNotes = sortedNotes
                self.isLoading = false
            }
        }
    }
    
    // Format date
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // Function to load notes from filesystem
    private func loadNotesFromFilesystem() -> [AnalyzedNote] {
        var notes: [AnalyzedNote] = []
        
        // Get documents directory
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ Could not access documents directory")
            return []
        }
        
        // Build path to Hera/VoiceNotes
        let heraDirectory = documentsDirectory.appendingPathComponent("Hera", isDirectory: true)
        let voiceNotesDirectory = heraDirectory.appendingPathComponent("VoiceNotes", isDirectory: true)
        
        // Verify if directory exists
        guard FileManager.default.fileExists(atPath: voiceNotesDirectory.path) else {
            print("❌ VoiceNotes directory does not exist: \(voiceNotesDirectory.path)")
            return []
        }
        
        print("📁 Loading notes from: \(voiceNotesDirectory.path)")
        
        do {
            // Get all folders in the VoiceNotes directory
            let folderURLs = try FileManager.default.contentsOfDirectory(at: voiceNotesDirectory, includingPropertiesForKeys: nil)
            
            print("📁 Found \(folderURLs.count) folders in VoiceNotes")
            
            for folderURL in folderURLs {
                // Extract file metadata to get date
                let attributes = try FileManager.default.attributesOfItem(atPath: folderURL.path)
                let creationDate = attributes[.creationDate] as? Date ?? Date()
                
                // For each folder, check if analysis.json file exists
                let analysisURL = folderURL.appendingPathComponent("analysis.json")
                
                if FileManager.default.fileExists(atPath: analysisURL.path) {
                    print("📄 Procesando archivo: \(analysisURL.lastPathComponent) en \(folderURL.lastPathComponent)")
                    
                    do {
                        // Read file content
                        let analysisData = try Data(contentsOf: analysisURL)
                        let rawContent = String(data: analysisData, encoding: .utf8) ?? ""
                        
                        print("📄 Tamaño del archivo: \(analysisData.count) bytes")
                        
                        // Crear una nota única para cada archivo
                        let noteId = UUID()
                        
                        // Crear nota con los datos básicos
                        let note = AnalyzedNote(
                            id: noteId,
                            title: "Nota \(folderURL.lastPathComponent)",
                            summary: rawContent,
                            folderURL: folderURL,
                            created: creationDate,
                            suggestedTitle: "🔍 Transcripción"
                        )
                        
                        notes.append(note)
                        
                    } catch {
                        print("❌ Error reading analysis.json file: \(error)")
                    }
                } else {
                    // Look for transcript.txt as a fallback
                    let transcriptURL = folderURL.appendingPathComponent("transcript.txt")
                    if FileManager.default.fileExists(atPath: transcriptURL.path) {
                        do {
                            let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)
                            if !transcript.isEmpty {
                                let note = AnalyzedNote(
                                    id: UUID(),
                                    title: "Transcript " + folderURL.lastPathComponent,
                                    summary: transcript,
                                    folderURL: folderURL,
                                    created: creationDate,
                                    suggestedTitle: "Transcripción"
                                )
                                
                                notes.append(note)
                            }
                        } catch {
                            print("❌ Error reading transcript.txt: \(error)")
                        }
                    }
                }
            }
        } catch {
            print("❌ Error listing folders: \(error)")
        }
        
        print("📊 Total notes loaded: \(notes.count)")
        return notes
    }
}

// Note detail view - SIMPLIFICADA PARA EVITAR ERRORES
struct NoteDetailView: View {
    let note: AnalyzedNote
    @Environment(\.colorScheme) private var colorScheme
    @State private var showCopiedMessage: Bool = false
    
    // Procesamiento del contenido para garantizar que se muestre correctamente
    private var cleanedContent: String {
        // Si es JSON, intentar extraer solo el texto relevante
        if note.summary.starts(with: "{") {
            do {
                // Intentar parsear como JSON para extraer contenido
                if let jsonData = note.summary.data(using: .utf8),
                   let jsonObj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    
                    // Intentar extraer primero de "summary" si existe
                    if let summary = jsonObj["summary"] as? String {
                        return summary
                    }
                    
                    // Luego intentar desde choices (formato OpenAI)
                    if let choices = jsonObj["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        return content
                    }
                }
            } catch {
                print("Error al procesar JSON del contenido: \(error)")
            }
        }
        
        // Si no se pudo procesar como JSON o no es JSON, devolver el contenido original
        return note.summary
    }
    
    // Convertir el resumen a formato markdown
    private var markdownContent: String {
        var markdown = """
        # \(note.title)
        
        """
        
        // Añadir título sugerido si existe y es diferente
        if !note.suggestedTitle.isEmpty && note.suggestedTitle != note.title {
            markdown += """
            > **Título sugerido:** \(note.suggestedTitle)
            
            """
        }
        
        // Añadir el contenido del resumen (limpio)
        markdown += cleanedContent
        
        // Añadir metadatos al final
        markdown += """
        
        ---
        Fecha: \(formatDate(note.created))
        """
        
        return markdown
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title with icon
                HStack {
                    Image(systemName: "doc.text")
                        .font(.title)
                        .foregroundColor(.blue)
                    
                    Text(note.suggestedTitle.isEmpty ? note.title : note.suggestedTitle)
                        .font(.title)
                        .bold()
                }
                .padding(.top)
                
                // Original title (if showing suggested title)
                if !note.suggestedTitle.isEmpty && note.suggestedTitle != note.title {
                    HStack {
                        Image(systemName: "character.book.closed")
                            .foregroundColor(.green)
                        
                        Text(note.title)
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    .padding(.top, 4)
                }
                
                // Date
                Text("Fecha: \(formatDate(note.created))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Divider()
                    .padding(.vertical, 8)
                
                // Warning if empty
                if cleanedContent.isEmpty {
                    Text("No hay contenido disponible para esta nota")
                        .font(.headline)
                        .foregroundColor(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    // Content with improved visibility
                    Text(cleanedContent)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colorScheme == .dark ? Color.black : Color.white)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(colorScheme == .dark ? Color.gray : Color.gray.opacity(0.5), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                        .textSelection(.enabled)
                    
                    // Botón para copiar al portapapeles
                    Button(action: {
                        UIPasteboard.general.string = markdownContent
                        
                        withAnimation {
                            showCopiedMessage = true
                        }
                        
                        // Ocultar el mensaje después de 2 segundos
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showCopiedMessage = false
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copiar al portapapeles")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.1))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 16)
                    .overlay(
                        Text("¡Copiado!")
                            .font(.caption)
                            .padding(6)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                            .offset(y: -30)
                            .opacity(showCopiedMessage ? 1 : 0)
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Detalle de Nota")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            print("📝 NoteDetailView apareció")
            print("📝 Título: \(note.title)")
            print("📝 Título sugerido: \(note.suggestedTitle)")
            print("📝 ID: \(note.id)")
            print("📝 Longitud: \(note.summary.count)")
            print("📝 Primeros 50 caracteres: \(note.summary.prefix(50))")
            
            // Extra debug for content
            if note.summary.isEmpty {
                print("⚠️ ALERTA: El contenido de la nota está vacío")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Model for analyzed notes
struct AnalyzedNote: Identifiable {
    let id: UUID
    let title: String
    let summary: String
    let folderURL: URL
    let created: Date
    let suggestedTitle: String // Título sugerido para mostrar en la vista de detalle
    
    // Inicializador con valores por defecto para evitar valores nulos
    init(id: UUID = UUID(), 
         title: String = "Nota sin título", 
         summary: String = "", 
         folderURL: URL, 
         created: Date = Date(),
         suggestedTitle: String = "") {
        self.id = id
        self.title = title.isEmpty ? "Nota sin título" : title
        self.summary = summary
        self.folderURL = folderURL
        self.created = created
        self.suggestedTitle = suggestedTitle.isEmpty ? title : suggestedTitle
    }
    
    // Método para verificar la validez de la nota
    func isValid() -> Bool {
        return !summary.isEmpty
    }
    
    // Añadir método para depuración
    func debugDescription() -> String {
        return """
        ID: \(id)
        Title: \(title)
        Suggested Title: \(suggestedTitle)
        Summary length: \(summary.count)
        First 100 chars: '\(summary.prefix(100))'
        Folder: \(folderURL.lastPathComponent)
        Created: \(created)
        """
    }
}

// Custom search bar component
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                .padding(.leading, 8)
            
            TextField(placeholder, text: $text)
                .padding(7)
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .primary)
                .disableAutocorrection(true)
                .autocapitalization(.none)
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                        .padding(.trailing, 8)
                }
            }
        }
        .background(colorScheme == .dark ? Color.black.opacity(0.2) : Color(.systemGray6))
        .cornerRadius(10)
    }
}

// Cell to display a note
struct NoteCell: View {
    let note: AnalyzedNote
    @Environment(\.colorScheme) private var colorScheme
    
    // Extraer título real a mostrar
    private var displayTitle: String {
        if !note.suggestedTitle.isEmpty {
            return note.suggestedTitle
        }
        return note.title
    }
    
    // Extraer resumen limpio
    private var displaySummary: String {
        // Si es JSON, intentar extraer solo el texto relevante
        if note.summary.starts(with: "{") {
            do {
                // Intentar parsear como JSON para extraer contenido
                if let jsonData = note.summary.data(using: .utf8),
                   let jsonObj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    
                    // Intentar extraer primero de "summary" si existe
                    if let summary = jsonObj["summary"] as? String {
                        return summary
                    }
                    
                    // Luego intentar desde choices (formato OpenAI)
                    if let choices = jsonObj["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        return content
                    }
                }
            } catch {
                // Si hay error al procesar, no hacer nada y usar el fallback
            }
        }
        
        // Si no se pudo procesar como JSON, devolver el contenido original
        return note.summary
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Título principal
            Text(displayTitle)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(1)
                .padding(.bottom, 2)
            
            // Fecha
            Text(formatDate(note.created))
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Divider and summary
            if !displaySummary.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                
                // Mostrar resumen
                Text(displaySummary.prefix(150) + (displaySummary.count > 150 ? "..." : ""))
                    .font(.caption)
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.8))
                    .lineLimit(3)
                    .padding(.top, 2)
            }
            
            // Chevron
            HStack {
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color("CardBackground") : .white)
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
    
    // Format date
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    do {
        let modelContainer = try ModelContainer(for: AudioRecording.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ContentView()
            .modelContainer(modelContainer)
    } catch {
        return Text("Error creating ModelContainer: \(error.localizedDescription)")
    }
}
