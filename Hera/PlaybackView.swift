import SwiftUI
import AVFoundation
import SwiftData
import EventKit // Importar EventKit para acceso al calendario

// Estructura para decodificar la respuesta JSON del análisis
struct AnalysisResult: Codable {
    let summary: String
    let events: [Event]?
    let reminders: [Reminder]?
    let suggestedTitle: String?
    
    struct Event: Codable, Identifiable {
        let name: String
        let date: String
        let time: String?
        
        var id: String { name + date + (time ?? "") }
    }
    
    struct Reminder: Codable, Identifiable {
        let name: String
        let date: String
        let time: String?
        
        var id: String { name + date + (time ?? "") }
    }
}

// Gestor de acceso al calendario
class CalendarManager {
    static let shared = CalendarManager()
    
    private let eventStore = EKEventStore()
    
    // Solicitar permisos de acceso al calendario
    func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToEvents { granted, error in
                DispatchQueue.main.async {
                    completion(granted)
                    if let error = error {
                        print("❌ Error al solicitar acceso al calendario: \(error)")
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, error in
                DispatchQueue.main.async {
                    completion(granted)
                    if let error = error {
                        print("❌ Error al solicitar acceso al calendario: \(error)")
                    }
                }
            }
        }
    }
    
    // Solicitar permisos de acceso a recordatorios
    func requestRemindersAccess(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToReminders { granted, error in
                DispatchQueue.main.async {
                    completion(granted)
                    if let error = error {
                        print("❌ Error al solicitar acceso a recordatorios: \(error)")
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .reminder) { granted, error in
                DispatchQueue.main.async {
                    completion(granted)
                    if let error = error {
                        print("❌ Error al solicitar acceso a recordatorios: \(error)")
                    }
                }
            }
        }
    }
    
    // Comprobar estado de los permisos de calendario
    func checkCalendarAuthorizationStatus() -> Bool {
        let status: EKAuthorizationStatus
        
        if #available(iOS 17.0, *) {
            status = EKEventStore.authorizationStatus(for: .event)
        } else {
            status = EKEventStore.authorizationStatus(for: .event)
        }
        
        switch status {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }
    
    // Comprobar estado de los permisos de recordatorios
    func checkRemindersAuthorizationStatus() -> Bool {
        let status: EKAuthorizationStatus
        
        if #available(iOS 17.0, *) {
            status = EKEventStore.authorizationStatus(for: .reminder)
        } else {
            status = EKEventStore.authorizationStatus(for: .reminder)
        }
        
        switch status {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }
    
    // Añadir recordatorio a la app de Recordatorios
    func addReminderToApp(title: String, dateString: String, notes: String? = nil, completion: @escaping (Bool, Error?, String) -> Void) {
        // Crear un formateador de fecha para interpretar la cadena
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "es_ES")
        
        // Intentar diferentes formatos si el primero falla
        var reminderDate: Date?
        var formatoUsado = ""
        let possibleFormats = ["dd/MM/yyyy HH:mm", "dd/MM/yyyy", "d 'de' MMMM 'de' yyyy", "d 'de' MMMM", "MMMM d, yyyy", "yyyy-MM-dd", "yyyy/MM/dd"]
        
        // Intentar con formatos específicos
        for format in possibleFormats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: dateString) {
                reminderDate = date
                formatoUsado = format
                print("✅ Fecha de recordatorio interpretada correctamente usando formato: \(format)")
                print("📅 Fecha interpretada: \(date)")
                break
            }
        }
        
        // Si no funcionó con formatos específicos, usar mañana como predeterminado
        if reminderDate == nil {
            // Crear una fecha por defecto para mañana
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            reminderDate = tomorrow
            print("⚠️ No se pudo interpretar la fecha: '\(dateString)'. Usando fecha predeterminada: mañana")
            formatoUsado = "fecha predeterminada (mañana)"
        }
        
        guard let dueDate = reminderDate else {
            completion(false, NSError(domain: "ReminderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se pudo interpretar la fecha"]), "")
            return
        }
        
        // Crear recordatorio
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes ?? "Recordatorio añadido desde Hera"
        
        // Establecer fecha de recordatorio (solo fecha, ignorando hora)
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
        // Establecer hora fija para todos los recordatorios (9:00 AM)
        dateComponents.hour = 9
        dateComponents.minute = 0
        
        reminder.dueDateComponents = dateComponents
        reminder.priority = 5 // Prioridad media
        
        // Usar la lista de recordatorios predeterminada
        if let defaultList = eventStore.defaultCalendarForNewReminders() {
            reminder.calendar = defaultList
            print("📋 Usando lista de recordatorios: \(defaultList.title)")
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            
            // Formatear la fecha para mostrarla al usuario
            dateFormatter.dateFormat = "dd/MM/yyyy"
            let fechaFormateada = dateFormatter.string(from: dueDate)
            
            let listaRecordatorios = "Lista: \(reminder.calendar?.title ?? "Predeterminada")"
            
            completion(true, nil, "Fecha del recordatorio: \(fechaFormateada)\n\(listaRecordatorios)")
        } catch let error {
            print("❌ Error al guardar recordatorio: \(error.localizedDescription)")
            completion(false, error, "")
        }
    }
    
    // Añadir evento al calendario
    func addEventToCalendar(title: String, dateString: String, timeString: String? = nil, notes: String? = nil, completion: @escaping (Bool, Error?, String) -> Void) {
        // Crear un formateador de fecha para interpretar la cadena
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "es_ES")
        
        // Intentar diferentes formatos si el primero falla
        var eventDate: Date?
        var formatoUsado = ""
        let possibleFormats = ["dd/MM/yyyy HH:mm", "dd/MM/yyyy", "d 'de' MMMM 'de' yyyy", "d 'de' MMMM", "MMMM d, yyyy", "yyyy-MM-dd", "yyyy/MM/dd"]
        
        // Intentar con formatos específicos
        for format in possibleFormats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: dateString) {
                eventDate = date
                formatoUsado = format
                print("✅ Fecha interpretada correctamente usando formato: \(format)")
                print("📅 Fecha interpretada: \(date)")
                break
            }
        }
        
        // Si no funcionó con formatos específicos, intentar con DateParser de NaturalLanguage 
        if eventDate == nil {
            // Crear una fecha por defecto para mañana
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            eventDate = tomorrow
            print("⚠️ No se pudo interpretar la fecha: '\(dateString)'. Usando fecha predeterminada: mañana")
            formatoUsado = "fecha predeterminada (mañana)"
        }
        
        guard let startDate = eventDate else {
            completion(false, NSError(domain: "CalendarError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se pudo interpretar la fecha"]), "")
            return
        }
        
        // Crear evento
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        
        // Determinar si es un evento de día completo o con hora específica
        let isAllDayEvent = timeString == nil || timeString?.isEmpty == true
        
        if isAllDayEvent {
            // Configurar como evento de día completo
            event.isAllDay = true
            event.startDate = Calendar.current.startOfDay(for: startDate)
            event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: event.startDate)
            print("📅 Configurado como evento de día completo")
        } else {
            // Configurar evento con hora específica
            event.isAllDay = false
            
            // Extraer la hora y minutos
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            
            if let timeDate = timeFormatter.date(from: timeString!) {
                let calendar = Calendar.current
                let timeComponents = calendar.dateComponents([.hour, .minute], from: timeDate)
                
                // Crear fecha con la hora específica
                var fullDateComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
                fullDateComponents.hour = timeComponents.hour
                fullDateComponents.minute = timeComponents.minute
                
                if let fullDate = calendar.date(from: fullDateComponents) {
                    event.startDate = fullDate
                    // Evento de una hora por defecto
                    event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: fullDate)
                    print("🕒 Hora configurada: \(timeString!)")
                } else {
                    // Fallback si hay algún problema con la hora
                    event.startDate = startDate
                    event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: startDate)
                    print("⚠️ No se pudo configurar la hora específica, usando hora predeterminada")
                }
            } else {
                // Fallback si no se puede interpretar la hora
                event.startDate = startDate
                event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: startDate)
                print("⚠️ No se pudo interpretar la hora: '\(timeString!)', usando hora predeterminada")
            }
        }
        
        event.notes = notes ?? "Evento añadido desde Hera"
        
        // Intentar usar el calendario primario del usuario si está disponible
        if let primaryCalendar = eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications }) {
            event.calendar = primaryCalendar
            print("📆 Usando calendario: \(primaryCalendar.title)")
        } else {
            event.calendar = eventStore.defaultCalendarForNewEvents
            print("📆 Usando calendario por defecto")
        }
        
        // Añadir una alarma 30 minutos antes para hacer más visible el evento (solo para eventos no de día completo)
        if !isAllDayEvent {
            let alarm = EKAlarm(relativeOffset: -30 * 60) // 30 minutos antes
            event.addAlarm(alarm)
        }
        
        do {
            try eventStore.save(event, span: .thisEvent)
            
            // Formatear la fecha para mostrarla al usuario
            dateFormatter.dateFormat = "dd/MM/yyyy"
            let fechaFormateada = dateFormatter.string(from: startDate)
            
            var detallesCalendario = "Calendario: \(event.calendar?.title ?? "Predeterminado")"
            
            // Agregar información sobre el tipo de evento
            if isAllDayEvent {
                detallesCalendario += "\nTipo: Evento de día completo"
            } else {
                detallesCalendario += "\nTipo: Evento con hora específica (\(timeString ?? "desconocida"))"
            }
            
            completion(true, nil, "Fecha del evento: \(fechaFormateada)\n\(detallesCalendario)")
        } catch let error {
            print("❌ Error al guardar evento: \(error.localizedDescription)")
            completion(false, error, "")
        }
    }
}

