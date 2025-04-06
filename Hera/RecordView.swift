import SwiftUI
import SwiftData
import AVFoundation

struct RecordView: View {
    @ObservedObject var audioManager: AudioManager
    var modelContext: ModelContext
    
    @State private var showingPermissionAlert = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack {
                // Botón de retroceso en la esquina superior izquierda
                HStack {
                    Button {
                        if audioManager.isRecording {
                            _ = audioManager.stopRecording()
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(AppColors.adaptiveText)
                    }
                    .padding()
                    
                    Spacer()
                }
                
                Spacer()
                
                // Visualización del tiempo centrada 
                Text(formatTime(audioManager.recordingTime))
                    .font(.system(size: 80, weight: .thin))
                    .monospacedDigit()
                    .foregroundColor(AppColors.adaptiveText)
                
                Spacer()
                
                // Botón principal de grabación con fondo adaptativo
                Button {
                    if audioManager.isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    ZStack {
                        // Fondo exterior con efecto de material y sombra
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 85, height: 85)
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.15), 
                                    radius: 8, x: 0, y: 3)
                        
                        // Círculo interior principal
                        Circle()
                            .fill(colorScheme == .dark ? Color.gray.opacity(0.3) : Color("ButtonBackground"))
                            .frame(width: 75, height: 75)
                            .overlay(
                                Circle()
                                    .stroke(colorScheme == .dark ? Color.white.opacity(0.7) : Color.white.opacity(0.3), lineWidth: 1.5)
                            )
                        
                        // Elemento central que cambia entre grabación y pausa
                        if audioManager.isRecording {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(colorScheme == .dark ? Color.white : Color("PrimaryText"))
                                .frame(width: 30, height: 30)
                        } else {
                            Circle()
                                .fill(colorScheme == .dark ? Color.white : Color("PrimaryText"))
                                .frame(width: 60, height: 60)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // Solo verificamos permisos si no estamos en modo de vista previa
            #if DEBUG
            // No verificar permisos en vista previa
            #else
            checkMicrophonePermission()
            #endif
        }
        .alert("Permiso de micrófono requerido", isPresented: $showingPermissionAlert) {
            Button("Ir a Configuración") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancelar", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Para grabar audio, debes permitir el acceso al micrófono en la configuración.")
        }
        .tint(AppColors.adaptiveTint) // Color de acento adaptativo
    }
    
    private func checkMicrophonePermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            break
        case .denied:
            showingPermissionAlert = true
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                if !granted {
                    DispatchQueue.main.async {
                        showingPermissionAlert = true
                    }
                }
            }
        @unknown default:
            break
        }
    }
    
    private func startRecording() {
        audioManager.startRecording()
    }
    
    private func stopRecording() {
        if let recording = audioManager.stopRecording() {
            saveRecording(recording)
            dismiss()
        }
    }
    
    private func saveRecording(_ recording: AudioRecording) {
        modelContext.insert(recording)
        
        do {
            try modelContext.save()
        } catch {
            print("Error al guardar la grabación: \(error)")
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// Clase mock para usar en previews
class MockAudioManager: AudioManager {
    override func startRecording() {
        // No hacer nada en la vista previa
        print("Mock: startRecording")
    }
    
    override func stopRecording() -> AudioRecording? {
        // No hacer nada en la vista previa
        print("Mock: stopRecording")
        return nil
    }
}

struct RecordViewPreview: PreviewProvider {
    static var previews: some View {
        let modelContainer: ModelContainer
        do {
            modelContainer = try ModelContainer(for: AudioRecording.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        } catch {
            fatalError("Error creando el ModelContainer: \(error)")
        }
        
        let mockManager = MockAudioManager()
        return RecordView(audioManager: mockManager, modelContext: modelContainer.mainContext)
    }
}