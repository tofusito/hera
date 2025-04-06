import Foundation
import AVFoundation

class OpenAIService {
    private let transcriptionEndpoint = "https://api.openai.com/v1/audio/transcriptions"
    private let chatCompletionEndpoint = "https://api.openai.com/v1/chat/completions"
    
    func transcribeAudio(fileURL: URL, apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Crear solicitud
        var request = URLRequest(url: URL(string: transcriptionEndpoint)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Crear fronteras para multipart form data
        let boundary = UUID().uuidString
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Preparar el cuerpo de la solicitud
        var bodyData = Data()
        
        // Añadir el modelo (whisper-1)
        bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        bodyData.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Añadir el archivo de audio
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
        
        // Finalizar el cuerpo
        bodyData.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Asignar el cuerpo a la solicitud
        request.httpBody = bodyData
        
        // Realizar la llamada a la API
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "OpenAIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No se recibieron datos"])))
                return
            }
            
            do {
                // Analizar respuesta JSON
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let text = json["text"] as? String {
                    completion(.success(text))
                } else {
                    // Intentar analizar error
                    let errorResponse = try JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
                    completion(.failure(NSError(domain: "OpenAI", code: 0, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])))
                }
            } catch {
                // Si hay error al decodificar JSON, intentar mostrar el mensaje de error como texto
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
        // Crear solicitud
        var request = URLRequest(url: URL(string: chatCompletionEndpoint)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Obtener la fecha actual en formato completo
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .none
        dateFormatter.locale = Locale(identifier: "es_ES") // Usar español
        let currentDateString = dateFormatter.string(from: Date())
        
        // Crear el prompt con el sistema y la transcripción
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
        
        // Crear el cuerpo JSON
        let requestBody: [String: Any] = [
            "model": "gpt-4o", // modelo actualizado a gpt-4o
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Transcription input: \(transcription)"]
            ],
            "temperature": 0.7
        ]
        
        // Convertir el cuerpo a JSON
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }
        
        // Realizar la llamada a la API
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "OpenAIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No se recibieron datos"])))
                return
            }
            
            // Guardar la respuesta cruda y la transcripción original
            self.saveDataToFiles(recordingId: recordingId, transcription: transcription, responseData: data)
            
            do {
                // Analizar respuesta JSON
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    completion(.success(content))
                } else {
                    // Intentar analizar error
                    let errorResponse = try JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
                    completion(.failure(NSError(domain: "OpenAI", code: 0, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])))
                }
            } catch {
                // Si hay error al decodificar JSON, intentar mostrar el mensaje de error como texto
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
        // Obtener la URL del directorio para esta grabación específica
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Error: No se pudo acceder al directorio de documentos")
            return
        }
        
        let voiceMemosDirectory = documentsDirectory.appendingPathComponent("Hera", isDirectory: true)
        let recordingDirectory = voiceMemosDirectory.appendingPathComponent(recordingId.uuidString, isDirectory: true)
        
        // Crear directorio si no existe
        if !FileManager.default.fileExists(atPath: recordingDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: recordingDirectory, withIntermediateDirectories: true)
            } catch {
                print("Error al crear directorio para archivos de procesamiento: \(error)")
                return
            }
        }
        
        // Guardar la transcripción original
        let transcriptionURL = recordingDirectory.appendingPathComponent("transcription.txt")
        do {
            try transcription.write(to: transcriptionURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error al guardar la transcripción: \(error)")
        }
        
        // Guardar la respuesta cruda de la API
        let responseURL = recordingDirectory.appendingPathComponent("analysis.json")
        do {
            try responseData.write(to: responseURL)
        } catch {
            print("Error al guardar la respuesta de la API: \(error)")
        }
    }
}

// Estructura para decodificar respuestas de error de OpenAI
struct OpenAIErrorResponse: Decodable {
    struct ErrorDetails: Decodable {
        let message: String
        let type: String?
        let param: String?
        let code: String?
    }
    
    let error: ErrorDetails
} 