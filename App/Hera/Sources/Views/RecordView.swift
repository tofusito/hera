import SwiftUI
import SwiftData
import AVFoundation

struct RecordView: View {
    @ObservedObject var audioManager: AudioManager
    var modelContext: ModelContext
    
    @State private var showingPermissionAlert = false
    @State private var recordingPulse = false
    @State private var buttonScale = 1.0
    @State private var recordingButtonPressed = false
    
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
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            if audioManager.isRecording {
                                _ = audioManager.stopRecording()
                            }
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(AppColors.adaptiveText)
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.08))
                            )
                    }
                    .padding()
                    
                    Spacer()
                }
                
                Spacer()
                
                // Visualización del tiempo centrada con animación
                Text(formatTime(audioManager.recordingTime))
                    .font(.system(size: 80, weight: .thin))
                    .monospacedDigit()
                    .foregroundColor(AppColors.adaptiveText)
                    .contentTransition(.numericText())
                    .scaleEffect(audioManager.isRecording && recordingPulse ? 1.03 : 1.0)
                    .animation(audioManager.isRecording ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default, value: recordingPulse)
                    .onAppear {
                        if audioManager.isRecording {
                            recordingPulse = true
                        }
                    }
                    .onChange(of: audioManager.isRecording) { _, isRecording in
                        recordingPulse = isRecording
                    }
                
                // Añadir indicador visual de que está grabando
                if audioManager.isRecording {
                    HStack(spacing: 20) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                            .scaleEffect(recordingPulse ? 1.1 : 0.9)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: recordingPulse)
                        
                        Text("Grabando")
                            .font(.subheadline)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .padding(.top, 10)
                    .transition(.opacity)
                }
                
                Spacer()
                
                // Botón principal de grabación con fondo adaptativo y animaciones
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        recordingButtonPressed = true
                        buttonScale = 0.9
                        
                        if audioManager.isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }
                    
                    // Reset del estado de pulsación del botón
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            buttonScale = 1.0
                            recordingButtonPressed = false
                        }
                    }
                } label: {
                    ZStack {
                        // Fondo exterior con efecto de material y sombra
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 90, height: 90)
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.15), 
                                    radius: 8, x: 0, y: 3)
                        
                        // Círculo interior principal
                        Circle()
                            .fill(colorScheme == .dark ? Color.gray.opacity(0.3) : AppColors.buttonBackground)
                            .frame(width: 80, height: 80)
                            .overlay(
                                Circle()
                                    .stroke(colorScheme == .dark ? Color.white.opacity(0.7) : Color.white.opacity(0.3), lineWidth: 1.5)
                            )
                        
                        // Elemento central que cambia entre grabación y pausa
                        if audioManager.isRecording {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(colorScheme == .dark ? Color.white : AppColors.primaryText)
                                .frame(width: 30, height: 30)
                                .transition(.scale(scale: 0.7).combined(with: .opacity))
                        } else {
                            Circle()
                                .fill(colorScheme == .dark ? Color.white : AppColors.primaryText)
                                .frame(width: 60, height: 60)
                                .transition(.scale(scale: 0.7).combined(with: .opacity))
                        }
                    }
                    .scaleEffect(buttonScale)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: buttonScale)
                }
                .buttonStyle(PlainButtonStyle())
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
        .alert("Microphone Permission Required", isPresented: $showingPermissionAlert) {
            Button("Go to Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("To record audio, you must allow access to the microphone in the settings.")
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
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                dismiss()
            }
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