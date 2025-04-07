import Foundation
import AVFoundation

class OpenAIService {
    private let transcriptionEndpoint = "https://api.openai.com/v1/audio/transcriptions"
    private let chatCompletionEndpoint = "https://api.openai.com/v1/chat/completions"
    
    func transcribeAudio(fileURL: URL, apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Create request
        var request = URLRequest(url: URL(string: transcriptionEndpoint)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Create boundaries for multipart form data
        let boundary = UUID().uuidString
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Prepare the request body
        var bodyData = Data()
        
        // Add the model (whisper-1)
        bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        bodyData.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Add the audio file
        do {
            let audioData = try Data(contentsOf: fileURL)
            bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
            bodyData.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
            bodyData.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
            bodyData.append(audioData)
            bodyData.append("\r\n".data(using: .utf8)!)
        } catch {
            completion(.failure(error))
            return
        }
        
        // Finalize the body
        bodyData.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Assign the body to the request
        request.httpBody = bodyData
        
        // Make the API call
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "OpenAIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            do {
                // Parse JSON response
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let text = json["text"] as? String {
                    completion(.success(text))
                } else {
                    // Try to parse error
                    let errorResponse = try JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
                    completion(.failure(NSError(domain: "OpenAI", code: 0, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])))
                }
            } catch {
                // If there's an error decoding JSON, try to show the error message as text
                if let errorText = String(data: data, encoding: .utf8) {
                    completion(.failure(NSError(domain: "OpenAIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Error: \(errorText)"])))
                } else {
                    completion(.failure(error))
                }
            }
        }
        
        task.resume()
    }
    
    func processTranscription(transcription: String, recordingId: UUID, apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Create request
        var request = URLRequest(url: URL(string: chatCompletionEndpoint)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Get current date in full format
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .none
        dateFormatter.locale = Locale(identifier: "es_ES") // Use Spanish
        let currentDateString = dateFormatter.string(from: Date())
        
        // Create the prompt with system and transcription
        let systemPrompt = """
        You are an assistant that analyzes transcribed voice notes and returns structured information in JSON format.

        Today is \(currentDateString).

        Given the raw transcription below, extract the core content and ignore digressions. Return a JSON object with the following structure:

        {
          "suggestedTitle": "📝 Clear, concise title with emoji",
          "summary": "A well-structured and detailed document that covers all the key points mentioned in the voice note. Format the text with clear headings, bullet points, and paragraphs as appropriate.",
          "events": [
            { "name": "Short event name with emoji", "date": "DD/MM/YYYY", "time": "HH:MM" }
          ],
          "reminders": [
            { "name": "Clear, actionable task", "date": "DD/MM/YYYY", "time": "HH:MM" }
          ]
        }

        Guidelines:
        - **suggestedTitle**: Create a short, meaningful title that captures the essence of the note. Always include an appropriate emoji at the beginning that represents the main topic.
        - **summary**: Create a well-structured document that covers all important points discussed in the audio note. Use proper formatting like headings (# for main points), bullet points (* for lists), and paragraphs to organize the information clearly. Make it comprehensive but concise, like a polished document ready to be shared. If the audio discusses steps or procedures, number them sequentially.
        - **events**: Detect things like meetings, deadlines, or any future plans. Convert relative dates like "next Tuesday" or "in two weeks" to the format DD/MM/YYYY based on today's date.
        - **reminders**: Extract to-do items such as "prepare slides", "send email", etc. Use simple language that works well in task lists.
        - Use emojis in event names to help users visually identify app-created events.
        - Keep the original language of the transcription.
        - Output valid JSON only.
        - Today is \(currentDateString). Use this as reference for relative dates.
        """
        
        // Create JSON body
        let requestBody: [String: Any] = [
            "model": "gpt-4o", // updated model to gpt-4o
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Transcription input: \(transcription)"]
            ],
            "temperature": 0.7
        ]
        
        // Convert body to JSON
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }
        
        // Make the API call
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "OpenAIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            // Save the raw response and original transcription
            self.saveDataToFiles(recordingId: recordingId, transcription: transcription, responseData: data)
            
            do {
                // Parse JSON response
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    completion(.success(content))
                } else {
                    // Try to parse error
                    let errorResponse = try JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
                    completion(.failure(NSError(domain: "OpenAI", code: 0, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])))
                }
            } catch {
                // If there's an error decoding JSON, try to show the error message as text
                if let errorText = String(data: data, encoding: .utf8) {
                    completion(.failure(NSError(domain: "OpenAIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Error: \(errorText)"])))
                } else {
                    completion(.failure(error))
                }
            }
        }
        
        task.resume()
    }
    
    private func saveDataToFiles(recordingId: UUID, transcription: String, responseData: Data) {
        // Get the URL of the directory for this specific recording
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Error: Could not access documents directory")
            return
        }
        
        // Use the same directory structure as AudioManager
        let heraDirectory = documentsDirectory.appendingPathComponent("Hera", isDirectory: true)
        let voiceNotesDirectory = heraDirectory.appendingPathComponent("VoiceNotes", isDirectory: true)
        let recordingDirectory = voiceNotesDirectory.appendingPathComponent(recordingId.uuidString, isDirectory: true)
        
        // Verify/create directories if they don't exist
        if !FileManager.default.fileExists(atPath: heraDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: heraDirectory, withIntermediateDirectories: true)
            } catch {
                print("❌ Error creating Hera directory: \(error)")
                return
            }
        }
        
        if !FileManager.default.fileExists(atPath: voiceNotesDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: voiceNotesDirectory, withIntermediateDirectories: true)
            } catch {
                print("❌ Error creating VoiceNotes directory: \(error)")
                return
            }
        }
        
        // Create recording directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: recordingDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: recordingDirectory, withIntermediateDirectories: true)
                print("📁 Created directory for recording: \(recordingDirectory.path)")
            } catch {
                print("❌ Error creating directory for recording: \(error)")
                return
            }
        } else {
            print("📁 Using existing directory: \(recordingDirectory.path)")
        }
        
        // Save the original transcription
        let transcriptionURL = recordingDirectory.appendingPathComponent("transcription.txt")
        do {
            try transcription.write(to: transcriptionURL, atomically: true, encoding: .utf8)
            print("📄 Saved transcription to: \(transcriptionURL.path)")
        } catch {
            print("❌ Error saving transcription: \(error)")
        }
        
        // Save the raw API response
        let responseURL = recordingDirectory.appendingPathComponent("analysis.json")
        do {
            try responseData.write(to: responseURL)
            print("📄 Saved analysis JSON to: \(responseURL.path)")
        } catch {
            print("❌ Error saving API response: \(error)")
        }
    }
}

// Structure to decode OpenAI error responses
struct OpenAIErrorResponse: Decodable {
    struct ErrorDetails: Decodable {
        let message: String
        let type: String?
        let param: String?
        let code: String?
    }
    
    let error: ErrorDetails
} 