import SwiftUI

struct RecordingCell: View {
    let recording: AudioRecording
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Indicador visual de audio
            Circle()
                .fill(AppColors.accent)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(.white)
                )
                .shadow(color: AppColors.accent.opacity(0.3), radius: 4, x: 0, y: 2)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(recording.title)
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(formatDate(recording.timestamp))
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText.opacity(0.7))
                    
                    Text(formatDuration(recording.duration))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(AppColors.secondaryText.opacity(0.12))
                        )
                }
            }
            
            Spacer()
            
            // Indicador de flecha más estilizado
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.secondaryText.opacity(0.5))
                .padding(.trailing, 8)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.cardBackground)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05), 
                        radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "Hoy, " + formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Ayer"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}