struct PlaybackView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @ObservedObject var audioManager: AudioManager
    @AppStorage("openai_api_key") private var storedOpenAIKey: String = ""
    
    // Propiedad calculada para eliminar espacios en blanco
    private var openAIKey: String {
        storedOpenAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Estado local
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var playbackProgress: Double = 0
    @State private var isLoading: Bool = false
    @State private var isTranscribing: Bool = false
    @State private var isProcessing: Bool = false
    @State private var timer: Timer?
    @State private var audioError: String?
    @State private var showOptions: Bool = false
    @State private var showRenameDialog: Bool = false
    @State private var newRecordingName: String = ""
    @State private var viewAppearTime: Date = Date()
    @State private var viewAppeared: Bool = false
    @State private var isShowingTranscription: Bool = false
    @State private var instanceNumber = Int.random(in: 1...1000)
    
    // Estados para la visualización desplegable
    @State private var showEvents: Bool = false
    @State private var showReminders: Bool = false
    
    // Estado para almacenar los datos analizados del JSON
    @State private var analysisData: AnalysisResult?
    
    // Estado para alertas de calendario
    @State private var showCalendarAlert: Bool = false
    @State private var calendarAlertMessage: String = ""
    @State private var showCalendarPermissionAlert: Bool = false
    
    @State private var showReminderAlert: Bool = false
    @State private var reminderAlertMessage: String = ""
    @State private var showReminderPermissionAlert: Bool = false
    
    @State private var showNotesAlert: Bool = false
    @State private var notesAlertMessage: String = ""
    
    // Injección de datos
    @Bindable var recording: AudioRecording
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Contenido principal (área scrolleable)
            VStack(spacing: 16) {
                // Título de la grabación (parte superior)
                Text(recording.title)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showOptions = true
                    }
                    .accessibilityIdentifier("recordingTitle")
                    .padding(.bottom, 5)
                
                // Contenido principal (scrolleable)
                ScrollView {
                    VStack(spacing: 15) {
                        if recording.analysis != nil {
                            // Si hay análisis, mostrar en orden: análisis
                            analysisView
                        } else if recording.transcription != nil {
                            // Si hay transcripción pero no análisis, mostrar la vista de análisis
                            analysisView
                        } else {
                            // Si no hay ni transcripción ni análisis, mostrar el reproductor completo
                            playerView
                        }
                    }
                    .padding(.bottom, 80) // Espacio para que no se oculte contenido detrás del reproductor fijo
                }
                .scrollIndicators(.hidden)
            }
            .padding()
            
            // Controles de reproducción fijos en la parte inferior
            if recording.fileURL != nil {
                VStack(spacing: 0) {
                    Divider()
                    
                    // Controles de reproducción compactos
                    compactPlayerControls
                }
                .background(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .overlay(
            ZStack {
                if isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    ProgressView("Cargando audio...")
                        .padding()
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(10)
                }
                
                if isTranscribing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack {
                        ProgressView("Transcribiendo...")
                        Text("Este proceso puede tardar unos segundos")
                            .font(.caption)
                            .padding(.top, 8)
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(10)
                }
                
                if isProcessing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack {
                        ProgressView("Analizando transcripción...")
                        Text("Este proceso puede tardar unos segundos")
                            .font(.caption)
                            .padding(.top, 8)
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(10)
                }
            }
        )
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Reproducción")
        .alert(isPresented: Binding<Bool>(
            get: { audioError != nil },
            set: { if !$0 { audioError = nil } }
        )) {
            Alert(
                title: Text("Error"),
                message: Text(audioError ?? "Error desconocido"),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog("Opciones", isPresented: $showOptions) {
            Button("Renombrar") {
                newRecordingName = recording.title
                showRenameDialog = true
            }
            
            Button("Compartir") {
                shareMemo()
            }
            
            Button("Eliminar", role: .destructive) {
                // Función para eliminar
            }
            
            Button("Cancelar", role: .cancel) {
                showOptions = false
            }
        }
        .alert("Renombrar grabación", isPresented: $showRenameDialog) {
            TextField("Nombre", text: $newRecordingName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Cancelar", role: .cancel) { }
            Button("Guardar") {
                if !newRecordingName.isEmpty {
                    renameRecording(newName: newRecordingName)
                }
            }
            .disabled(newRecordingName.isEmpty)
        } message: {
            Text("Introduce un nuevo nombre para esta grabación")
        }
        // Alerta después de añadir un evento al calendario
        .alert(isPresented: $showCalendarAlert) {
            Alert(
                title: Text("Calendario"),
                message: Text(calendarAlertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        // Alerta para solicitar permisos de calendario
        .alert("Acceso al Calendario", isPresented: $showCalendarPermissionAlert) {
            Button("Cancelar", role: .cancel) { }
            Button("Configurar") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Esta app necesita acceso a tu calendario para añadir eventos. Por favor, concede permisos en la configuración.")
        }
        // Alerta después de añadir un recordatorio
        .alert(isPresented: $showReminderAlert) {
            Alert(
                title: Text("Recordatorio"),
                message: Text(reminderAlertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        // Alerta para solicitar permisos de recordatorios
        .alert("Acceso a Recordatorios", isPresented: $showReminderPermissionAlert) {
            Button("Cancelar", role: .cancel) { }
            Button("Configurar") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Esta app necesita acceso a tus recordatorios para añadir tareas. Por favor, concede permisos en la configuración.")
        }
        // Alerta después de exportar a Notas
        .alert(isPresented: $showNotesAlert) {
            Alert(
                title: Text("Notas"),
                message: Text(notesAlertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            // Registrar tiempo de aparición para detectar ciclos
            viewAppearTime = Date()
            
            print("🟢 PlaybackView apareció: \(recording.id.uuidString) (instancia: \(instanceNumber))")
            
            if !viewAppeared {
                viewAppeared = true
                print("🔄 Vista aparecida por primera vez")
                
                // Si hay análisis disponible, intentar decodificarlo
                if let analysisText = recording.analysis {
                    decodeAnalysisJSON(analysisText)
                }
                
                // Asegurar que los eventos y recordatorios estén colapsados inicialmente
                showEvents = false
                showReminders = false
            }
        }
        .onDisappear {
            let timeVisible = Date().timeIntervalSince(viewAppearTime)
            
            print("🔴 PlaybackView desapareció: \(recording.id.uuidString) (instancia: \(instanceNumber), tiempo visible: \(String(format: "%.2f", timeVisible))s)")
            
            // Invalidar el timer
            if timer != nil {
                timer?.invalidate()
                timer = nil
            }
        }
    }
    
    // MARK: - Vistas Componentes
    
    // Vista del reproductor de audio
    private var playerView: some View {
        VStack {
            // Usar un spacer más grande arriba para bajar el contenido
            Spacer(minLength: 100)
            
            // Contenido principal centrado
            VStack(spacing: 30) {
                // Visualización de onda
                PlaybackBarsView(isPlaying: audioManager.isPlaying)
                    .frame(height: 200)  // Reducir la altura de 250 a 200
                    .padding(.horizontal)
                
                // Botón de varita mágica para transcripción y análisis
                Button(action: {
                    transcribeAndAnalyze()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16, weight: .medium))
                        Text("Transcribir")
                            .font(.headline)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(.systemBlue).opacity(openAIKey.isEmpty ? 0.3 : 0.7))
                        }
                    )
                    .foregroundColor(openAIKey.isEmpty ? .gray : .white)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.15), 
                            radius: 6, x: 0, y: 2)
                }
                .disabled(shouldDisableButton())
            }
            
            // Usar un spacer flexible para empujar el contenido hacia arriba
            Spacer(minLength: 100)
            
            // Añadir botón de configuración si no hay clave API
            if openAIKey.isEmpty {
                Button(action: {
                    showSettingsSheet()
                }) {
                    HStack {
                        Image(systemName: "key")
                        Text("Configurar API Key")
                    }
                    .font(.footnote)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.blue, lineWidth: 1)
                    )
                }
                .padding(.bottom, 20)
            }
        }
    }
    
    // Vista de análisis cuando hay transcripción
    private var analysisView: some View {
        VStack(spacing: 16) {
            // Botón para analizar si no hay análisis
            if recording.analysis == nil {
                Button(action: {
                    processTranscription()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16, weight: .medium))
                        Text("Analizar Transcripción")
                            .font(.headline)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(.systemBlue).opacity(openAIKey.isEmpty ? 0.3 : 0.7))
                        }
                    )
                    .foregroundColor(openAIKey.isEmpty ? .gray : .white)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.15), 
                            radius: 6, x: 0, y: 2)
                }
                .disabled(openAIKey.isEmpty || isProcessing)
                .padding(.vertical, 20)
                
                // Mostrar la transcripción si no hay análisis
                if let transcription = recording.transcription {
                    Text("Transcripción:")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(transcription)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                }
            } else {
                // Mostrar el resultado del análisis
                if let analysisData = analysisData {
                    // Sección de resumen
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "text.bubble")
                                .foregroundColor(.blue)
                            Text("Resumen")
                                .font(.headline)
                        }
                        
                        ZStack(alignment: .bottomTrailing) {
                            Text(analysisData.summary)
                                .padding()
                                .padding(.trailing, 80)
                                .padding(.bottom, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(8)
                            
                            // Botón minimalista para exportar a Notas
                            Button(action: {
                                exportToNotes()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "note.text")
                                        .font(.footnote)
                                    Text("Exportar")
                                        .font(.caption)
                                }
                                .padding(6)
                                .background(Color("AccentColor").opacity(0.1))
                                .foregroundColor(AppColors.adaptiveText)
                                .cornerRadius(8)
                            }
                            .padding(12)
                        }
                    }
                    .padding(.bottom, 10)
                    
                    // Sección de eventos (siempre visible, incluso si está vacía)
                    VStack {
                        Button(action: { showEvents.toggle() }) {
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundColor(.gray)
                                Text("Eventos")
                                    .font(.headline)
                                Spacer()
                                if let events = analysisData.events {
                                    Text("\(events.count)")
                                        .font(.footnote)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(10)
                                } else {
                                    Text("0")
                                        .font(.footnote)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(10)
                                }
                                Image(systemName: showEvents ? "chevron.up" : "chevron.down")
                            }
                            .padding(.vertical, 5)
                        }
                        
                        if showEvents, let events = analysisData.events, !events.isEmpty {
                            ForEach(events) { event in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.name)
                                            .fontWeight(.medium)
                                        Text(event.date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    
                                    // Botón para añadir al calendario
                                    Button(action: {
                                        addEventToCalendar(title: event.name, date: event.date, timeString: event.time)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.subheadline)
                                            Text("Añadir")
                                                .font(.subheadline)
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 10)
                                        .background(Color("AccentColor").opacity(0.1))
                                        .foregroundColor(AppColors.adaptiveText)
                                        .cornerRadius(15)
                                    }
                                }
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground).opacity(0.7))
                                .cornerRadius(8)
                            }
                        } else if showEvents {
                            Text("No hay eventos en esta grabación")
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .background(Color(UIColor.secondarySystemBackground).opacity(0.3))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 5)
                    
                    // Sección de recordatorios (siempre visible, incluso si está vacía)
                    VStack {
                        Button(action: { showReminders.toggle() }) {
                            HStack {
                                Image(systemName: "bell")
                                    .foregroundColor(.gray)
                                Text("Recordatorios")
                                    .font(.headline)
                                Spacer()
                                if let reminders = analysisData.reminders {
                                    Text("\(reminders.count)")
                                        .font(.footnote)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(10)
                                } else {
                                    Text("0")
                                        .font(.footnote)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(10)
                                }
                                Image(systemName: showReminders ? "chevron.up" : "chevron.down")
                            }
                            .padding(.vertical, 5)
                        }
                        
                        if showReminders, let reminders = analysisData.reminders, !reminders.isEmpty {
                            ForEach(reminders) { reminder in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(reminder.name)
                                            .fontWeight(.medium)
                                        Text(reminder.date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    
                                    // Botón para añadir a Recordatorios
                                    Button(action: {
                                        addReminderToApp(title: reminder.name, date: reminder.date)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.subheadline)
                                            Text("Añadir")
                                                .font(.subheadline)
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 10)
                                        .background(Color("AccentColor").opacity(0.1))
                                        .foregroundColor(AppColors.adaptiveText)
                                        .cornerRadius(15)
                                    }
                                }
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground).opacity(0.7))
                                .cornerRadius(8)
                            }
                        } else if showReminders {
                            Text("No hay recordatorios en esta grabación")
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .background(Color(UIColor.secondarySystemBackground).opacity(0.3))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 5)
                    
                    // Ver transcripción original
                    if let transcription = recording.transcription {
                        Button(action: {
                            isShowingTranscription.toggle()
                        }) {
                            HStack {
                                Image(systemName: isShowingTranscription ? "chevron.up" : "chevron.down")
                                Text(isShowingTranscription ? "Ocultar transcripción original" : "Ver transcripción original")
                                    .font(.caption)
                            }
                            .padding(.vertical, 10)
                        }
                        
                        if isShowingTranscription {
                            Text(transcription)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(UIColor.tertiarySystemBackground))
                                .cornerRadius(8)
                        }
                    }
                } else {
                    // Mostrar el análisis en crudo si no se pudo decodificar
                    Text("Análisis:")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                    Text(recording.analysis ?? "")
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal)
    }
    
    // Controles compactos para reproductor de audio
    private var compactPlayerControls: some View {
        HStack(spacing: 15) {
            // Botón Play/Pause mejorado
            Button(action: togglePlayPause) {
                ZStack {
                    // Fondo con efecto de vidrio
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 75, height: 75)
                    
                    // Círculo principal con icono
                    Circle()
                        .fill(colorScheme == .dark ? Color.gray.opacity(0.5) : Color(red: 0.2, green: 0.2, blue: 0.25))
                        .frame(width: 68, height: 68)
                        .overlay(
                            Circle()
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.7) : Color.white.opacity(0.3), lineWidth: 2.5)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0)
                        .overlay(
                            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.white)
                                .offset(x: audioManager.isPlaying ? 0 : 2)
                        )
                }
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.3), 
                        radius: 12, x: 0, y: 5)
            }
            
            // Barra de reproducción compacta
            VStack(spacing: 4) {
                // Slider
                Slider(value: $playbackProgress, in: 0...1) { editing in
                    if !editing && duration > 0 {
                        seekToPosition(playbackProgress)
                    }
                }
                .tint(Color(.systemBlue))
                .padding(.vertical, 2)
                .disabled(!audioManager.isPlayerReady)
                
                // Tiempos
                HStack {
                    Text(formatTime(currentTime))
                        .font(.caption2)
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
                        .monospacedDigit()
                    
                    Spacer()
                    
                    Text(formatTime(duration))
                        .font(.caption2)
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
    }
    
    // MARK: - Métodos de audio
    
    // Reproducir/pausar audio
    private func togglePlayPause() {
        if audioManager.isPlaying {
            print("⏸️ Pausando reproducción")
            audioManager.pausePlayback()
            stopPlaybackAndTimer()
        } else {
            print("▶️ Iniciando reproducción manualmente")
            forceLoadAndPlayAudio()
        }
    }
    
    // Forzar carga y reproducción (para botón play)
    private func forceLoadAndPlayAudio() {
        guard !isLoading else { return }
        
        guard let fileURL = recording.fileURL else {
            audioError = "No hay URL de audio para esta grabación"
            return
        }
        
        // Verificar existencia del archivo
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            audioError = "El archivo de audio no existe"
            print("⚠️ El archivo de audio no existe en: \(fileURL.path)")
            return
        }
        
        print("🎬 Forzando carga de audio: \(fileURL.lastPathComponent)")
        isLoading = true
        
        // Si ya hay un player reproduciendo, usar ese
        if audioManager.isPlaying && audioManager.player?.url == fileURL {
            print("🔄 Ya está reproduciendo el archivo correcto, continuando")
            isLoading = false
            
            // Asegurar que el timer está funcionando
            if timer == nil {
                setupProgressTimer()
            }
            return
        }
        
        // Detener cualquier reproducción anterior
        audioManager.stopPlayback()
        
        // Cargar el audio nuevo - SIEMPRE reproducir después de cargar
        audioManager.prepareToPlay(url: fileURL) { success, audioDuration in
            // Usar un pequeño retraso para asegurar que la vista está estable
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isLoading = false
                
                if success {
                    self.duration = audioDuration
                    print("✅ Audio preparado - Duración: \(audioDuration)s")
                    
                    // SIEMPRE reproducir después de una acción manual del usuario
                    print("▶️ Reproducción real iniciada")
                    self.audioManager.startPlayback(url: fileURL)
                    
                    // Usar un pequeño delay mayor para evitar conflictos de estado
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        if self.audioManager.isPlaying && self.audioManager.player != nil {
                            self.setupProgressTimer()
                        }
                    }
                } else {
                    self.audioError = "No se pudo cargar el audio"
                    print("❌ Error al cargar el audio desde: \(fileURL.path)")
                }
            }
        }
    }
    
    // Temporizador para actualizar el progreso
    private func setupProgressTimer() {
        // Verificar que el player existe antes de configurar el timer
        guard let player = self.audioManager.player else {
            print("⚠️ No se puede configurar el timer - Player no disponible")
            return
        }
        
        // Cancelar cualquier timer existente antes de crear uno nuevo
        stopPlaybackAndTimer()
        
        print("⏱️ Configurando timer de progreso")
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            // Verificar nuevamente que el player sigue existiendo
            guard let player = self.audioManager.player else { 
                print("⚠️ Timer activo pero sin player disponible - deteniendo timer")
                DispatchQueue.main.async {
                    self.stopPlaybackAndTimer()
                }
                return 
            }
            
            if self.audioManager.isPlaying {
                // Actualizar la posición actual - usar DispatchQueue para evitar ciclos de actualización
                let newTime = player.currentTime
                let newProgress = self.duration > 0 ? newTime / self.duration : 0
                
                DispatchQueue.main.async {
                    self.currentTime = newTime
                    self.playbackProgress = newProgress
                }
                
                // Verificar si llegamos al final
                if newTime >= self.duration - 0.1 {
                    print("🏁 Reproducción completada")
                    DispatchQueue.main.async {
                        self.currentTime = 0
                        self.playbackProgress = 0
                        self.stopPlaybackAndTimer()
                        
                        // Asegurarse de que el player se detiene
                        self.audioManager.stopPlayback()
                    }
                }
            }
        }
        
        if let timer = timer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    
    // Detener reproducción y temporizador
    private func stopPlaybackAndTimer() {
        if timer != nil {
            timer?.invalidate()
            timer = nil
            print("⏱️ Temporizador detenido")
        }
    }
    
    // Adelantar 10 segundos
    private func seekForward() {
        guard audioManager.isPlayerReady else { return }
        
        let newTime = min(currentTime + 10, duration)
        seekToTime(newTime)
    }
    
    // Retroceder 10 segundos
    private func seekBack() {
        guard audioManager.isPlayerReady else { return }
        
        let newTime = max(currentTime - 10, 0)
        seekToTime(newTime)
    }
    
    // Buscar a una posición específica (0-1)
    private func seekToPosition(_ position: Double) {
        guard audioManager.isPlayerReady else { return }
        
        let targetTime = position * duration
        seekToTime(targetTime)
    }
    
    // Buscar a un tiempo específico en segundos
    private func seekToTime(_ targetTime: TimeInterval) {
        if let player = audioManager.player {
            // Establecer nueva posición
            player.currentTime = targetTime
            
            // Actualizar estado
            currentTime = targetTime
            playbackProgress = targetTime / duration
        }
    }
    
    // Formatear tiempo como MM:SS
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // MARK: - Flujo de Transcripción y Análisis
    
    // Método combinado para transcribir y luego analizar automáticamente
    private func transcribeAndAnalyze() {
        if recording.transcription == nil {
            // Transcribir primero y luego analizar automáticamente
            transcribeAudioWithCallback {
                self.processTranscription()
            }
        } else if recording.analysis == nil {
            // Ya hay transcripción, solo analizar
            processTranscription()
        }
    }
    
    // Transcribir audio con callback para encadenar acciones
    private func transcribeAudioWithCallback(completion: @escaping () -> Void) {
        // Verificar que la API key no esté vacía después de eliminar espacios
        guard let fileURL = recording.fileURL, !openAIKey.isEmpty else {
            isTranscribing = false
            audioError = "No hay URL de audio o no hay API key configurada"
            print("⚠️ API Key vacía o inválida: '\(openAIKey)'")
            return
        }
        
        // Verificar que el archivo existe
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            isTranscribing = false
            audioError = "El archivo de audio no existe en: \(fileURL.path)"
            return
        }
        
        isTranscribing = true
        
        // Verificar la grabación actual
        print("🔍 Iniciando transcripción para grabación: ID: \(recording.id)")
        
        let service = OpenAIService()
        service.transcribeAudio(fileURL: fileURL, apiKey: openAIKey) { result in
            DispatchQueue.main.async {
                self.isTranscribing = false
                
                switch result {
                case .success(let transcription):
                    if !transcription.isEmpty {
                        print("✅ Transcripción completada: \(transcription.prefix(50))...")
                        
                        // Guardar en archivo primero
                        self.saveTranscriptionToFile(transcription, for: fileURL)
                        
                        // Actualizar en SwiftData
                        self.updateTranscriptionInSwiftData(transcription)
                        
                        // Llamar al callback después de la transcripción exitosa
                        completion()
                    } else {
                        self.audioError = "La transcripción está vacía"
                    }
                    
                case .failure(let error):
                    print("❌ Error al transcribir: \(error)")
                    self.audioError = "Error al transcribir: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // Guardar transcripción en archivo
    private func saveTranscriptionToFile(_ text: String, for audioURL: URL) {
        let folderURL = audioURL.deletingLastPathComponent()
        let textFileURL = folderURL.appendingPathComponent("transcription.txt")
        
        do {
            try text.write(to: textFileURL, atomically: true, encoding: .utf8)
            print("✅ Transcripción guardada en archivo: \(textFileURL.path)")
        } catch {
            print("❌ Error al guardar transcripción en archivo: \(error)")
        }
    }
    
    // Actualizar la transcripción en SwiftData (refactorizado)
    private func updateTranscriptionInSwiftData(_ transcription: String) {
        // Buscar la grabación original en SwiftData
        let fetchDescriptor = FetchDescriptor<AudioRecording>()
        
        do {
            let allRecordings = try self.modelContext.fetch(fetchDescriptor)
            // Buscar manualmente por ID
            if let originalRecording = allRecordings.first(where: { $0.id == self.recording.id }) {
                // Actualizar la transcripción en la grabación original
                print("🔄 Actualizando transcripción en grabación SwiftData: \(originalRecording.id)")
                originalRecording.transcription = transcription
                try self.modelContext.save()
                
                // Actualizar también la instancia actual
                self.recording.transcription = transcription
                print("✅ Transcripción guardada correctamente en SwiftData")
            } else {
                print("⚠️ No se encontró la grabación en SwiftData: \(self.recording.id)")
                // Intentar guardar en la instancia actual como respaldo
                self.recording.transcription = transcription
                try? self.modelContext.save()
            }
        } catch {
            print("❌ Error al buscar/guardar en SwiftData: \(error)")
            // Intentar guardar en la instancia actual como respaldo
            self.recording.transcription = transcription
            try? self.modelContext.save()
        }
    }
    
    // Procesar la transcripción con OpenAI
    private func processTranscription() {
        guard let fileURL = recording.fileURL,
              let transcription = recording.transcription,
              !transcription.isEmpty,
              !openAIKey.isEmpty else {
            audioError = "No hay transcripción disponible o no hay API key configurada"
            print("⚠️ API Key vacía o inválida para procesamiento: '\(openAIKey)'")
            return
        }
        
        isProcessing = true
        
        print("🔍 Iniciando procesamiento para grabación: ID: \(recording.id)")
        
        let service = OpenAIService()
        service.processTranscription(transcription: transcription, recordingId: recording.id, apiKey: openAIKey) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                
                switch result {
                case .success(let analysis):
                    if !analysis.isEmpty {
                        print("✅ Procesamiento completado")
                        
                        // Buscar la grabación original en SwiftData
                        let fetchDescriptor = FetchDescriptor<AudioRecording>()
                        
                        do {
                            let allRecordings = try self.modelContext.fetch(fetchDescriptor)
                            // Buscar manualmente por ID
                            if let originalRecording = allRecordings.first(where: { $0.id == self.recording.id }) {
                                // Actualizar el análisis en la grabación original
                                print("🔄 Actualizando análisis en grabación SwiftData: \(originalRecording.id)")
                                originalRecording.analysis = analysis
                                try self.modelContext.save()
                                
                                // Actualizar también la instancia actual
                                self.recording.analysis = analysis
                                print("✅ Análisis guardado correctamente en SwiftData")
                                
                                // Decodificar el análisis para mostrarlo
                                self.decodeAnalysisJSON(analysis)
                                
                                // Aplicar el título sugerido si está disponible
                                if let analysisData = self.analysisData, 
                                   let suggestedTitle = analysisData.suggestedTitle,
                                   !suggestedTitle.isEmpty {
                                    // Actualizar el título de la grabación
                                    self.renameRecording(newName: suggestedTitle)
                                }
                            } else {
                                print("⚠️ No se encontró la grabación en SwiftData: \(self.recording.id)")
                                // Intentar guardar en la instancia actual como respaldo
                                self.recording.analysis = analysis
                                try? self.modelContext.save()
                                
                                // Decodificar el análisis para mostrarlo
                                self.decodeAnalysisJSON(analysis)
                                
                                // Aplicar el título sugerido si está disponible
                                if let analysisData = self.analysisData, 
                                   let suggestedTitle = analysisData.suggestedTitle,
                                   !suggestedTitle.isEmpty {
                                    // Actualizar el título de la grabación
                                    self.renameRecording(newName: suggestedTitle)
                                }
                            }
                        } catch {
                            print("❌ Error al buscar/guardar en SwiftData: \(error)")
                            // Intentar guardar en la instancia actual como respaldo
                            self.recording.analysis = analysis
                            try? self.modelContext.save()
                            
                            // Decodificar el análisis para mostrarlo
                            self.decodeAnalysisJSON(analysis)
                            
                            // Aplicar el título sugerido si está disponible
                            if let analysisData = self.analysisData, 
                               let suggestedTitle = analysisData.suggestedTitle,
                               !suggestedTitle.isEmpty {
                                // Actualizar el título de la grabación
                                self.renameRecording(newName: suggestedTitle)
                            }
                        }
                    } else {
                        self.audioError = "El análisis está vacío"
                    }
                    
                case .failure(let error):
                    print("❌ Error al procesar: \(error)")
                    self.audioError = "Error al procesar: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // Decodificar el análisis JSON
    private func decodeAnalysisJSON(_ jsonString: String) {
        print("Intentando decodificar JSON de análisis")
        
        // Limpiar el string de JSON eliminando marcas de código
        var cleanedJsonString = jsonString
        
        // Eliminar caracteres de markdown de código ```json y ```
        if cleanedJsonString.contains("```") {
            // Primero eliminar la línea que contiene ```json o ``` al principio
            let lines = cleanedJsonString.components(separatedBy: "\n")
            var filteredLines = [String]()
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.hasPrefix("```") && !trimmed.hasSuffix("```") {
                    filteredLines.append(line)
                }
            }
            
            cleanedJsonString = filteredLines.joined(separator: "\n")
            print("📝 JSON limpiado de marcas de código markdown")
        }
        
        guard let jsonData = cleanedJsonString.data(using: .utf8) else {
            print("❌ No se pudo convertir el string a data")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let result = try decoder.decode(AnalysisResult.self, from: jsonData)
            self.analysisData = result
            print("✅ JSON decodificado correctamente: \(result.summary.prefix(30))...")
            
            // Mostrar secciones por defecto si tienen contenido
            self.showEvents = result.events?.isEmpty == false
            self.showReminders = result.reminders?.isEmpty == false
        } catch {
            print("❌ Error al decodificar JSON: \(error)")
            
            // Intento de respaldo: buscar manualmente llaves { } JSON y extraer el contenido
            if let startIndex = cleanedJsonString.firstIndex(of: "{"),
               let endIndex = cleanedJsonString.lastIndex(of: "}") {
                
                let jsonSubstring = cleanedJsonString[startIndex...endIndex]
                let extractedJson = String(jsonSubstring)
                
                print("🔄 Intentando con JSON extraído manualmente: \(extractedJson.prefix(50))...")
                
                if let jsonData = extractedJson.data(using: .utf8) {
                    do {
                        let decoder = JSONDecoder()
                        let result = try decoder.decode(AnalysisResult.self, from: jsonData)
                        self.analysisData = result
                        print("✅ JSON extraído decodificado correctamente")
                        
                        // Mostrar secciones por defecto si tienen contenido
                        self.showEvents = result.events?.isEmpty == false
                        self.showReminders = result.reminders?.isEmpty == false
                    } catch let extractionError {
                        print("❌ Error en segundo intento de decodificación: \(extractionError)")
                    }
                }
            }
        }
    }
    
    // Función para renombrar la grabación
    private func renameRecording(newName: String) {
        guard !newName.isEmpty else { return }
        
        // Buscar la grabación original en SwiftData
        let fetchDescriptor = FetchDescriptor<AudioRecording>()
        
        do {
            let allRecordings = try modelContext.fetch(fetchDescriptor)
            // Buscar manualmente por ID
            if let originalRecording = allRecordings.first(where: { $0.id == recording.id }) {
                // Actualizar el nombre en la grabación original
                print("🔄 Actualizando nombre en grabación SwiftData: \(originalRecording.id)")
                originalRecording.title = newName
                try modelContext.save()
                
                // Actualizar también la instancia actual
                recording.title = newName
                
                // Publicar una notificación para que ContentView refresque la lista
                NotificationCenter.default.post(name: Notification.Name("RefreshRecordingsList"), object: nil)
                
                print("✅ Nombre actualizado correctamente en SwiftData")
            } else {
                print("⚠️ No se encontró la grabación en SwiftData: \(recording.id)")
                // Intentar guardar en la instancia actual como respaldo
                recording.title = newName
                try? modelContext.save()
                
                // Publicar notificación para refrescar la lista de todas formas
                NotificationCenter.default.post(name: Notification.Name("RefreshRecordingsList"), object: nil)
            }
        } catch {
            print("❌ Error al buscar/guardar en SwiftData: \(error)")
            // Intentar guardar en la instancia actual como respaldo
            recording.title = newName
            try? modelContext.save()
            
            // Publicar notificación para refrescar la lista de todas formas
            NotificationCenter.default.post(name: Notification.Name("RefreshRecordingsList"), object: nil)
        }
    }
    
    // MARK: - Métodos de ayuda para el botón
    
    // Determinar si se debe deshabilitar el botón
    private func shouldDisableButton() -> Bool {
        if openAIKey.isEmpty {
            // Sin API key
            return true
        }
        
        if isTranscribing || isProcessing {
            // En proceso
            return true
        }
        
        // Todo correcto, habilitar botón
        return false
    }
    
    // Determinar el color de fondo del botón según el estado
    private func determineButtonBackground() -> Color {
        if openAIKey.isEmpty {
            // Sin API key
            return Color.gray.opacity(0.3)
        }
        
        if isTranscribing || isProcessing {
            // En proceso
            return Color.gray.opacity(0.7)
        }
        
        // Estado normal, listo para procesar
        return Color.gray.opacity(0.6)
    }
    
    // Mostrar hoja de configuración de API
    private func showSettingsSheet() {
        // Usar una notificación para abrir la hoja de configuración desde ContentView
        NotificationCenter.default.post(name: Notification.Name("ShowAPISettings"), object: nil)
        // Cerrar la vista actual
        dismiss()
    }
    
    // Función para añadir evento al calendario
    private func addEventToCalendar(title: String, date: String, timeString: String? = nil) {
        // Comprobar si tenemos permisos para acceder al calendario
        if CalendarManager.shared.checkCalendarAuthorizationStatus() {
            // Tenemos permisos, añadir evento
            CalendarManager.shared.addEventToCalendar(title: title, dateString: date, timeString: timeString, notes: "Evento añadido desde Hera") { success, error, detalles in
                if success {
                    calendarAlertMessage = "Evento '\(title)' añadido correctamente al calendario.\n\n\(detalles)"
                    showCalendarAlert = true
                } else {
                    calendarAlertMessage = "No se pudo añadir el evento al calendario: \(error?.localizedDescription ?? "Error desconocido")"
                    showCalendarAlert = true
                }
            }
        } else {
            // No tenemos permisos, solicitarlos
            CalendarManager.shared.requestAccess { granted in
                if granted {
                    // Permisos concedidos, añadir evento
                    CalendarManager.shared.addEventToCalendar(title: title, dateString: date, timeString: timeString, notes: "Evento añadido desde Hera") { success, error, detalles in
                        if success {
                            calendarAlertMessage = "Evento '\(title)' añadido correctamente al calendario.\n\n\(detalles)"
                            showCalendarAlert = true
                        } else {
                            calendarAlertMessage = "No se pudo añadir el evento al calendario: \(error?.localizedDescription ?? "Error desconocido")"
                            showCalendarAlert = true
                        }
                    }
                } else {
                    // Permisos denegados, mostrar alerta
                    showCalendarPermissionAlert = true
                }
            }
        }
    }
    
    // Función para añadir recordatorio a la app de Recordatorios
    private func addReminderToApp(title: String, date: String) {
        // Comprobar si tenemos permisos para acceder a recordatorios
        if CalendarManager.shared.checkRemindersAuthorizationStatus() {
            // Tenemos permisos, añadir recordatorio
            CalendarManager.shared.addReminderToApp(title: title, dateString: date, notes: "Recordatorio añadido desde Hera") { success, error, detalles in
                if success {
                    reminderAlertMessage = "Recordatorio '\(title)' añadido correctamente.\n\n\(detalles)"
                    showReminderAlert = true
                } else {
                    reminderAlertMessage = "No se pudo añadir el recordatorio: \(error?.localizedDescription ?? "Error desconocido")"
                    showReminderAlert = true
                }
            }
        } else {
            // No tenemos permisos, solicitarlos
            CalendarManager.shared.requestRemindersAccess { granted in
                if granted {
                    // Permisos concedidos, añadir recordatorio
                    CalendarManager.shared.addReminderToApp(title: title, dateString: date, notes: "Recordatorio añadido desde Hera") { success, error, detalles in
                        if success {
                            reminderAlertMessage = "Recordatorio '\(title)' añadido correctamente.\n\n\(detalles)"
                            showReminderAlert = true
                        } else {
                            reminderAlertMessage = "No se pudo añadir el recordatorio: \(error?.localizedDescription ?? "Error desconocido")"
                            showReminderAlert = true
                        }
                    }
                } else {
                    // Permisos denegados, mostrar alerta
                    showReminderPermissionAlert = true
                }
            }
        }
    }
    
    // Función para compartir el memo
    private func shareMemo() {
        // Preparar el texto para compartir
        var shareText = ""
        
        shareText += "\(recording.title)\n\n"
        
        if let transcription = recording.transcription {
            shareText += "Transcripción:\n\(transcription)\n\n"
        }
        
        if let analysis = recording.analysis, 
           let analysisData = try? JSONDecoder().decode(AnalysisResult.self, from: Data(analysis.utf8)) {
            shareText += "Resumen:\n\(analysisData.summary)\n\n"
            
            if let events = analysisData.events, !events.isEmpty {
                shareText += "Eventos:\n"
                for event in events {
                    shareText += "- \(event.name) (\(event.date))\n"
                }
                shareText += "\n"
            }
            
            if let reminders = analysisData.reminders, !reminders.isEmpty {
                shareText += "Recordatorios:\n"
                for reminder in reminders {
                    shareText += "- \(reminder.name) (\(reminder.date))\n"
                }
            }
        }
        
        // Crear el item para compartir
        let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        
        // Presentar el controlador
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true, completion: nil)
        }
    }
    
    // Función para exportar a la app Notas del iPhone
    private func exportToNotes() {
        guard let analysisData = analysisData else {
            notesAlertMessage = "No hay análisis disponible para exportar"
            showNotesAlert = true
            return
        }
        
        // Obtener el título sugerido o usar uno predeterminado
        let noteTitle = analysisData.suggestedTitle ?? recording.title
        
        // Construir el cuerpo de la nota con formato
        var noteBody = ""
        
        // Añadir el resumen completo
        noteBody += analysisData.summary
        
        // Añadir sección de eventos si hay alguno
        if let events = analysisData.events, !events.isEmpty {
            noteBody += "\n\n## Eventos\n"
            for event in events {
                let timeInfo = event.time != nil ? " a las \(event.time!)" : ""
                noteBody += "- \(event.name) - \(event.date)\(timeInfo)\n"
            }
        }
        
        // Añadir sección de recordatorios si hay alguno
        if let reminders = analysisData.reminders, !reminders.isEmpty {
            noteBody += "\n\n## Recordatorios\n"
            for reminder in reminders {
                let timeInfo = reminder.time != nil ? " a las \(reminder.time!)" : ""
                noteBody += "- \(reminder.name) - \(reminder.date)\(timeInfo)\n"
            }
        }
        
        // Si está disponible, añadir la transcripción al final
        if let transcription = recording.transcription {
            noteBody += "\n\n## Transcripción original\n\n"
            noteBody += transcription
        }
        
        // Crear la nota usando NoteKit
        createNote(title: noteTitle, content: noteBody) { success, errorMessage in
            DispatchQueue.main.async {
                if success {
                    self.notesAlertMessage = "La nota '\(noteTitle)' ha sido creada correctamente en la aplicación Notas."
                } else {
                    self.notesAlertMessage = "Error al crear la nota: \(errorMessage)"
                }
                self.showNotesAlert = true
            }
        }
    }
    
    // Función auxiliar para crear una nota en la app Notas
    private func createNote(title: String, content: String, completion: @escaping (Bool, String) -> Void) {
        // URL para la integración con la app Notas mediante URL scheme
        var components = URLComponents(string: "mobilenotes://")
        
        // Codificar título y contenido para URL
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedContent = content.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Construir la URL con los parámetros
        components?.queryItems = [
            URLQueryItem(name: "title", value: encodedTitle),
            URLQueryItem(name: "body", value: encodedContent)
        ]
        
        if let url = components?.url {
            // Verificar si la URL es válida y puede ser abierta
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:]) { success in
                    if success {
                        completion(true, "")
                    } else {
                        completion(false, "No se pudo abrir la app Notas")
                    }
                }
            } else {
                // Fallback alternativo usando la API de compartir
                let activityVC = UIActivityViewController(
                    activityItems: [title, content],
                    applicationActivities: nil
                )
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    rootViewController.present(activityVC, animated: true) {
                        completion(true, "Usando el menú compartir como alternativa")
                    }
                } else {
                    completion(false, "No se pudo acceder al controlador de vista para compartir")
                }
            }
        } else {
            completion(false, "URL inválida")
        }
    }
}

