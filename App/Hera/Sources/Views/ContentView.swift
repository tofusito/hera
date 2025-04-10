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
        self.title = "Recording - \(id.uuidString.prefix(4))"
        self.duration = 0 // Se podría cargar desde AVAsset si fuera necesario aquí
        
        // Comprobar si existe el archivo de transcripción
        let transcriptionFileURL = folderURL.appendingPathComponent("transcription.txt")
        if fileManager.fileExists(atPath: transcriptionFileURL.path) {
            do {
                // Leer transcripción desde el archivo
                self.transcription = try String(contentsOf: transcriptionFileURL, encoding: .utf8)
                print("📄 Transcription loaded from file: \(transcriptionFileURL.path)")
            } catch {
                print("⚠️ Could not read transcription file: \(error)")
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
                if let jsonObj = try JSONSerialization.jsonObject(with: analysisData) as? [String: Any],
                   let choices = jsonObj["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    self.analysis = content
                    print("📄 Analysis loaded from file: \(analysisFileURL.path)")
                } else {
                    self.analysis = nil
                }
            } catch {
                print("⚠️ Could not read analysis file: \(error)")
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
    
    // Estados para selección múltiple
    @State private var isSelectionMode = false
    @State private var selectedRecordings = Set<UUID>()
    
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
            // Barra superior con search bar y botón de selección
            HStack {
                // Search bar
                SearchBar(text: $searchText, placeholder: "Search recordings")
                    .padding(.leading)
                
                // Botón de selección
                Button(action: {
                    isSelectionMode.toggle()
                    if !isSelectionMode {
                        selectedRecordings.removeAll()
                    }
                }) {
                    Text(isSelectionMode ? "Cancel" : "Select")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppColors.adaptiveTint)
                }
                .padding(.trailing)
            }
            .padding(.top, 8)
            
            // Si está en modo selección y hay elementos seleccionados, mostrar barra de acciones
            if isSelectionMode && !selectedRecordings.isEmpty {
                HStack {
                    Text("\(selectedRecordings.count) \(selectedRecordings.count == 1 ? "recording" : "recordings")")
                        .font(.subheadline)
                        .foregroundColor(AppColors.adaptiveText)
                    
                    Spacer()
                    
                    Button(action: {
                        deleteSelectedRecordings()
                    }) {
                        Label("Delete", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(colorScheme == .dark ? Color.black.opacity(0.2) : Color.gray.opacity(0.1))
            }
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    let recordingsToShow = searchText.isEmpty ? displayableRecordings : filteredRecordings
                    
                    ForEach(recordingsToShow) { recording in
                        HStack {
                            if isSelectionMode {
                                Button(action: {
                                    toggleSelection(recording.id)
                                }) {
                                    Image(systemName: selectedRecordings.contains(recording.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedRecordings.contains(recording.id) ? AppColors.adaptiveTint : .gray)
                                        .font(.system(size: 20))
                                        .padding(.leading, 4)
                                }
                            }
                            
                            DisplayableRecordingCell(recording: recording)
                                .contentShape(Rectangle())
                                .shadow(color: colorScheme == .dark ?
                                        Color.black.opacity(0.08) :
                                        Color.black.opacity(0.12),
                                        radius: 3, x: 0, y: 2)
                                .onTapGesture {
                                    if isSelectionMode {
                                        toggleSelection(recording.id)
                                    } else {
                                        handleRecordingTap(recording)
                                    }
                                }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 2)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteRecording(recording)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .scrollIndicators(.hidden)
        }
        .onChange(of: searchText) { _, _ in
            filterRecordings()
        }
    }
    
    @ViewBuilder
    private func bottomBarView() -> some View {
        VStack(spacing: 0) {
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
                            .foregroundColor(colorScheme == .dark ? .white : iconColor)
                            .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
                    }
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
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
                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color("OffWhiteBackground").opacity(0.9))
                            .frame(width: 66, height: 66)
                            .overlay(
                                Circle()
                                    .stroke(colorScheme == .dark ? Color.white : Color("OffWhiteBackground"), lineWidth: colorScheme == .dark ? 1.5 : 0.5)
                                    .opacity(colorScheme == .dark ? 0.5 : 0.8)
                            )
                            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                    }
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.2),
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
                            .foregroundColor(colorScheme == .dark ? .white : iconColor)
                            .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
                    }
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                }
                .padding(.trailing, 30)
            }
            .padding(.bottom, 25)
            .padding(.top, 15)
            .background(
                ZStack(alignment: .top) {
                    // Fondo principal con mayor opacidad
                    Rectangle()
                        .fill(.regularMaterial)
                        .opacity(colorScheme == .dark ? 0.8 : 0.9)
                    
                    // Borde superior para mejor separación visual
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1))
                }
                .edgesIgnoringSafeArea(.bottom)
                .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: -2)
            )
        }
        .edgesIgnoringSafeArea(.bottom)
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
            
            // Cargar todos los registros y filtrar por ID
            let fetchDescriptor = FetchDescriptor<AudioRecording>()
            do {
                let allRecordings = try modelContext.fetch(fetchDescriptor)
                let recordingsToDelete = allRecordings.filter { recording in
                    orphanedIds.contains(recording.id)
                }
                
                for item in recordingsToDelete {
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
    
    // Function to toggle the selection of a recording
    private func toggleSelection(_ id: UUID) {
        if selectedRecordings.contains(id) {
            selectedRecordings.remove(id)
        } else {
            selectedRecordings.insert(id)
        }
    }
    
    // Function to delete selected recordings
    private func deleteSelectedRecordings() {
        withAnimation {
            // Get indices of selected recordings
            let indicesToDelete = displayableRecordings.indices.filter { selectedRecordings.contains(displayableRecordings[$0].id) }
            
            if !indicesToDelete.isEmpty {
                let idsToDelete = indicesToDelete.map { displayableRecordings[$0].id }
                let foldersToDelete = indicesToDelete.map { displayableRecordings[$0].folderURL }
                
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
                // Function to check if the ID is in the array
                let fetchDescriptor = FetchDescriptor<AudioRecording>()
                do {
                    let allRecordings = try modelContext.fetch(fetchDescriptor)
                    let recordingsToDelete = allRecordings.filter { recording in 
                        idsToDelete.contains(recording.id)
                    }
                    
                    // Delete records
                    for item in recordingsToDelete {
                        modelContext.delete(item)
                    }
                    try modelContext.save()
                } catch {
                     print("Error deleting from SwiftData: \(error)")
                }
                
                // Update UI list
                // Delete in reverse order to avoid index problems
                for index in indicesToDelete.sorted(by: >) {
                    if index < displayableRecordings.count {
                        displayableRecordings.remove(at: index)
                    }
                }
                
                // Clear selections
                selectedRecordings.removeAll()
                isSelectionMode = false
            }
        }
    }
    
    // Function to delete a single recording
    private func deleteRecording(_ recording: DisplayableRecording) {
        withAnimation {
            if let index = displayableRecordings.firstIndex(where: { $0.id == recording.id }) {
                let folderURL = recording.folderURL
                
                do {
                    if FileManager.default.fileExists(atPath: folderURL.path) {
                        try FileManager.default.removeItem(at: folderURL)
                        print("Deleted folder: \(folderURL.lastPathComponent)")
                    }
                } catch {
                    print("Error deleting folder \(folderURL.lastPathComponent): \(error)")
                }
                
                // También eliminar de SwiftData
                // Cargar todos los registros y filtrar por ID
                let fetchDescriptor = FetchDescriptor<AudioRecording>()
                do {
                    let allRecordings = try modelContext.fetch(fetchDescriptor)
                    // Buscar el registro por ID
                    if let recordingToDelete = allRecordings.first(where: { $0.id == recording.id }) {
                        modelContext.delete(recordingToDelete)
                        try modelContext.save()
                    }
                } catch {
                     print("Error deleting from SwiftData: \(error)")
                }
                
                // Actualizar UI list
                displayableRecordings.remove(at: index)
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
        .background(colorScheme == .dark ? Color("CardBackground") : Color("CardBackground"))
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
    @AppStorage("forced_theme") private var forcedTheme = 0 // 0 = System, 1 = Light, 2 = Dark
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // Valores originales para restaurar si se cierra sin guardar
    @State private var originalOpenAIKey = ""
    @State private var originalGeminiKey = ""
    @State private var originalAnthropicKey = ""
    @State private var originalForcedTheme = 0
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Fondo general más claro en modo oscuro
                colorScheme == .dark ? Color("ListBackground") : Color("OffWhiteBackground")
                
                Form {
                    Section(header: Text("OpenAI API Key")) {
                        SecureField("API Key", text: $openAIKey)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    Section(header: Text("Theme Settings")) {
                        Picker("App Theme", selection: $forcedTheme) {
                            Text("System Default").tag(0)
                            Text("Light Mode").tag(1)
                            Text("Dark Mode").tag(2)
                        }
                        .pickerStyle(.menu)
                    }
                    
                    // Explicación
                    Section(header: Text("Information")) {
                        Text("An API key is required for transcription and analysis features. You can get one from [openai.com](https://platform.openai.com/account/api-keys)")
                            .font(.footnote)
                        
                        Text("Theme changes will take effect when you restart the app.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .scrollIndicators(.hidden)
                .background(Color.clear)
            }
            .navigationTitle("Settings")
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
                        forcedTheme = originalForcedTheme
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
                originalForcedTheme = forcedTheme
            }
        }
        .preferredColorScheme(getPreferredColorScheme())
        .tint(AppColors.adaptiveTint)
    }
    
    private func getPreferredColorScheme() -> ColorScheme? {
        switch forcedTheme {
        case 1:
            return .light
        case 2:
            return .dark
        default:
            return nil // system default
        }
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
    
    // Estados para selección múltiple
    @State private var isSelectionMode = false
    @State private var selectedNotes = Set<UUID>()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()
                
                VStack {
                    if isLoading {
                        ProgressView("Loading notes...")
                            .padding()
                    } else if analyzedNotes.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "note.text")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            
                            Text("No notes")
                                .font(.title2)
                                .foregroundColor(.gray)
                            
                            Text("Notes will appear here after processing your recordings")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding()
                    } else {
                        // Barra superior con search bar y botón de selección
                        HStack {
                            SearchBar(text: $searchText, placeholder: "Search notes")
                                .padding(.leading)
                            
                            Button(action: {
                                isSelectionMode.toggle()
                                if !isSelectionMode {
                                    selectedNotes.removeAll()
                                }
                            }) {
                                Text(isSelectionMode ? "Cancel" : "Select")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppColors.adaptiveTint)
                            }
                            .padding(.trailing)
                        }
                        .padding(.top, 8)
                        
                        // Si está en modo selección y hay elementos seleccionados, mostrar barra de acciones
                        if isSelectionMode && !selectedNotes.isEmpty {
                            HStack {
                                Text("\(selectedNotes.count) \(selectedNotes.count == 1 ? "note" : "notes")")
                                    .font(.subheadline)
                                    .foregroundColor(AppColors.adaptiveText)
                                
                                Spacer()
                                
                                Button(action: {
                                    deleteSelectedNotes()
                                }) {
                                    Label("Delete", systemImage: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(colorScheme == .dark ? Color.black.opacity(0.2) : Color.gray.opacity(0.1))
                        }
                        
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(analyzedNotes) { note in
                                    HStack {
                                        if isSelectionMode {
                                            Button(action: {
                                                toggleSelection(note.id)
                                            }) {
                                                Image(systemName: selectedNotes.contains(note.id) ? "checkmark.circle.fill" : "circle")
                                                    .foregroundColor(selectedNotes.contains(note.id) ? AppColors.adaptiveTint : .gray)
                                                    .font(.system(size: 20))
                                                    .padding(.leading, 4)
                                            }
                                        }
                                        
                                        NoteCell(note: note)
                                            .contentShape(Rectangle())
                                            .shadow(color: Color.black.opacity(0.12),
                                                    radius: 3, x: 0, y: 2)
                                            .onTapGesture {
                                                if isSelectionMode {
                                                    toggleSelection(note.id)
                                                } else {
                                                    print("🔍 Note selected: \(note.title)")
                                                    selectedNote = note
                                                }
                                            }
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 2)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            deleteNote(note)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
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
            .onChange(of: searchText) { _, _ in
                // Filter notes when search text changes
                filterNotes()
            }
            .fullScreenCover(item: $selectedNote) { note in
                NavigationStack {
                    NoteDetailView(note: note)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Close") {
                                    selectedNote = nil
                                }
                            }
                            ToolbarItem(placement: .principal) {
                                Text("Note")
                                    .font(.headline)
                            }
                        }
                }
                .accentColor(AppColors.adaptiveTint)
            }
        }
        .tint(AppColors.adaptiveTint)
    }
    
    // Function to toggle the selection of a note
    private func toggleSelection(_ id: UUID) {
        if selectedNotes.contains(id) {
            selectedNotes.remove(id)
        } else {
            selectedNotes.insert(id)
        }
    }
    
    // Function to delete a single note
    private func deleteNote(_ note: AnalyzedNote) {
        withAnimation {
            if let index = analyzedNotes.firstIndex(where: { $0.id == note.id }) {
                let folderURL = note.folderURL
                if FileManager.default.fileExists(atPath: folderURL.path) {
                    do {
                        try FileManager.default.removeItem(at: folderURL)
                        print("Deleted note folder: \(folderURL.lastPathComponent)")
                    } catch {
                        print("Error deleting note folder \(folderURL.lastPathComponent): \(error)")
                    }
                }
                
                // Update UI list
                analyzedNotes.remove(at: index)
            }
        }
    }
    
    // Function to delete selected notes
    private func deleteSelectedNotes() {
        withAnimation {
            // Get indices of selected notes
            let notesToDelete = analyzedNotes.filter { selectedNotes.contains($0.id) }
            
            for note in notesToDelete {
                let folderURL = note.folderURL
                if FileManager.default.fileExists(atPath: folderURL.path) {
                    do {
                        try FileManager.default.removeItem(at: folderURL)
                        print("Deleted note folder: \(folderURL.lastPathComponent)")
                    } catch {
                        print("Error deleting note folder \(folderURL.lastPathComponent): \(error)")
                    }
                }
            }
            
            // Update UI list
            analyzedNotes.removeAll { selectedNotes.contains($0.id) }
            
            // Clear selections
            selectedNotes.removeAll()
            isSelectionMode = false
        }
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
                    print("📄 Processing file: \(analysisURL.lastPathComponent) in \(folderURL.lastPathComponent)")
                    
                    do {
                        // Read the complete content of the JSON file
                        let analysisData = try Data(contentsOf: analysisURL)
                        let fileContent = String(data: analysisData, encoding: .utf8) ?? ""
                        
                        print("📄 JSON content (first 100 chars): \(fileContent.prefix(100))")
                        
                        // Default title with folder ID
                        let title = "Note \(folderURL.lastPathComponent)"
                        var suggestedTitle = ""
                        var summary = ""

                        // Try to parse the JSON directly
                        do {
                            let jsonObj = try JSONSerialization.jsonObject(with: analysisData) as? [String: Any]
                            
                            if let jsonObj = jsonObj {
                                print("📄 JSON parsed correctly")
                                
                                // 1. Extract suggested title directly from JSON
                                if let extractedTitle = jsonObj["suggestedTitle"] as? String, !extractedTitle.isEmpty {
                                    suggestedTitle = extractedTitle
                                    print("📄 Suggested title found: \(suggestedTitle)")
                                }
                                
                                // 2. Extract summary directly from JSON
                                if let extractedSummary = jsonObj["summary"] as? String, !extractedSummary.isEmpty {
                                    summary = extractedSummary
                                    print("📄 Summary found (first 30 chars): \(summary.prefix(30))")
                                }
                                
                                // 3. If no fields were found directly, search in OpenAI format
                                if (suggestedTitle.isEmpty || summary.isEmpty),
                                   let choices = jsonObj["choices"] as? [[String: Any]],
                                   let firstChoice = choices.first,
                                   let message = firstChoice["message"] as? [String: Any],
                                   let content = message["content"] as? String {
                                    
                                    print("📄 Found content in OpenAI format")
                                    
                                    // If there's no summary, use the content
                                    if summary.isEmpty {
                                        summary = content
                                    }
                                    
                                    // Search for a suggestedTitle in the content if not found
                                    if suggestedTitle.isEmpty {
                                        // Use regular expression to find the suggested title
                                        if let range = content.range(of: "\"suggestedTitle\"\\s*:\\s*\"([^\"]*)\"", options: .regularExpression) {
                                            let extractedText = String(content[range])
                                            if let startQuote = extractedText.range(of: "\":", options: .backwards)?.upperBound,
                                               let endQuote = extractedText.range(of: "\"", options: .backwards)?.lowerBound,
                                               startQuote < endQuote {
                                                suggestedTitle = String(extractedText[startQuote..<endQuote])
                                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                                    .replacingOccurrences(of: "\"", with: "")
                                                print("📄 Suggested title extracted from content: \(suggestedTitle)")
                                            }
                                        } else if let range = content.range(of: "suggestedTitle:\\s*([^\\n]*)", options: .regularExpression) {
                                            let extractedText = String(content[range])
                                            if let colonIndex = extractedText.firstIndex(of: ":") {
                                                let startIndex = extractedText.index(after: colonIndex)
                                                suggestedTitle = String(extractedText[startIndex...])
                                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                                    .replacingOccurrences(of: "\"", with: "")
                                                print("📄 Suggested title extracted from content (alternative format): \(suggestedTitle)")
                                            }
                                        }
                                    }
                                }
                                
                                // If a suggested title still hasn't been found, use a default value
                                if suggestedTitle.isEmpty {
                                    let defaultTitle = jsonObj["suggestedTitle"] as? String
                                    suggestedTitle = defaultTitle != nil && !defaultTitle!.isEmpty ? defaultTitle! : "💬 Transcription"
                                }
                                
                                // Create a note with the extracted data
                                let note = AnalyzedNote(
                                    id: UUID(),
                                    title: title,
                                    summary: fileContent,         // Save complete content to preserve
                                    folderURL: folderURL,
                                    created: creationDate,
                                    suggestedTitle: suggestedTitle,
                                    processedSummary: summary     // Processed summary (if exists)
                                )
                                
                                notes.append(note)
                                continue
                            }
                        } catch {
                            print("⚠️ JSON could not be parsed from analysis.json file")
                            
                            // If JSON could not be parsed, try extracting with regular expressions
                            if let suggestedTitleMatch = fileContent.range(of: "\"suggestedTitle\"\\s*:\\s*\"([^\"]*)\"", options: .regularExpression) {
                                let suggestedTitleText = String(fileContent[suggestedTitleMatch])
                                if let startQuote = suggestedTitleText.range(of: "\":", options: .backwards)?.upperBound,
                                   let endQuote = suggestedTitleText.range(of: "\"", options: .backwards)?.lowerBound,
                                   startQuote < endQuote {
                                    suggestedTitle = String(suggestedTitleText[startQuote..<endQuote])
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                    print("📄 Suggested title extracted with regex: \(suggestedTitle)")
                                }
                            }
                            
                            if let summaryMatch = fileContent.range(of: "\"summary\"\\s*:\\s*\"([^\"]*)\"", options: .regularExpression) {
                                let summaryText = String(fileContent[summaryMatch])
                                if let startQuote = summaryText.range(of: "\":", options: .backwards)?.upperBound,
                                   let endQuote = summaryText.range(of: "\"", options: .backwards)?.lowerBound,
                                   startQuote < endQuote {
                                    summary = String(summaryText[startQuote..<endQuote])
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                    print("📄 Summary extracted with regex (first 30 chars): \(summary.prefix(30))")
                                }
                            }
                            
                            if suggestedTitle.isEmpty {
                                suggestedTitle = "💬 Transcription"
                            }
                            
                            // Create note with extracted data using regex
                            let note = AnalyzedNote(
                                id: UUID(),
                                title: title,
                                summary: fileContent,
                                folderURL: folderURL,
                                created: creationDate,
                                suggestedTitle: suggestedTitle,
                                processedSummary: summary.isEmpty ? nil : summary
                            )
                            
                            notes.append(note)
                            continue
                        }
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
                                    title: "Transcription \(folderURL.lastPathComponent)",
                                    summary: transcript,
                                    folderURL: folderURL,
                                    created: creationDate,
                                    suggestedTitle: "💬 Simple transcription",
                                    processedSummary: transcript // For simple transcriptions, the content is already plain text
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
        
        print("📄 Total notes loaded: \(notes.count)")
        return notes
    }
}

// Note detail view - SIMPLIFIED FOR ERRORS
struct NoteDetailView: View {
    let note: AnalyzedNote
    @Environment(\.colorScheme) private var colorScheme
    @State private var showCopiedMessage: Bool = false
    
    // Extract clean summary for display
    private var displaySummary: String {
        // If it's JSON, try multiple formats
        if note.summary.starts(with: "{") {
            do {
                if let jsonData = note.summary.data(using: .utf8),
                   let jsonObj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    
                    // 1. Try to extract directly from the "summary" field
                    if let summaryValue = jsonObj["summary"] as? String, !summaryValue.isEmpty {
                        return summaryValue
                    }
                    
                    // 2. Search in OpenAI response format
                    if let choices = jsonObj["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        
                        // 2.1 Search for the "summary" field within the content
                        if let range = content.range(of: "\"summary\"\\s*:\\s*\"([^\"]*)\"", options: .regularExpression) {
                            let extractedText = String(content[range])
                            if let startQuote = extractedText.range(of: "\":", options: .backwards)?.upperBound,
                               let endQuote = extractedText.range(of: "\"", options: .backwards)?.lowerBound,
                               startQuote < endQuote {
                                let summary = String(extractedText[startQuote..<endQuote])
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .replacingOccurrences(of: "\"", with: "")
                                if !summary.isEmpty {
                                    return summary
                                }
                            }
                        }
                        
                        // 2.2 If there's no specific summary field, use all content
                        if !content.isEmpty {
                            return content
                        }
                    }
                }
            } catch {
                print("Error processing JSON for summary: \(error)")
            }
            
            // 3. Try to extract with regex if parsing JSON failed
            if let summaryMatch = note.summary.range(of: "\"summary\"\\s*:\\s*\"([^\"]*)\"", options: .regularExpression) {
                let summaryText = String(note.summary[summaryMatch])
                if let startQuote = summaryText.range(of: "\":", options: .backwards)?.upperBound,
                   let endQuote = summaryText.range(of: "\"", options: .backwards)?.lowerBound,
                   startQuote < endQuote {
                    let summary = String(summaryText[startQuote..<endQuote])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !summary.isEmpty {
                        return summary
                    }
                }
            }
        }
        
        // If we couldn't get the summary from JSON, return some alternative content
        if let processed = note.processedSummary, !processed.isEmpty {
            return processed
        }
        
        // If everything else fails, return the complete content
        return note.summary.isEmpty ? "No content could be extracted from summary" : note.summary
    }
    
    // Extract only the ID from the title if it's a UUID
    private var displayOriginalTitle: String {
        // If the title starts with "Note " followed by a UUID, extract just the UUID
        if note.title.starts(with: "Note ") {
            let components = note.title.components(separatedBy: " ")
            if components.count > 1 {
                return "ID: \(components[1].prefix(8))..."
            }
        }
        return note.title
    }
    
    // Convert summary to markdown format
    private var markdownContent: String {
        var markdown = """
        # \(note.suggestedTitle)
        
        """
        
        // Add ID as metadata
        markdown += """
        > ID: \(note.id)
        
        """
        
        // Add the content of the summary (cleaned)
        markdown += displaySummary
        
        // Add metadata at the end
        markdown += """
        
        ---
        Date: \(formatDate(note.created))
        """
        
        return markdown
    }
    
    var body: some View {
        ZStack {
            // General adaptive background
            Color("Background").ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with title
                    VStack(alignment: .leading, spacing: 8) {
                        // Main title (suggestedTitle)
                        HStack {
                            Image(systemName: "doc.text")
                                .font(.title)
                                .foregroundColor(AppColors.adaptiveTint)
                            
                            Text(note.suggestedTitle.isEmpty ? note.title : note.suggestedTitle)
                                .font(.title)
                                .bold()
                                .foregroundColor(AppColors.adaptiveText)
                        }
                        
                        // Featured date
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
                            
                            Text("Date: \(formatDate(note.created))")
                                .font(.subheadline)
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colorScheme == .dark ? Color("CardBackground").opacity(0.6) : Color("CardBackground").opacity(0.9))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.08 : 0.12), radius: 3, x: 0, y: 2)
                    
                    // Original title (if there's a suggested title and it's different)
                    if !note.suggestedTitle.isEmpty && note.suggestedTitle != note.title {
                        HStack {
                            Image(systemName: "character.book.closed")
                                .foregroundColor(colorScheme == .dark ? .green.opacity(0.8) : .green)
                            
                            Text(displayOriginalTitle)
                                .font(.headline)
                                .foregroundColor(colorScheme == .dark ? .green.opacity(0.8) : .green)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Warning if empty
                    if displaySummary.isEmpty {
                        VStack(alignment: .center, spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 36))
                                .foregroundColor(.red.opacity(0.8))
                            
                            Text("No content available for this note")
                                .font(.headline)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05))
                        )
                    } else {
                        // Content card with title
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "text.bubble")
                                    .foregroundColor(AppColors.adaptiveTint)
                                
                                Text("Content")
                                    .font(.headline)
                                    .foregroundColor(AppColors.adaptiveText)
                                
                                Spacer()
                                
                                // Small button to copy
                                Button {
                                    UIPasteboard.general.string = markdownContent
                                    
                                    withAnimation {
                                        showCopiedMessage = true
                                    }
                                    
                                    // Hide message after 2 seconds
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        withAnimation {
                                            showCopiedMessage = false
                                        }
                                    }
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 15))
                                        .foregroundColor(colorScheme == .dark ? .white : Color.blue)
                                        .padding(6)
                                        .background(
                                            Circle()
                                                .fill(colorScheme == .dark ? Color.blue.opacity(0.2) : Color.blue.opacity(0.1))
                                        )
                                }
                            }
                            .padding(.bottom, 4)
                            .overlay(
                                ZStack {
                                    if showCopiedMessage {
                                        Text("Copied!")
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .padding(5)
                                            .background(Color.blue.opacity(0.15))
                                            .cornerRadius(4)
                                            .foregroundColor(.primary)
                                            .offset(x: -40, y: 25)
                                    }
                                }
                            )
                            
                            // Text content of the summary (summary) with Markdown support
                            MarkdownText(markdown: displaySummary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color("CardBackground") : Color("CardBackground"))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(colorScheme == .dark ? Color.gray.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.08 : 0.12), radius: 3, x: 0, y: 2)
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Note Detail")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            print("📝 NoteDetailView appeared")
            print("📝 Title: \(note.title)")
            print("📝 Suggested title: \(note.suggestedTitle)")
            print("📝 ID: \(note.id)")
            print("📝 Length: \(note.summary.count)")
            print("📝 First 50 characters: \(note.summary.prefix(50))")
            
            // Extra debug for content
            if note.summary.isEmpty {
                print("⚠️ ALERT: Note content is empty")
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
    let suggestedTitle: String // Suggested title to display in detail view
    let processedSummary: String? // Optional processed summary
    
    // Inicializador with default values to avoid null values
    init(id: UUID = UUID(), 
         title: String = "Untitled note", 
         summary: String = "", 
         folderURL: URL, 
         created: Date = Date(),
         suggestedTitle: String = "",
         processedSummary: String? = nil) {
        self.id = id
        self.title = title.isEmpty ? "Untitled note" : title
        self.summary = summary
        self.folderURL = folderURL
        self.created = created
        self.suggestedTitle = suggestedTitle.isEmpty ? title : suggestedTitle
        self.processedSummary = processedSummary
    }
    
    // Method to verify the validity of the note
    func isValid() -> Bool {
        return !summary.isEmpty
    }
    
    // Add method for debugging
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
    
    // Extract real title to display
    private var displayTitle: String {
        if !note.suggestedTitle.isEmpty {
            return note.suggestedTitle
        }
        return note.title
    }
    
    // Extract clean summary for display
    private var displaySummary: String {
        // If it's JSON, try multiple formats
        if note.summary.starts(with: "{") {
            do {
                if let jsonData = note.summary.data(using: .utf8),
                   let jsonObj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    
                    // 1. Try to extract directly from the "summary" field
                    if let summaryValue = jsonObj["summary"] as? String, !summaryValue.isEmpty {
                        return summaryValue
                    }
                    
                    // 2. Search in OpenAI response format
                    if let choices = jsonObj["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        
                        // 2.1 Search for the "summary" field within the content
                        if let range = content.range(of: "\"summary\"\\s*:\\s*\"([^\"]*)\"", options: .regularExpression) {
                            let extractedText = String(content[range])
                            if let startQuote = extractedText.range(of: "\":", options: .backwards)?.upperBound,
                               let endQuote = extractedText.range(of: "\"", options: .backwards)?.lowerBound,
                               startQuote < endQuote {
                                let summary = String(extractedText[startQuote..<endQuote])
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .replacingOccurrences(of: "\"", with: "")
                                if !summary.isEmpty {
                                    return summary
                                }
                            }
                        }
                        
                        // 2.2 If there's no specific summary field, use all content
                        if !content.isEmpty {
                            return content
                        }
                    }
                }
            } catch {
                print("Error processing JSON for summary: \(error)")
            }
            
            // 3. Try to extract with regex if parsing JSON failed
            if let summaryMatch = note.summary.range(of: "\"summary\"\\s*:\\s*\"([^\"]*)\"", options: .regularExpression) {
                let summaryText = String(note.summary[summaryMatch])
                if let startQuote = summaryText.range(of: "\":", options: .backwards)?.upperBound,
                   let endQuote = summaryText.range(of: "\"", options: .backwards)?.lowerBound,
                   startQuote < endQuote {
                    let summary = String(summaryText[startQuote..<endQuote])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !summary.isEmpty {
                        return summary
                    }
                }
            }
        }
        
        // If we couldn't get the summary from JSON, return some alternative content
        if let processed = note.processedSummary, !processed.isEmpty {
            return processed
        }
        
        // If everything else fails, return the complete content
        return note.summary.isEmpty ? "No content could be extracted from summary" : note.summary
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main title (suggestedTitle)
            Text(displayTitle)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(1)
                .padding(.bottom, 2)
            
            // Date
            Text(formatDate(note.created))
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Divider and summary preview
            if !displaySummary.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                
                // Show truncated summary, cleaning possible Markdown markers
                let plainText = cleanMarkdownText(displaySummary.prefix(150))
                Text(plainText + (displaySummary.count > 150 ? "..." : ""))
                    .font(.caption)
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.8))
                    .lineLimit(3)
                    .padding(.top, 2)
            }
            
            // Navigation indicator
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
                .fill(colorScheme == .dark ? Color("CardBackground") : Color("CardBackground"))
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
    
    // Function to clean basic Markdown markers for preview
    private func cleanMarkdownText(_ text: String.SubSequence) -> String {
        var result = String(text)
        
        // Remove headers (#)
        result = result.replacingOccurrences(of: #"^\s*#{1,6}\s+"#, with: "", options: .regularExpression, range: nil)
        
        // Remove bold/italic markers
        result = result.replacingOccurrences(of: "[*_]{1,2}", with: "", options: .regularExpression, range: nil)
        
        // Remove code markers
        result = result.replacingOccurrences(of: "`", with: "")
        
        // Remove list markers
        result = result.replacingOccurrences(of: #"^\s*[\-\*\+]\s+"#, with: "• ", options: .regularExpression, range: nil)
        result = result.replacingOccurrences(of: #"^\s*\d+\.\s+"#, with: "• ", options: .regularExpression, range: nil)
        
        // Replace multiple spaces with one space
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression, range: nil)
        
        return result
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

