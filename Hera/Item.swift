//
//  Item.swift
//  Memo
//
//  Created by Manuel Jesús Gutiérrez Fernández on 27/3/25.
//

import Foundation
import SwiftData

@Model
final class AudioRecording: Identifiable {
    var id: UUID
    var title: String
    var timestamp: Date
    var duration: TimeInterval
    @Attribute(.externalStorage) var fileURL: URL?
    var transcription: String?
    var analysis: String?
    
    init(id: UUID = UUID(), title: String, timestamp: Date = Date(), duration: TimeInterval = 0, fileURL: URL? = nil, transcription: String? = nil, analysis: String? = nil) {
        self.id = id
        self.title = title
        self.timestamp = timestamp
        self.duration = duration
        self.fileURL = fileURL
        self.transcription = transcription
        self.analysis = analysis
    }
}