// Extensión para agregar métodos al AudioManager
extension AudioManager {
    var isPlayerReady: Bool {
        return player != nil
    }
    
    func pausePlayback() {
        // Este método pausa sin liberar recursos
        if let player = player {
            player.pause()
            // Usar DispatchQueue para actualizar estado
            DispatchQueue.main.async {
                self.isPlaying = false
                print("🛑 Reproducción pausada")
            }
        }
    }
    
    func resumePlayback() {
        // Este método reanuda la reproducción si ya está preparado
        if let player = player {
            print("▶️ Reproducción reanudada")
            player.play()
            // Usar DispatchQueue para actualizar estado
            DispatchQueue.main.async {
                self.isPlaying = true
            }
        }
    }
}

// Vista para visualizar forma de onda durante reproducción
struct PlaybackBarsView: View {
    var isPlaying: Bool
    
    // Estado para la animación de los círculos
    @State private var scales: [CGFloat] = [0.8, 0.6, 0.9, 0.7]
    @State private var timer: Timer?
    
    var body: some View {
        HStack(spacing: 20) {
            // Cuatro círculos animados
            ForEach(0..<4) { index in
                Circle()
                    .fill(isPlaying ? Color.black : Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .scaleEffect(scales[index])
                    .animation(isPlaying ? .easeInOut(duration: 0.6) : nil, value: scales[index])
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 40)
        .onAppear {
            // Solo iniciamos el timer si está reproduciendo
            if isPlaying {
                startAnimationTimer()
            }
        }
        .onDisappear {
            // Detener el timer al desaparecer
            stopAnimationTimer()
        }
        .onChange(of: isPlaying) { _, newValue in
            if newValue {
                // Iniciar animación cuando comienza la reproducción
                startAnimationTimer()
            } else {
                // Detener animación cuando se pausa
                stopAnimationTimer()
                // Resetear los tamaños a valores estáticos cuando está pausado
                resetScales()
            }
        }
    }
    
    // Método para iniciar la animación de los círculos
    private func startAnimationTimer() {
        // Cancelar timer existente
        stopAnimationTimer()
        
        // Crear un nuevo timer que actualiza las escalas aleatoriamente
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            withAnimation {
                // Generar nuevas escalas aleatorias para cada círculo con más rango
                for i in 0..<scales.count {
                    scales[i] = CGFloat.random(in: 0.4...1.2)
                }
            }
        }
        
        // Activar el timer inmediatamente para la primera animación
        timer?.fire()
        
        // Asegurar que el timer funcione incluso cuando hay scroll
        if let timer = timer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    
    // Método para detener la animación
    private func stopAnimationTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // Resetear las escalas a valores estáticos
    private func resetScales() {
        // Valores uniformes para el estado pausado
        scales = [0.8, 0.8, 0.8, 0.8]
    }
}

#Preview {
    let recording = AudioRecording(title: "Recording 1", timestamp: Date(), duration: 120)
    PlaybackView(audioManager: AudioManager(), recording: recording)
} 