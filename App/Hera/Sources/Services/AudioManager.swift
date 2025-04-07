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
        // Método dedicado para limpiar temporizadores
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
        // Detener cualquier grabación existente primero
        if isRecording {
            _ = stopRecording()
        }
        
        // Detener cualquier reproducción existente
        if isPlaying {
            stopPlayback()
        }
        
        // Limpiar temporizadores existentes
        cleanupTimers()
        
        let recordingSession = AVAudioSession.sharedInstance()
        
        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default)
            try recordingSession.setActive(true)
            
            let timestamp = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "dd-MM-yyyy HH:mm:ss"
            let dateTimeString = formatter.string(from: timestamp)
            
            // Crear un UUID para esta grabación
            let recordingId = UUID()
            
            // Crear directorio para esta grabación
            guard let recordingDirectory = createRecordingDirectory(for: recordingId) else {
                print("Error: No se pudo crear el directorio para la grabación")
                return
            }
            
            // Guardar el archivo dentro de la carpeta específica
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
            
            // Crear un nuevo objeto AudioRecording
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
            
            // Iniciar temporizador para actualizar la duración con un delay para asegurar que el recorder está listo
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self, self.isRecording else { return }
                
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    guard let self = self, let recorder = self.audioRecorder, self.isRecording else { return }
                    self.recordingTime = recorder.currentTime
                }
                
                // Asegurar que el timer se ejecute en el modo de ejecución común
                RunLoop.current.add(self.timer!, forMode: .common)
                
                // Iniciar temporizador para actualizar el nivel de audio
                self.levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    guard let self = self, let recorder = self.audioRecorder, self.isRecording else { return }
                    
                    recorder.updateMeters()
                    
                    // Obtener el nivel de audio del canal 0
                    let level = recorder.averagePower(forChannel: 0)
                    
                    // Convertir el nivel en dB a un valor normalizado (0-1)
                    // Los valores de dB están típicamente entre -160 y 0
                    let normalizedLevel = max(0.0, min(1.0, (level + 60) / 60))
                    
                    // Actualizar en el hilo principal
                    DispatchQueue.main.async {
                        self.audioLevel = normalizedLevel
                    }
                }
                
                // Asegurar que el levelTimer se ejecute en el modo de ejecución común
                RunLoop.current.add(self.levelTimer!, forMode: .common)
            }
            
        } catch {
            print("Could not start recording: \(error)")
            isRecording = false
            audioLevel = 0.0
        }
    }
    
    func stopRecording() -> AudioRecording? {
        // Verificar si realmente estamos grabando
        guard isRecording, let recorder = audioRecorder else {
            isRecording = false
            audioLevel = 0.0
            cleanupTimers()
            return nil
        }
        
        // Capturar la grabación antes de detener
        let capturedRecording = currentAudioRecording
        let capturedDuration = recordingTime
        
        // Detener grabadora y limpiar
        recorder.stop()
        audioRecorder = nil
        isRecording = false
        
        // Limpiar temporizadores
        cleanupTimers()
        
        // Actualizar la duración y devolver la grabación
        if let recording = capturedRecording {
            // Usar let en lugar de var, y crear una nueva instancia para modificación
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
        // Detener cualquier reproducción existente
        if isPlaying {
            stopPlayback()
        }
        
        // Imprimir la URL para depuración
        print("Intentando reproducir archivo en: \(url.path)")
        
        // Verificar existencia del archivo
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("⚠️ ERROR: El archivo de audio no existe durante startPlayback: \(url.path)")
            DispatchQueue.main.async {
                self.isPlaying = false
            }
            return
        }
        
        let playbackSession = AVAudioSession.sharedInstance()
        
        do {
            try playbackSession.setCategory(.playback, mode: .default)
            try playbackSession.setActive(true)
            
            // Si ya tenemos un reproductor cargado, verificar si es para la misma URL
            if let existingPlayer = audioPlayer, existingPlayer.url == url {
                print("🔄 Usando reproductor existente ya preparado")
                existingPlayer.currentTime = 0
                existingPlayer.play()
                
                DispatchQueue.main.async {
                    self.isPlaying = true
                    print("✅ Reproducción iniciada con reproductor existente")
                }
                return
            }
            
            // Crear un nuevo reproductor
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            guard let player = audioPlayer else {
                print("No se pudo crear el reproductor de audio")
                return
            }
            
            player.delegate = self
            player.prepareToPlay()
            let success = player.play()
            
            if success {
                // Usamos DispatchQueue para actualizar estado después de iniciar reproducción
                DispatchQueue.main.async {
                    self.isPlaying = true
                    print("✅ Reproducción iniciada correctamente")
                }
            } else {
                print("⚠️ El método play() devolvió false - El player está en estado inválido")
                DispatchQueue.main.async {
                    self.isPlaying = false
                }
            }
        } catch {
            print("❌ No se pudo reproducir el audio: \(error)")
            DispatchQueue.main.async {
                self.isPlaying = false
            }
        }
    }
    
    func stopPlayback() {
        // Verificar que realmente hay reproducción activa
        guard isPlaying, let player = audioPlayer else {
            print("⚠️ stopPlayback: No hay reproducción activa que detener")
            DispatchQueue.main.async {
                self.isPlaying = false
            }
            return
        }
        
        print("⏹️ Deteniendo reproducción explícitamente")
        player.stop()
        // Solo liberar recursos si realmente es necesario
        // audioPlayer = nil // Comentado para permitir reutilización
        
        // Usamos DispatchQueue para actualizar estado después de detener reproducción
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }
    
    func prepareToPlay(url: URL, completion: @escaping (Bool, TimeInterval) -> Void) {
        // Detener cualquier reproducción existente
        if isPlaying {
            stopPlayback()
        }
        
        // Imprimir la URL para depuración
        print("Preparando audio en: \(url.path)")
        
        // Verificar existencia del archivo
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("⚠️ ERROR: El archivo de audio no existe durante prepareToPlay: \(url.path)")
            completion(false, 0)
            return
        }
        
        let playbackSession = AVAudioSession.sharedInstance()
        
        do {
            try playbackSession.setCategory(.playback, mode: .default)
            try playbackSession.setActive(true)
            
            let tempPlayer = try AVAudioPlayer(contentsOf: url)
            tempPlayer.prepareToPlay()
            
            // Registrar la duración para uso posterior
            let audioDuration = tempPlayer.duration
            
            // Asegurarnos de que tempPlayer no sea liberado antes de tiempo
            self.audioPlayer = tempPlayer
            
            print("✅ Audio preparado correctamente - Duración: \(audioDuration)s")
            completion(true, audioDuration)
        } catch {
            print("❌ Error al preparar el audio: \(error)")
            audioPlayer = nil
            completion(false, 0)
        }
    }
    
    // Delegados
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("La grabación terminó con un error")
        }
        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0.0
            self.cleanupTimers()
        }
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("🏁 Reproducción finalizada naturalmente")
        // No detener inmediatamente el reproductor, permitir que se reutilice
        DispatchQueue.main.async {
            self.isPlaying = false
            // No limpiar audioPlayer = nil aquí para permitir reutilización
        }
    }
    
    // Función para crear estructura de carpetas para grabaciones
    func createRecordingDirectory(for recordingId: UUID) -> URL? {
        guard let voiceMemosURL = getVoiceMemosDirectoryURL() else {
            return nil
        }
        
        let recordingDirectoryURL = voiceMemosURL.appendingPathComponent(recordingId.uuidString, isDirectory: true)
        
        // Crear directorio específico para esta grabación con su UUID
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

    // Método para obtener la URL del directorio donde se guardan las grabaciones
    func getVoiceMemosDirectoryURL() -> URL? {
        // Directorio Documents
        let documentsURL = getDocumentsDirectory()
        
        // Crear directorio Hera principal si no existe
        let heraDirectoryURL = documentsURL.appendingPathComponent("Hera", isDirectory: true)
        if !FileManager.default.fileExists(atPath: heraDirectoryURL.path) {
            do {
                try FileManager.default.createDirectory(at: heraDirectoryURL, withIntermediateDirectories: true)
            } catch {
                print("Error creating Hera directory: \(error)")
                return nil
            }
        }
        
        // Crear directorio VoiceNotes dentro de Hera
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
    
    // Crear directorio Hera para archivos de procesamiento
    // Esta es una función auxiliar para uso interno
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
    
    // Verificar y reparar estructura de directorios
    func verifyAndRepairDirectoryStructure() {
        print("📂 Verificando estructura de directorios...")
        
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ No se pudo acceder al directorio de documentos")
            return
        }
        
        // Verificar/crear directorio Hera principal
        let heraDirectoryURL = documentsDirectory.appendingPathComponent("Hera", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: heraDirectoryURL.path) {
            do {
                try FileManager.default.createDirectory(at: heraDirectoryURL, withIntermediateDirectories: true)
                print("✅ Creado directorio principal Hera: \(heraDirectoryURL.path)")
            } catch {
                print("❌ Error creando directorio principal Hera: \(error)")
            }
        } else {
            print("✓ Directorio principal Hera existe: \(heraDirectoryURL.path)")
        }
        
        // Verificar/crear directorio VoiceNotes dentro de Hera
        let voiceNotesURL = heraDirectoryURL.appendingPathComponent("VoiceNotes", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: voiceNotesURL.path) {
            do {
                try FileManager.default.createDirectory(at: voiceNotesURL, withIntermediateDirectories: true)
                print("✅ Creado directorio VoiceNotes: \(voiceNotesURL.path)")
            } catch {
                print("❌ Error creando directorio VoiceNotes: \(error)")
            }
        } else {
            print("✓ Directorio VoiceNotes existe: \(voiceNotesURL.path)")
        }
        
        // Verificar permisos de escritura
        if FileManager.default.isWritableFile(atPath: voiceNotesURL.path) {
            print("✓ Directorio VoiceNotes tiene permisos de escritura")
            
            // Crear un archivo temporal para probar
            let testFile = voiceNotesURL.appendingPathComponent("test_write.txt")
            do {
                try "Test write".write(to: testFile, atomically: true, encoding: .utf8)
                print("✓ Prueba de escritura exitosa")
                
                // Eliminar archivo temporal
                try FileManager.default.removeItem(at: testFile)
            } catch {
                print("❌ Error en prueba de escritura: \(error)")
            }
        } else {
            print("❌ Directorio VoiceNotes no tiene permisos de escritura")
        }
        
        // Migrar archivos de la estructura antigua si existe
        let oldVoiceRecordingsURL = documentsDirectory.appendingPathComponent("VoiceRecordings", isDirectory: true)
        if FileManager.default.fileExists(atPath: oldVoiceRecordingsURL.path) {
            print("🔄 Encontrado directorio antiguo VoiceRecordings, migrando archivos...")
            
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: oldVoiceRecordingsURL, includingPropertiesForKeys: nil)
                
                if contents.isEmpty {
                    print("✓ Directorio antiguo vacío, eliminando...")
                    try FileManager.default.removeItem(at: oldVoiceRecordingsURL)
                } else {
                    print("🔄 Migrando \(contents.count) elementos...")
                    
                    for itemURL in contents {
                        let destURL = voiceNotesURL.appendingPathComponent(itemURL.lastPathComponent)
                        
                        if !FileManager.default.fileExists(atPath: destURL.path) {
                            try FileManager.default.moveItem(at: itemURL, to: destURL)
                            print("  ✓ Migrado: \(itemURL.lastPathComponent)")
                        } else {
                            print("  ⚠️ Ya existe en destino: \(itemURL.lastPathComponent)")
                        }
                    }
                    
                    // Verificar si ahora está vacío para eliminar
                    let remainingContents = try FileManager.default.contentsOfDirectory(at: oldVoiceRecordingsURL, includingPropertiesForKeys: nil)
                    if remainingContents.isEmpty {
                        try FileManager.default.removeItem(at: oldVoiceRecordingsURL)
                        print("✅ Directorio antiguo eliminado después de migración")
                    }
                }
            } catch {
                print("❌ Error durante la migración: \(error)")
            }
        }
    }
    
    // Método público para listar y verificar las grabaciones
    func listAndVerifyRecordings() {
        print("📊 Verificando grabaciones existentes...")
        
        guard let voiceMemosURL = getVoiceMemosDirectoryURL() else {
            print("❌ No se pudo acceder al directorio de grabaciones")
            return
        }
        
        do {
            // Obtener todos los elementos en el directorio principal
            let contents = try FileManager.default.contentsOfDirectory(at: voiceMemosURL, includingPropertiesForKeys: nil)
            
            print("📁 Encontradas \(contents.count) carpetas de grabación.")
            
            // Verificar cada carpeta de grabación
            for folderURL in contents {
                if folderURL.hasDirectoryPath {
                    let folderName = folderURL.lastPathComponent
                    print("  📂 Carpeta: \(folderName)")
                    
                    // Listar contenidos de la carpeta
                    do {
                        let folderContents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                        print("    📄 Contiene \(folderContents.count) archivos:")
                        
                        // Verificar cada archivo
                        for fileURL in folderContents {
                            let fileName = fileURL.lastPathComponent
                            print("      - \(fileName) (\(getSizeString(for: fileURL)))")
                        }
                        
                        // Verificar archivo de audio
                        let audioURL = folderURL.appendingPathComponent("audio.m4a")
                        if FileManager.default.fileExists(atPath: audioURL.path) {
                            print("    ✅ Archivo de audio existe")
                        } else {
                            print("    ❌ Archivo de audio NO existe")
                        }
                        
                        // Verificar transcripción
                        let transcriptionURL = folderURL.appendingPathComponent("transcription.txt")
                        if FileManager.default.fileExists(atPath: transcriptionURL.path) {
                            print("    ✅ Archivo de transcripción existe")
                        } else {
                            print("    ⚠️ Archivo de transcripción NO existe")
                        }
                        
                        // Verificar análisis
                        let analysisURL = folderURL.appendingPathComponent("analysis.json")
                        if FileManager.default.fileExists(atPath: analysisURL.path) {
                            print("    ✅ Archivo de análisis existe")
                        } else {
                            print("    ⚠️ Archivo de análisis NO existe")
                        }
                    } catch {
                        print("    ❌ Error al listar contenidos: \(error)")
                    }
                }
            }
        } catch {
            print("❌ Error al listar grabaciones: \(error)")
        }
    }
    
    // Obtener tamaño legible de un archivo
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
        return "tamaño desconocido"
    }
} 
