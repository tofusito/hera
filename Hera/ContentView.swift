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
    
    @State private var playbackViewKey = UUID() // Añadir una clave única y estable para el PlaybackViewWrapper
    
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
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(displayableRecordings) { recording in
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
    
    @ViewBuilder
    private func bottomBarView() -> some View {
        VStack {
            Spacer()
            
            HStack {
                // Icono de lista de notas (izquierda) con sombra
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
                
                // Botón central de grabación (con sombra)
                Button {
                    isShowingRecordView = true
                } label: {
                    ZStack {
                        // Material de fondo con efecto de vidrio
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 74, height: 74)
                        
                        // Círculo principal con borde suave
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
                    .offset(y: -2) // Elevarlo ligeramente para dar sensación de relieve
                }
                
                Spacer()
                
                // Icono de configuración (derecha) con sombra
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
    
    // MARK: - Vista de reproducción
    @ViewBuilder
    private func playbackSheetView(for recording: DisplayableRecording) -> some View {
        NavigationView {
            // Buscar grabación en SwiftData con función separada
            let originalRecording = findOrCreateRecording(from: recording)
            
            // Mostrar vista de reproducción
            PlaybackView(audioManager: audioManager, recording: originalRecording)
                .id(recording.id) // ID fijo para evitar regeneraciones
        }
    }
    
    // MARK: - Funciones auxiliares
    private func findOrCreateRecording(from displayableRecording: DisplayableRecording) -> AudioRecording {
        // Buscar grabación en SwiftData
        let fetchDescriptor = FetchDescriptor<AudioRecording>()
        let allRecordings = (try? modelContext.fetch(fetchDescriptor)) ?? []
        
        // Buscar por ID
        if let found = allRecordings.first(where: { $0.id == displayableRecording.id }) {
            return found
        }
        
        // Si no existe, crear una nueva
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
        // Primero detener cualquier reproducción actual para evitar conflictos
        if audioManager.isPlaying {
            audioManager.stopPlayback()
        }
        
        // Usamos DispatchQueue para evitar cambios de estado durante actualización
        DispatchQueue.main.async {
            selectedRecordingForPlayback = recording
            print("🔍 Seleccionada grabación: \(recording.id.uuidString)")
        }
    }
    
    // Función para cargar grabaciones desde el sistema de archivos
    private func loadRecordingsFromFilesystem() {
        guard let voiceMemosURL = audioManager.getVoiceMemosDirectoryURL() else {
            displayableRecordings = []
            return
        }
        
        print("📂 Buscando grabaciones en: \(voiceMemosURL.path)")
        
        var foundRecordings: [DisplayableRecording] = []
        let fileManager = FileManager.default
        var modified = false
        
        do {
            let folderURLs = try fileManager.contentsOfDirectory(at: voiceMemosURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
            
            print("🔍 Encontradas \(folderURLs.count) carpetas")
            
            for folderURL in folderURLs {
                // Asegurarse de que es un directorio y su nombre es un UUID válido
                let resourceValues = try? folderURL.resourceValues(forKeys: [.isDirectoryKey])
                guard resourceValues?.isDirectory == true else { continue }
                
                guard let recordingId = UUID(uuidString: folderURL.lastPathComponent) else {
                    print("⚠️ Carpeta con nombre no válido: \(folderURL.lastPathComponent)")
                    continue
                }
                
                // Comprobar si existe un archivo de audio
                let audioFileURL = folderURL.appendingPathComponent("audio.m4a")
                guard fileManager.fileExists(atPath: audioFileURL.path) else {
                    print("⚠️ No se encontró audio.m4a en: \(folderURL.path)")
                    continue
                }
                
                // Intentar encontrar metadatos en SwiftData
                if let existingData = allRecordingsData.first(where: { $0.id == recordingId }) {
                    // Verificar si la URL almacenada en SwiftData es correcta
                    if existingData.fileURL?.path != audioFileURL.path {
                        print("🔄 Corrigiendo ruta en SwiftData para \(recordingId)")
                        print("   - Antigua: \(existingData.fileURL?.path ?? "nil")")
                        print("   - Nueva: \(audioFileURL.path)")
                        
                        // Actualizar la ruta en SwiftData
                        existingData.fileURL = audioFileURL
                        modified = true
                    }
                    
                    // Verificar si existe un archivo de transcripción
                    let transcriptionFileURL = folderURL.appendingPathComponent("transcription.txt")
                    if fileManager.fileExists(atPath: transcriptionFileURL.path) {
                        do {
                            // Si hay transcripción en archivo, pero no en SwiftData o es diferente
                            let transcriptionText = try String(contentsOf: transcriptionFileURL, encoding: .utf8)
                            if existingData.transcription != transcriptionText {
                                print("🔄 Actualizando transcripción para grabación: \(recordingId)")
                                existingData.transcription = transcriptionText
                                modified = true
                            }
                        } catch {
                            print("⚠️ Error al leer transcripción para \(recordingId): \(error)")
                        }
                    } else if existingData.transcription != nil {
                        // Si no hay archivo pero hay transcripción en SwiftData
                        // En este caso, limpiamos la transcripción en SwiftData para mantener consistencia
                        print("🧹 Eliminando transcripción sin archivo para: \(recordingId)")
                        existingData.transcription = nil
                        modified = true
                    }
                    
                    if let displayable = DisplayableRecording(from: existingData) {
                        // Usar datos de SwiftData
                        foundRecordings.append(displayable)
                    }
                } else {
                    // Si no hay datos en SwiftData, crear desde el sistema de archivos
                    if let displayable = DisplayableRecording(id: recordingId, folderURL: folderURL) {
                        foundRecordings.append(displayable)
                        
                        print("➕ Creando nuevo registro en SwiftData para \(recordingId)")
                        // Crear entrada en SwiftData con posible transcripción
                        let newRecordingData = AudioRecording(
                            id: recordingId,
                            title: displayable.title,
                            timestamp: displayable.timestamp,
                            duration: displayable.duration,
                            fileURL: displayable.fileURL,
                            transcription: displayable.transcription,  // Incluir transcripción si existe
                            analysis: displayable.analysis  // Incluir análisis si existe
                        )
                        modelContext.insert(newRecordingData)
                        modified = true
                    }
                }
            }
            
            // Intentar guardar cambios en SwiftData
            if modelContext.hasChanges {
                do {
                    try modelContext.save()
                    print("✅ Cambios guardados en SwiftData")
                } catch {
                    print("❌ Error al guardar cambios en SwiftData: \(error)")
                }
            }
            
        } catch {
            print("❌ Error al leer el directorio Hera: \(error)")
        }
        
        // Ordenar por fecha (más reciente primero)
        foundRecordings.sort { $0.timestamp > $1.timestamp }
        
        // Actualizar el estado
        displayableRecordings = foundRecordings
        
        print("📊 Total grabaciones cargadas: \(foundRecordings.count)")
        
        // Limpieza opcional: Eliminar entradas de SwiftData que no tienen carpeta correspondiente
        cleanupOrphanedSwiftDataEntries(filesystemIds: Set(foundRecordings.map { $0.id }))
        
        if modified {
            loadRecordingsFromFilesystem()
        }
    }
    
    // Función para eliminar grabaciones
    private func deleteRecordingsFromFilesystem(offsets: IndexSet) {
        withAnimation {
            let idsToDelete = offsets.map { displayableRecordings[$0].id }
            let foldersToDelete = offsets.map { displayableRecordings[$0].folderURL }
            
            for folderURL in foldersToDelete {
                do {
                    if FileManager.default.fileExists(atPath: folderURL.path) {
                        try FileManager.default.removeItem(at: folderURL)
                        print("Eliminada carpeta: \(folderURL.lastPathComponent)")
                    }
                } catch {
                    print("Error al eliminar carpeta \(folderURL.lastPathComponent): \(error)")
                }
            }
            
            // Eliminar de SwiftData también
            let fetchDescriptor = FetchDescriptor<AudioRecording>(predicate: #Predicate { idsToDelete.contains($0.id) })
            do {
                let dataToDelete = try modelContext.fetch(fetchDescriptor)
                for item in dataToDelete {
                    modelContext.delete(item)
                }
                try modelContext.save()
            } catch {
                 print("Error eliminando de SwiftData: \(error)")
            }
            
            // Actualizar la lista UI
            displayableRecordings.remove(atOffsets: offsets)
        }
    }
    
    // Función opcional para limpiar SwiftData
    private func cleanupOrphanedSwiftDataEntries(filesystemIds: Set<UUID>) {
        let dataIds = Set(allRecordingsData.map { $0.id })
        let orphanedIds = dataIds.subtracting(filesystemIds)
        
        if !orphanedIds.isEmpty {
            print("Eliminando entradas huérfanas de SwiftData: \(orphanedIds)")
            let fetchDescriptor = FetchDescriptor<AudioRecording>(predicate: #Predicate { orphanedIds.contains($0.id) })
            do {
                let dataToDelete = try modelContext.fetch(fetchDescriptor)
                for item in dataToDelete {
                    modelContext.delete(item)
                }
                try modelContext.save()
            } catch {
                 print("Error limpiando SwiftData: \(error)")
            }
        }
    }
    
    // Función para importar archivos de audio
    private func importAudioFile(from sourceURL: URL) {
        // Crear un ID único para esta grabación importada
        let recordingId = UUID()
        
        // Crear el directorio para la grabación importada
        guard let recordingDirectory = audioManager.createRecordingDirectory(for: recordingId) else {
            print("Error: No se pudo crear directorio para grabación importada")
            return
        }
        
        // Nombrar archivo de destino como audio.m4a para seguir la convención
        let destinationURL = recordingDirectory.appendingPathComponent("audio.m4a")
        
        do {
            // Si ya existe un archivo con ese nombre, eliminarlo primero
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            // Copiar el archivo al directorio específico de esta grabación
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            
            // Obtener duración del audio
            let asset = AVURLAsset(url: destinationURL)
            
            // Usar Task para manejar operaciones asíncronas
            Task {
                var duration: TimeInterval = 0
                
                do {
                    let durationValue = try await asset.load(.duration)
                    duration = CMTimeGetSeconds(durationValue)
                } catch {
                    print("Error al obtener la duración: \(error)")
                }
                
                // Crear un nombre legible para la grabación
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
                dateFormatter.locale = Locale(identifier: "es_ES")
                let title = "Imported at \(dateFormatter.string(from: Date()))"
                
                // Crear y guardar el nuevo objeto AudioRecording
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
                    
                    // Recargar la lista para mostrar el nuevo archivo
                    loadRecordingsFromFilesystem()
                }
            }
            
        } catch {
            print("Error al importar el archivo de audio: \(error)")
        }
    }
    
    // Función para formatear fecha relativa
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

    // Funciones de formato
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
                        // Las claves se guardan automáticamente con @AppStorage
                        dismiss()
                    }
                    .foregroundColor(AppColors.adaptiveText)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        // Restaurar valores originales antes de cerrar
                        openAIKey = originalOpenAIKey
                        geminiKey = originalGeminiKey
                        anthropicKey = originalAnthropicKey
                        dismiss()
                    }
                    .foregroundColor(AppColors.adaptiveText)
                }
            }
            .onAppear {
                // Guardar los valores originales al aparecer la vista
                originalOpenAIKey = openAIKey
                originalGeminiKey = geminiKey
                originalAnthropicKey = anthropicKey
            }
        }
        .tint(AppColors.adaptiveTint)
    }
}

// Vista de lista de notas
struct NotesListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Fondo general más claro en modo oscuro
                colorScheme == .dark ? Color("ListBackground") : Color(UIColor.systemGroupedBackground)
                
                List {
                    Text("Here you will see your saved notes")
                        .foregroundColor(.gray)
                        .listRowBackground(colorScheme == .dark ? Color("ListBackground") : Color(UIColor.systemBackground))
                }
                .scrollIndicators(.hidden)
                .background(Color.clear)
                .listStyle(PlainListStyle())
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
        }
        .tint(AppColors.adaptiveTint)
    }
}

#Preview {
    do {
        let modelContainer = try ModelContainer(for: AudioRecording.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ContentView()
            .modelContainer(modelContainer)
    } catch {
        return Text("Error al crear el ModelContainer: \(error.localizedDescription)")
    }
}
