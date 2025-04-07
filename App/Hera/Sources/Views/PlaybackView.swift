import SwiftUI
import AVFoundation
import SwiftData
import EventKit // Importar EventKit para acceso al calendario

// Structure to decode the JSON analysis response
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
                        print("❌ Error requesting access to calendar: \(error)")
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, error in
                DispatchQueue.main.async {
                    completion(granted)
                    if let error = error {
                        print("❌ Error requesting access to calendar: \(error)")
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
                        print("❌ Error requesting access to reminders: \(error)")
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .reminder) { granted, error in
                DispatchQueue.main.async {
                    completion(granted)
                    if let error = error {
                        print("❌ Error requesting access to reminders: \(error)")
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
    
    // Add reminder to the Reminders app
    func addReminderToApp(title: String, dateString: String, notes: String? = nil, completion: @escaping (Bool, Error?, String) -> Void) {
        // Create a date formatter to interpret the string
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "es_ES")
        
        // Try different formats if the first fails
        var reminderDate: Date?
        let possibleFormats = ["dd/MM/yyyy HH:mm", "dd/MM/yyyy", "d 'de' MMMM 'de' yyyy", "d 'de' MMMM", "MMMM d, yyyy", "yyyy-MM-dd", "yyyy/MM/dd"]
        
        // Try with specific formats
        for format in possibleFormats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: dateString) {
                reminderDate = date
                print("✅ Reminder date correctly interpreted using format: \(format)")
                print("📅 Interpreted date: \(date)")
                break
            }
        }
        
        // If it didn't work with specific formats, use tomorrow as default
        if reminderDate == nil {
            // Create a default date for tomorrow
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            reminderDate = tomorrow
            print("⚠️ Could not interpret the date: '\(dateString)'. Using default date: tomorrow")
        }
        
        guard let dueDate = reminderDate else {
            completion(false, NSError(domain: "ReminderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not interpret the date"]), "")
            return
        }
        
        // Create reminder
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes ?? "Reminder added from Hera"
        
        // Set reminder date (date only, ignoring time)
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
        // Set fixed time for all reminders (9:00 AM)
        dateComponents.hour = 9
        dateComponents.minute = 0
        
        reminder.dueDateComponents = dateComponents
        reminder.priority = 5 // Medium priority
        
        // Use the default reminders list
        if let defaultList = eventStore.defaultCalendarForNewReminders() {
            reminder.calendar = defaultList
            print("📋 Using reminders list: \(defaultList.title)")
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            
            // Format the date to show to the user
            dateFormatter.dateFormat = "dd/MM/yyyy"
            let formattedDate = dateFormatter.string(from: dueDate)
            
            let remindersList = "List: \(reminder.calendar?.title ?? "Default")"
            
            completion(true, nil, "Reminder date: \(formattedDate)\n\(remindersList)")
        } catch let error {
            print("❌ Error saving reminder: \(error.localizedDescription)")
            completion(false, error, "")
        }
    }
    
    // Add event to calendar
    func addEventToCalendar(title: String, dateString: String, timeString: String? = nil, notes: String? = nil, completion: @escaping (Bool, Error?, String) -> Void) {
        // Create a date formatter to interpret the string
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "es_ES")
        
        // Try different formats if the first fails
        var eventDate: Date?
        let possibleFormats = ["dd/MM/yyyy HH:mm", "dd/MM/yyyy", "d 'de' MMMM 'de' yyyy", "d 'de' MMMM", "MMMM d, yyyy", "yyyy-MM-dd", "yyyy/MM/dd"]
        
        // Try with specific formats
        for format in possibleFormats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: dateString) {
                eventDate = date
                print("✅ Date correctly interpreted using format: \(format)")
                print("📅 Interpreted date: \(date)")
                break
            }
        }
        
        // If it didn't work with specific formats, try with DateParser from NaturalLanguage
        if eventDate == nil {
            // Create a default date for tomorrow
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            eventDate = tomorrow
            print("⚠️ Could not interpret the date: '\(dateString)'. Using default date: tomorrow")
        }
        
        guard let startDate = eventDate else {
            completion(false, NSError(domain: "CalendarError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not interpret the date"]), "")
            return
        }
        
        // Create event
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        
        // Determine if it's an all-day event or with specific time
        let isAllDayEvent = timeString == nil || timeString?.isEmpty == true
        
        if isAllDayEvent {
            // Configure as all-day event
            event.isAllDay = true
            event.startDate = Calendar.current.startOfDay(for: startDate)
            event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: event.startDate)
            print("📅 Configured as all-day event")
        } else {
            // Configure event with specific time
            event.isAllDay = false
            
            // Extract hour and minutes
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            
            if let timeDate = timeFormatter.date(from: timeString!) {
                let calendar = Calendar.current
                let timeComponents = calendar.dateComponents([.hour, .minute], from: timeDate)
                
                // Create date with specific time
                var fullDateComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
                fullDateComponents.hour = timeComponents.hour
                fullDateComponents.minute = timeComponents.minute
                
                if let fullDate = calendar.date(from: fullDateComponents) {
                    event.startDate = fullDate
                    // One hour event by default
                    event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: fullDate)
                    print("🕒 Time set: \(timeString!)")
                } else {
                    // Fallback if there's a problem with the time
                    event.startDate = startDate
                    event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: startDate)
                    print("⚠️ Could not set specific time, using default time")
                }
            } else {
                // Fallback if time can't be interpreted
                event.startDate = startDate
                event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: startDate)
                print("⚠️ Could not interpret time: '\(timeString!)', using default time")
            }
        }
        
        event.notes = notes ?? "Event added from Hera"
        
        // Try to use the user's primary calendar if available
        if let primaryCalendar = eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications }) {
            event.calendar = primaryCalendar
            print("📆 Using calendar: \(primaryCalendar.title)")
        } else {
            event.calendar = eventStore.defaultCalendarForNewEvents
            print("📆 Using default calendar")
        }
        
        // Add an alarm 30 minutes before to make the event more visible (only for non-all-day events)
        if !isAllDayEvent {
            let alarm = EKAlarm(relativeOffset: -30 * 60) // 30 minutes before
            event.addAlarm(alarm)
        }
        
        do {
            try eventStore.save(event, span: .thisEvent)
            
            // Format the date to show to the user
            dateFormatter.dateFormat = "dd/MM/yyyy"
            let formattedDate = dateFormatter.string(from: startDate)
            
            var calendarDetails = "Calendar: \(event.calendar?.title ?? "Default")"
            
            // Add information about the event type
            if isAllDayEvent {
                calendarDetails += "\nType: All-day event"
            } else {
                calendarDetails += "\nType: Specific time event (\(timeString ?? "unknown"))"
            }
            
            completion(true, nil, "Event date: \(formattedDate)\n\(calendarDetails)")
        } catch let error {
            print("❌ Error saving event: \(error.localizedDescription)")
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
    
    @State private var showAllNotes: Bool = false
    @State private var isShowingTooltip: Bool = false
    @State private var buttonScale: CGFloat = 1.0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Fondo principal adaptativo
            AppColors.background
                .ignoresSafeArea()
                
            // Contenido principal (área scrolleable)
            VStack(spacing: 16) {
                // Título de la grabación (parte superior)
                Text(recording.title)
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
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
                    
                    ProgressView("Loading audio...")
                        .padding()
                        .background(colorScheme == .dark ? 
                                   Color(UIColor.systemBackground).opacity(0.8) : 
                                   Color(UIColor.systemBackground))
                        .cornerRadius(10)
                }
                
                if isTranscribing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack {
                        ProgressView("Transcribing...")
                        Text("This process may take a few seconds")
                            .font(.caption)
                            .padding(.top, 8)
                    }
                    .padding()
                    .background(colorScheme == .dark ? 
                               Color(UIColor.systemBackground).opacity(0.8) : 
                               Color(UIColor.systemBackground))
                    .cornerRadius(10)
                }
                
                if isProcessing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack {
                        ProgressView("Analyzing transcription...")
                        Text("This process may take a few seconds")
                            .font(.caption)
                            .padding(.top, 8)
                    }
                    .padding()
                    .background(colorScheme == .dark ? 
                               Color(UIColor.systemBackground).opacity(0.8) : 
                               Color(UIColor.systemBackground))
                    .cornerRadius(10)
                }
            }
        )
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Playback")
        .alert(isPresented: Binding<Bool>(
            get: { audioError != nil },
            set: { if !$0 { audioError = nil } }
        )) {
            Alert(
                title: Text("Error"),
                message: Text(audioError ?? "Unknown error"),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog("Options", isPresented: $showOptions) {
            Button("Rename") {
                newRecordingName = recording.title
                showRenameDialog = true
            }
            
            Button("Share") {
                shareMemo()
            }
            
            Button("Delete", role: .destructive) {
                // Función para eliminar
            }
            
            Button("Cancel", role: .cancel) {
                showOptions = false
            }
        }
        .alert("Rename recording", isPresented: $showRenameDialog) {
            TextField("Name", text: $newRecordingName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if !newRecordingName.isEmpty {
                    renameRecording(newName: newRecordingName)
                }
            }
            .disabled(newRecordingName.isEmpty)
        } message: {
            Text("Enter a new name for this recording")
        }
        // Alerta después de añadir un evento al calendario
        .alert("Event Added", isPresented: $showCalendarAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The event has been added to your calendar.")
        }
        // Alerta para solicitar permisos de calendario
        .alert("Calendar Access Required", isPresented: $showCalendarPermissionAlert) {
            Button("Go to Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This app needs access to your calendar to add events. Please grant permission in settings.")
        }
        // Alerta después de añadir un recordatorio
        .alert("Reminder Added", isPresented: $showReminderAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The reminder has been added to your list.")
        }
        // Alerta para solicitar permisos de recordatorios
        .alert("Reminders Access Required", isPresented: $showReminderPermissionAlert) {
            Button("Go to Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This app needs access to your reminders to add tasks. Please grant permission in settings.")
        }
        // Alerta después de exportar a Notas
        .alert(isPresented: $showNotesAlert) {
            Alert(
                title: Text("Notes"),
                message: Text(notesAlertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            // Registrar tiempo de aparición para detectar ciclos
            viewAppearTime = Date()
            
            print("🟢 PlaybackView appeared: \(recording.id.uuidString) (instance: \(instanceNumber))")
            
            if !viewAppeared {
                viewAppeared = true
                print("🔄 View appeared for the first time")
                
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
            
            print("🔴 PlaybackView disappeared: \(recording.id.uuidString) (instance: \(instanceNumber), time visible: \(String(format: "%.2f", timeVisible))s)")
            
            // Invalidar el timer
            if timer != nil {
                timer?.invalidate()
                timer = nil
            }
        }
        // Cambiar sheet a NavigationLink
        .navigationDestination(isPresented: $showAllNotes) {
            AnalyzedNotesListView()
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
                        Text("Transcribe")
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
                        Text("Configure API Key")
                    }
                    .font(.footnote)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(AppColors.accent, lineWidth: 1)
                    )
                    .foregroundColor(AppColors.primaryText)
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
                        Text("Analyze Transcription")
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
                    Text("Transcription:")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(transcription)
                        .font(.body)
                        .foregroundColor(AppColors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(colorScheme == .dark ? 
                                   Color("CardBackground").opacity(0.7) : 
                                   Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                }
            } else {
                // Mostrar el resultado del análisis
                if let analysisData = analysisData {
                    // Sección de resumen
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "text.bubble")
                                .foregroundColor(Color("AccentColor"))
                            Text("Summary")
                                .font(.headline)
                                .foregroundColor(Color("PrimaryText"))
                        }
                        
                        ZStack(alignment: .bottomTrailing) {
                            Text(analysisData.summary)
                                .foregroundColor(Color("PrimaryText"))
                                .padding()
                                .padding(.trailing, 80)
                                .padding(.bottom, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(colorScheme == .dark ? 
                                           Color("CardBackground").opacity(0.7) : 
                                           Color(UIColor.secondarySystemBackground))
                                .cornerRadius(8)
                            
                            // Botón minimalista para exportar a Notas
                            Button(action: {
                                exportToNotes()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "note.text")
                                        .font(.footnote)
                                    Text("Export")
                                        .font(.caption)
                                }
                                .padding(6)
                                .background(Color("AccentColor").opacity(0.1))
                                .foregroundColor(Color("PrimaryText"))
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
                                    .foregroundColor(colorScheme == .dark ? .gray.opacity(0.9) : .gray)
                                Text("Events")
                                    .font(.headline)
                                    .foregroundColor(Color("PrimaryText"))
                                Spacer()
                                if let events = analysisData.events {
                                    Text("\(events.count)")
                                        .font(.footnote)
                                        .foregroundColor(Color("PrimaryText").opacity(0.8))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.2))
                                        .cornerRadius(10)
                                } else {
                                    Text("0")
                                        .font(.footnote)
                                        .foregroundColor(Color("PrimaryText").opacity(0.8))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.2))
                                        .cornerRadius(10)
                                }
                                Image(systemName: showEvents ? "chevron.up" : "chevron.down")
                                    .foregroundColor(Color("PrimaryText").opacity(0.7))
                            }
                            .padding(.vertical, 5)
                        }
                        
                        if showEvents, let events = analysisData.events, !events.isEmpty {
                            ForEach(events) { event in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.name)
                                            .fontWeight(.medium)
                                            .foregroundColor(Color("PrimaryText"))
                                        Text(event.date)
                                            .font(.caption)
                                            .foregroundColor(colorScheme == .dark ? 
                                                           Color.white.opacity(0.7) : 
                                                           Color.secondary)
                                    }
                                    Spacer()
                                    
                                    // Botón para añadir al calendario
                                    Button(action: {
                                        addEventToCalendar(title: event.name, date: event.date, timeString: event.time)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.subheadline)
                                            Text("Add")
                                                .font(.subheadline)
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 10)
                                        .background(Color("AccentColor").opacity(0.1))
                                        .foregroundColor(Color("PrimaryText"))
                                        .cornerRadius(15)
                                    }
                                }
                                .padding()
                                .background(colorScheme == .dark ? 
                                           Color("CardBackground").opacity(0.5) : 
                                           Color(UIColor.secondarySystemBackground).opacity(0.7))
                                .cornerRadius(8)
                            }
                        } else if showEvents {
                            Text("No events found in this recording")
                                .font(.subheadline)
                                .foregroundColor(colorScheme == .dark ? 
                                               Color.white.opacity(0.7) : 
                                               Color.secondary)
                                .padding()
                        }
                    }
                    .padding(.vertical, 5)
                    
                    // Sección de recordatorios
                    VStack {
                        Button(action: { showReminders.toggle() }) {
                            HStack {
                                Image(systemName: "list.bullet.clipboard")
                                    .foregroundColor(colorScheme == .dark ? .orange.opacity(0.9) : .orange)
                                Text("Reminders")
                                    .font(.headline)
                                    .foregroundColor(Color("PrimaryText"))
                                Spacer()
                                if let reminders = analysisData.reminders {
                                    Text("\(reminders.count)")
                                        .font(.footnote)
                                        .foregroundColor(Color("PrimaryText").opacity(0.8))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(colorScheme == .dark ? 0.3 : 0.2))
                                        .cornerRadius(10)
                                } else {
                                    Text("0")
                                        .font(.footnote)
                                        .foregroundColor(Color("PrimaryText").opacity(0.8))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(colorScheme == .dark ? 0.3 : 0.2))
                                        .cornerRadius(10)
                                }
                                Image(systemName: showReminders ? "chevron.up" : "chevron.down")
                                    .foregroundColor(Color("PrimaryText").opacity(0.7))
                            }
                            .padding(.vertical, 5)
                        }
                        
                        if showReminders, let reminders = analysisData.reminders, !reminders.isEmpty {
                            ForEach(reminders) { reminder in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(reminder.name)
                                            .fontWeight(.medium)
                                            .foregroundColor(Color("PrimaryText"))
                                        
                                        Text(reminder.date)
                                            .font(.caption)
                                            .foregroundColor(colorScheme == .dark ? 
                                                           Color.white.opacity(0.7) : 
                                                           Color.secondary)
                                    }
                                    Spacer()
                                    
                                    // Button to add to Reminders
                                    Button(action: {
                                        // We get the date value safely
                                        addTaskToReminders(title: reminder.name, date: reminder.date)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.subheadline)
                                            Text("Add")
                                                .font(.subheadline)
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 10)
                                        .background(Color("AccentColor").opacity(0.1))
                                        .foregroundColor(Color("PrimaryText"))
                                        .cornerRadius(15)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal)
                                .background(colorScheme == .dark ? 
                                           Color("CardBackground").opacity(0.5) : 
                                           Color(UIColor.secondarySystemBackground))
                                .cornerRadius(8)
                            }
                        } else if showReminders {
                            Text("No reminders found in this recording")
                                .foregroundColor(colorScheme == .dark ? 
                                               Color.white.opacity(0.7) : 
                                               Color.secondary)
                                .padding()
                        }
                    }
                    .padding(.vertical, 5)
                    
                    // View original transcription
                    if let transcription = recording.transcription {
                        Button(action: {
                            isShowingTranscription.toggle()
                        }) {
                            HStack {
                                Image(systemName: isShowingTranscription ? "chevron.up" : "chevron.down")
                                    .foregroundColor(Color("PrimaryText").opacity(0.7))
                                Text(isShowingTranscription ? "Hide original transcription" : "View original transcription")
                                    .font(.caption)
                                    .foregroundColor(Color("PrimaryText").opacity(0.8))
                            }
                            .padding(.vertical, 10)
                        }
                        
                        if isShowingTranscription {
                            Text(transcription)
                                .font(.body)
                                .foregroundColor(Color("PrimaryText"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(colorScheme == .dark ? 
                                           Color("CardBackground").opacity(0.3) : 
                                           Color(UIColor.tertiarySystemBackground))
                                .cornerRadius(8)
                        }
                    } else {
                        // Show raw analysis if it couldn't be decoded
                        Text("Analysis:")
                            .font(.headline)
                            .foregroundColor(Color("PrimaryText"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                        Text(recording.analysis ?? "")
                            .font(.body)
                            .foregroundColor(Color("PrimaryText"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(colorScheme == .dark ? 
                                       Color("CardBackground").opacity(0.5) : 
                                       Color(UIColor.secondarySystemBackground))
                            .cornerRadius(8)
                    }
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
                                .foregroundColor(.white)
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
                .tint(Color("AccentColor"))
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
    
    // MARK: - Audio methods
    
    // Play/pause audio
    private func togglePlayPause() {
        if audioManager.isPlaying {
            print("⏸️ Pausing playback")
            audioManager.pausePlayback()
            stopPlaybackAndTimer()
        } else {
            print("▶️ Starting playback manually")
            forceLoadAndPlayAudio()
        }
    }
    
    // Force load and playback (for play button)
    private func forceLoadAndPlayAudio() {
        guard !isLoading else { return }
        
        guard let fileURL = recording.fileURL else {
            audioError = "No audio URL available for this recording"
            return
        }
        
        // Check if file exists
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            audioError = "The audio file doesn't exist"
            print("⚠️ Audio file doesn't exist at: \(fileURL.path)")
            return
        }
        
        print("🎬 Forcing audio load: \(fileURL.lastPathComponent)")
        isLoading = true
        
        // If there's already a player playing, use that one
        if audioManager.isPlaying && audioManager.player?.url == fileURL {
            print("🔄 Already playing the correct file, continuing")
            isLoading = false
            
            // Ensure the timer is running
            if timer == nil {
                setupProgressTimer()
            }
            return
        }
        
        // Stop any previous playback
        audioManager.stopPlayback()
        
        // Load the new audio - ALWAYS play after loading
        audioManager.prepareToPlay(url: fileURL) { success, audioDuration in
            // Use a small delay to ensure the view is stable
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isLoading = false
                
                if success {
                    self.duration = audioDuration
                    print("✅ Audio prepared - Duration: \(audioDuration)s")
                    
                    // ALWAYS play after a manual user action
                    print("▶️ Real playback started")
                    self.audioManager.startPlayback(url: fileURL)
                    
                    // Use a slightly longer delay to avoid state conflicts
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        if self.audioManager.isPlaying && self.audioManager.player != nil {
                            self.setupProgressTimer()
                        }
                    }
                } else {
                    self.audioError = "Could not load audio"
                    print("❌ Error loading audio from: \(fileURL.path)")
                }
            }
        }
    }
    
    // Temporizador para actualizar el progreso
    private func setupProgressTimer() {
        // Verificar que el player existe antes de configurar el timer
        if audioManager.player == nil {
            print("⚠️ Cannot set up timer - Player not available")
            return
        }
        
        // Cancelar cualquier timer existente antes de crear uno nuevo
        stopPlaybackAndTimer()
        
        print("⏱️ Setting up progress timer")
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            // Verificar nuevamente que el player sigue existiendo
            guard let player = self.audioManager.player else { 
                print("⚠️ Timer active but player not available - stopping timer")
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
                    print("🏁 Playback completed")
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
            print("⏱️ Timer stopped")
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
            audioError = "No audio URL available or API key not configured"
            print("⚠️ Empty or invalid API Key for processing: '\(openAIKey)'")
            return
        }
        
        // Verificar que el archivo existe
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            isTranscribing = false
            audioError = "The audio file doesn't exist"
            return
        }
        
        isTranscribing = true
        
        // Verificar la grabación actual
        print("🔍 Starting transcription for recording: ID: \(recording.id)")
        
        let service = OpenAIService()
        service.transcribeAudio(fileURL: fileURL, apiKey: openAIKey) { result in
            DispatchQueue.main.async {
                self.isTranscribing = false
                
                switch result {
                case .success(let transcription):
                    if !transcription.isEmpty {
                        print("✅ Transcription completed: \(transcription.prefix(50))...")
                        
                        // Guardar en archivo primero
                        self.saveTranscriptionToFile(transcription, for: fileURL)
                        
                        // Actualizar en SwiftData
                        self.updateTranscriptionInSwiftData(transcription)
                        
                        // Llamar al callback después de la transcripción exitosa
                        completion()
                    } else {
                        self.audioError = "The transcription is empty"
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
        
        print("📁 Saving transcription to directory: \(folderURL.path)")
        
        // Verificar que el directorio existe
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                print("📁 Created directory for transcription: \(folderURL.path)")
            } catch {
                print("❌ Error creating directory for transcription: \(error)")
                return
            }
        }
        
        do {
            try text.write(to: textFileURL, atomically: true, encoding: .utf8)
            print("✅ Transcription saved to file: \(textFileURL.path)")
        } catch {
            print("❌ Error saving transcription to file: \(error)")
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
                print("✅ Transcription successfully saved in SwiftData")
            } else {
                print("⚠️ Could not find the recording in SwiftData: \(self.recording.id)")
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
        guard let _ = recording.fileURL,
              let transcription = recording.transcription,
              !transcription.isEmpty,
              !openAIKey.isEmpty else {
            audioError = "No transcription available or API key not configured"
            print("⚠️ Empty or invalid API Key for processing: '\(openAIKey)'")
            return
        }
        
        isProcessing = true
        
        print("🔍 Starting processing for recording: ID: \(recording.id)")
        
        let service = OpenAIService()
        service.processTranscription(transcription: transcription, recordingId: recording.id, apiKey: openAIKey) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                
                switch result {
                case .success(let analysis):
                    if !analysis.isEmpty {
                        print("✅ Analysis successfully saved in SwiftData")
                        
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
                                print("✅ Analysis successfully saved in SwiftData")
                                
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
        print("Trying to decode analysis JSON")
        
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
            CalendarManager.shared.addEventToCalendar(title: title, dateString: date, timeString: timeString, notes: "Event added from Hera") { success, error, details in
                if success {
                    calendarAlertMessage = "Event '\(title)' successfully added to calendar.\n\n\(details)"
                    showCalendarAlert = true
                } else {
                    calendarAlertMessage = "Could not add event to calendar: \(error?.localizedDescription ?? "Unknown error")"
                    showCalendarAlert = true
                }
            }
        } else {
            // No tenemos permisos, solicitarlos
            CalendarManager.shared.requestAccess { granted in
                if granted {
                    // Permisos concedidos, añadir evento
                    CalendarManager.shared.addEventToCalendar(title: title, dateString: date, timeString: timeString, notes: "Event added from Hera") { success, error, details in
                        if success {
                            calendarAlertMessage = "Event '\(title)' successfully added to calendar.\n\n\(details)"
                            showCalendarAlert = true
                        } else {
                            calendarAlertMessage = "Could not add event to calendar: \(error?.localizedDescription ?? "Unknown error")"
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
    private func addTaskToReminders(title: String, date: String) {
        // Comprobar si tenemos permisos para acceder a recordatorios
        if CalendarManager.shared.checkRemindersAuthorizationStatus() {
            // Tenemos permisos, añadir recordatorio
            CalendarManager.shared.addReminderToApp(title: title, dateString: date, notes: "Reminder added from Hera") { success, error, details in
                if success {
                    reminderAlertMessage = "Reminder '\(title)' added successfully.\n\n\(details)"
                    showReminderAlert = true
                } else {
                    reminderAlertMessage = "Could not add reminder: \(error?.localizedDescription ?? "Unknown error")"
                    showReminderAlert = true
                }
            }
        } else {
            // No tenemos permisos, solicitarlos
            CalendarManager.shared.requestRemindersAccess { granted in
                if granted {
                    // Permisos concedidos, añadir recordatorio
                    CalendarManager.shared.addReminderToApp(title: title, dateString: date, notes: "Reminder added from Hera") { success, error, details in
                        if success {
                            reminderAlertMessage = "Reminder '\(title)' added successfully.\n\n\(details)"
                            showReminderAlert = true
                        } else {
                            reminderAlertMessage = "Could not add reminder: \(error?.localizedDescription ?? "Unknown error")"
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
            shareText += "Transcription:\n\(transcription)\n\n"
        }
        
        if let analysis = recording.analysis, 
           let analysisData = try? JSONDecoder().decode(AnalysisResult.self, from: Data(analysis.utf8)) {
            shareText += "Summary:\n\(analysisData.summary)\n\n"
            
            if let events = analysisData.events, !events.isEmpty {
                shareText += "Events:\n"
                for event in events {
                    shareText += "- \(event.name) (\(event.date))\n"
                }
                shareText += "\n"
            }
            
            if let reminders = analysisData.reminders, !reminders.isEmpty {
                shareText += "Reminders:\n"
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
            notesAlertMessage = "No analysis available to export"
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
            noteBody += "\n\n## Events\n"
            for event in events {
                let timeInfo = event.time != nil ? " at \(event.time!)" : ""
                noteBody += "- \(event.name) - \(event.date)\(timeInfo)\n"
            }
        }
        
        // Añadir sección de recordatorios si hay alguno
        if let reminders = analysisData.reminders, !reminders.isEmpty {
            noteBody += "\n\n## Reminders\n"
            for reminder in reminders {
                let timeInfo = reminder.time != nil ? " at \(reminder.time!)" : ""
                noteBody += "- \(reminder.name) - \(reminder.date)\(timeInfo)\n"
            }
        }
        
        // Si está disponible, añadir la transcripción al final
        if let transcription = recording.transcription {
            noteBody += "\n\n## Original Transcription\n\n"
            noteBody += transcription
        }
        
        // Crear la nota usando NoteKit
        createNote(title: noteTitle, content: noteBody) { success, errorMessage in
            DispatchQueue.main.async {
                if success {
                    self.notesAlertMessage = "Note '\(noteTitle)' has been successfully created in the Notes app."
                } else {
                    self.notesAlertMessage = "Error creating note: \(errorMessage)"
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
                        completion(false, "Could not open Notes app")
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
                        completion(true, "Using share menu as alternative")
                    }
                } else {
                    completion(false, "Could not access view controller for sharing")
                }
            }
        } else {
            completion(false, "Invalid URL")
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
                print("🛑 Playback paused")
            }
        }
    }
    
    func resumePlayback() {
        // Este método reanuda la reproducción si ya está preparado
        if let player = player {
            print("▶️ Playback resumed")
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
    @Environment(\.colorScheme) private var colorScheme
    
    // Estado para la animación de los círculos
    @State private var scales: [CGFloat] = [0.8, 0.6, 0.9, 0.7]
    @State private var timer: Timer?
    
    var body: some View {
        HStack(spacing: 20) {
            // Cuatro círculos animados
            ForEach(0..<4) { index in
                Circle()
                    .fill(colorScheme == .dark ? 
                          (isPlaying ? Color(white: 0.9) : Color.gray.opacity(0.3)) : 
                          (isPlaying ? Color("PrimaryText") : Color.gray.opacity(0.3)))
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

// MARK: - Vistas para la lista de notas
struct AnalyzedNotesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var analyzedNotes: [PlaybackAnalyzedNote] = []
    @State private var searchText: String = ""
    @State private var sortOrder: SortOrder = .newest
    @State private var showSortOptions: Bool = false
    
    // Propiedades calculadas para filtrar y ordenar notas
    private var filteredNotes: [PlaybackAnalyzedNote] {
        if searchText.isEmpty {
            return sortedNotes
        } else {
            return sortedNotes.filter { 
                $0.title.localizedCaseInsensitiveContains(searchText) || 
                $0.recordingTitle.localizedCaseInsensitiveContains(searchText) ||
                $0.summary.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private var sortedNotes: [PlaybackAnalyzedNote] {
        switch sortOrder {
        case .newest:
            return analyzedNotes.sorted { $0.created > $1.created }
        case .oldest:
            return analyzedNotes.sorted { $0.created < $1.created }
        case .alphabetical:
            return analyzedNotes.sorted { $0.title < $1.title }
        }
    }
    
    var body: some View {
        List {
            if analyzedNotes.isEmpty {
                ContentUnavailableView(
                    "No hay notas analizadas",
                    systemImage: "note.text",
                    description: Text("Las notas aparecerán aquí después de analizar tus grabaciones.")
                )
            } else if filteredNotes.isEmpty {
                ContentUnavailableView.search
            } else {
                ForEach(filteredNotes) { note in
                    NavigationLink {
                        NoteDetailFullScreenView(note: note)
                    } label: {
                        HStack(spacing: 15) {
                            // Icono de la nota con círculo
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "doc.text")
                                    .font(.system(size: 18))
                                    .foregroundColor(.blue)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(note.recordingTitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            
                            // Fecha
                            Text(formatDate(note.created))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor.secondarySystemBackground).opacity(0.5))
                            .padding(
                                EdgeInsets(
                                    top: 4,
                                    leading: 8,
                                    bottom: 4,
                                    trailing: 8
                                )
                            )
                    )
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Mis Notas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    showSortOptions = true
                }) {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .confirmationDialog("Ordenar Notas", isPresented: $showSortOptions) {
                    Button("Más recientes primero") { sortOrder = .newest }
                    Button("Más antiguas primero") { sortOrder = .oldest }
                    Button("Alfabéticamente") { sortOrder = .alphabetical }
                    Button("Cancelar", role: .cancel) { }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    dismiss()
                }) {
                    Text("Cerrar")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Buscar notas")
        .onAppear {
            loadAnalyzedNotes()
        }
    }
    
    private func loadAnalyzedNotes() {
        let fetchDescriptor = FetchDescriptor<AudioRecording>()
        
        do {
            let recordings = try modelContext.fetch(fetchDescriptor)
            var notes: [PlaybackAnalyzedNote] = []
            
            for recording in recordings {
                if let analysis = recording.analysis {
                    print("📊 Analysis found for recording \(recording.title)")
                    
                    // Procesar el JSON
                    let processedData = processAnalysisJSON(analysis)
                    
                    if let title = processedData.title, let summary = processedData.summary {
                        print("✅ Procesado exitoso - Título: \(title), Longitud resumen: \(summary.count)")
                        
                        let note = PlaybackAnalyzedNote(
                            id: recording.id,
                            title: title,
                            summary: summary,
                            recordingTitle: recording.title,
                            created: recording.timestamp
                        )
                        notes.append(note)
                    }
                }
            }
            
            // Usar animación para cargar las notas
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                analyzedNotes = notes
            }
            print("✅ Loaded \(notes.count) analyzed notes")
        } catch {
            print("❌ Error loading analyzed notes: \(error)")
        }
    }
    
    // Función para procesar el JSON de análisis
    private func processAnalysisJSON(_ jsonString: String) -> (title: String?, summary: String?) {
        print("🔄 Procesando JSON: \(jsonString.prefix(100))...")
        
        // Intentar extraer desde la respuesta directa de OpenAI
        if let jsonData = jsonString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            
            print("🔍 Contenido del mensaje encontrado: \(content.prefix(100))...")
            
            // Extraer el JSON del contenido
            if let jsonStartIndex = content.firstIndex(of: "{"),
               let jsonEndIndex = content.lastIndex(of: "}") {
                
                let jsonContent = String(content[jsonStartIndex...jsonEndIndex])
                print("📄 JSON interno extraído: \(jsonContent.prefix(100))...")
                
                if let innerData = jsonContent.data(using: .utf8),
                   let innerJson = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any] {
                    
                    let title = innerJson["suggestedTitle"] as? String ?? "Nota sin título"
                    let summary = innerJson["summary"] as? String ?? "Sin contenido"
                    
                    return (title, summary)
                }
            }
        }
        
        // Intentar procesar como JSON directo de AnalysisResult
        if let jsonData = jsonString.data(using: .utf8),
           let analysisResult = try? JSONDecoder().decode(AnalysisResult.self, from: jsonData) {
            return (analysisResult.suggestedTitle, analysisResult.summary)
        }
        
        return (nil, nil)
    }
}

// NUEVA VISTA A PANTALLA COMPLETA PARA EL DETALLE DE NOTAS
struct NoteDetailFullScreenView: View {
    let note: PlaybackAnalyzedNote
    @State private var showCopiedMessage: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    // Convertir el resumen a formato markdown
    private var markdownContent: String {
        """
        # \(note.title)
        
        \(note.summary)
        
        ---
        Grabación: \(note.recordingTitle)
        Fecha: \(formatDate(note.created, includeTime: true))
        """
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Sección de fecha
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                    Text(formatDate(note.created, includeTime: true))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 16)
                
                Divider()
                
                // Contenido del resumen
                if note.summary.isEmpty {
                    Text("No hay contenido disponible para esta nota")
                        .font(.headline)
                        .foregroundColor(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    Text(note.summary)
                        .font(.body)
                        .lineSpacing(8)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(colorScheme == .dark ? Color.black : Color.white)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(colorScheme == .dark ? Color.gray : Color.gray.opacity(0.5), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                        .textSelection(.enabled)
                }
                
                Divider()
                
                // Información de la grabación
                HStack {
                    Image(systemName: "waveform")
                        .foregroundColor(.purple)
                    Text("De la grabación: \(note.recordingTitle)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Botón para copiar al portapapeles con posición fija en la esquina inferior derecha
                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 80) // Espacio para que no tape el botón
                    
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
                        ZStack {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 56, height: 56)
                                .shadow(radius: 4)
                            
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                    .overlay(
                        Text("¡Copiado!")
                            .font(.caption)
                            .padding(8)
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .offset(y: -50)
                            .opacity(showCopiedMessage ? 1 : 0)
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100) // Espacio adicional al final
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    shareNote()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }
    
    private func shareNote() {
        let content = markdownContent
        let activityVC = UIActivityViewController(activityItems: [content], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
}

// Enumeración para las opciones de ordenación
enum SortOrder {
    case newest, oldest, alphabetical
}

// Modelo para las notas analizadas
struct PlaybackAnalyzedNote: Identifiable {
    let id: UUID
    let title: String
    let summary: String
    let recordingTitle: String
    let created: Date
}

// Función para formatear fechas
private func formatDate(_ date: Date, includeTime: Bool = false) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    
    if includeTime {
        formatter.timeStyle = .short
    } else {
        formatter.timeStyle = .none
    }
    
    return formatter.string(from: date)
}

#Preview {
    let recording = AudioRecording(title: "Recording 1", timestamp: Date(), duration: 120)
    PlaybackView(audioManager: AudioManager(), recording: recording)
} 
