// AnalysisResult.swift
// Created by AI assistant.
// Struct to decode JSON analysis response.

import Foundation

/// Structure to decode the JSON analysis response from OpenAI.
public struct AnalysisResult: Codable {
    /// A summary of the recording content.
    public let summary: String
    /// Extracted events from the summary.
    public let events: [Event]?
    /// Extracted reminders from the summary.
    public let reminders: [Reminder]?
    /// Suggested title based on the recording content.
    public let suggestedTitle: String?

    /// Nested structure representing an event.
    public struct Event: Codable, Identifiable {
        public let name: String
        /// The date string representation of the event.
        public let date: String
        /// Optional time string for the event.
        public let time: String?

        /// A unique identifier for the event.
        public var id: String { name + date + (time ?? "") }
    }

    /// Nested structure representing a reminder.
    public struct Reminder: Codable, Identifiable {
        public let name: String
        /// The date string representation of the reminder.
        public let date: String
        /// Optional time string for the reminder.
        public let time: String?

        /// A unique identifier for the reminder.
        public var id: String { name + date + (time ?? "") }
    }
} 