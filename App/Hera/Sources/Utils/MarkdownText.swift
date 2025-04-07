import SwiftUI

struct MarkdownText: View {
    let markdown: String
    var font: Font = .body
    var accentColor: Color = AppColors.accent
    var lineSpacing: CGFloat = 5
    
    @Environment(\.colorScheme) private var colorScheme
    
    // Procesar el texto para convertir secuencias de escape a caracteres reales
    private var processedText: String {
        var text = markdown
        
        // Reemplazar las secuencias de escape comunes
        let replacements: [String: String] = [
            "\\n": "\n",
            "\\t": "\t",
            "\\r": "\r",
            "\\\\": "\\",
            "\\\"": "\"",
            "\\\'": "\'",
            "\\n\\n": "\n\n", // Doble salto de línea
            "\\n\\r": "\n\r"  // Combinación salto de línea y retorno
        ]
        
        // Aplicar todas las sustituciones
        for (escape, replacement) in replacements {
            text = text.replacingOccurrences(of: escape, with: replacement)
        }
        
        return text
    }
    
    var body: some View {
        if #available(iOS 15.0, *) {
            renderMarkdown()
        } else {
            // iOS 14: Fallback a texto plano
            plainText
        }
    }
    
    @available(iOS 15.0, *)
    private func renderMarkdown() -> some View {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,  // Interpretar toda la sintaxis de Markdown
            failurePolicy: .returnPartiallyParsedIfPossible  // Devolver lo que se pueda parsear
        )
        
        do {
            let attributedString = try AttributedString(markdown: processedText, options: options)
            
            return Text(attributedString)
                .textSelection(.enabled)
                .lineSpacing(lineSpacing)
                .eraseToAnyView()
        } catch {
            print("Error al renderizar Markdown: \(error)")
            // Si falla, usar nuestra implementación personalizada más simple
            return MarkdownTextCustomRenderer(text: processedText)
                .eraseToAnyView()
        }
    }
    
    private var plainText: some View {
        Text(processedText)
            .font(font)
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .lineSpacing(lineSpacing)
            .textSelection(.enabled)
    }
    
    // Función para detectar si el texto parece contener formato Markdown
    private func containsMarkdown(_ text: String) -> Bool {
        // Detectar encabezados
        let headerPattern = #"^#{1,6}\s"#
        if text.range(of: headerPattern, options: .regularExpression, range: nil, locale: nil) != nil {
            return true
        }
        
        // Detectar énfasis
        if text.contains("**") || text.contains("__") || 
           (text.contains("*") && !text.contains("* ")) || 
           (text.contains("_") && !text.contains("_ ")) {
            return true
        }
        
        // Detectar bloques de código
        if text.contains("```") || text.contains("`") {
            return true
        }
        
        // Detectar listas
        let listItemPattern = #"^[\s]*[-\*\+]\s"#
        let numberedListPattern = #"^[\s]*\d+\.\s"#
        if text.range(of: listItemPattern, options: .regularExpression, range: nil, locale: nil) != nil ||
           text.range(of: numberedListPattern, options: .regularExpression, range: nil, locale: nil) != nil {
            return true
        }
        
        // Detectar enlaces
        let linkPattern = #"\[.*?\]\(.*?\)"#
        if text.range(of: linkPattern, options: .regularExpression, range: nil, locale: nil) != nil {
            return true
        }
        
        // No parece contener formato Markdown
        return false
    }
}

// Renderer personalizado para versiones anteriores o si falla el parser nativo
struct MarkdownTextCustomRenderer: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseMarkdownLines(), id: \.id) { line in
                switch line.type {
                case .h1:
                    Text(line.text)
                        .font(.largeTitle.bold())
                        .foregroundColor(.primary)
                        .padding(.bottom, 4)
                case .h2:
                    Text(line.text)
                        .font(.title.bold())
                        .foregroundColor(.primary)
                        .padding(.bottom, 2)
                case .h3:
                    Text(line.text)
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                case .bulletItem:
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(line.text)
                    }
                    .padding(.leading, 8)
                case .numberItem:
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(line.number).")
                            .foregroundColor(.secondary)
                        Text(line.text)
                    }
                    .padding(.leading, 8)
                case .codeBlock:
                    Text(line.text)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(4)
                case .normal:
                    Text(line.text)
                }
            }
        }
        .textSelection(.enabled)
    }
    
    // Estructura para cada línea parseada
    private struct MarkdownLine: Identifiable {
        let id = UUID()
        let text: String
        let type: LineType
        var number: Int = 0
        
        enum LineType {
            case h1, h2, h3, bulletItem, numberItem, codeBlock, normal
        }
    }
    
    // Parsear el texto Markdown línea por línea
    private func parseMarkdownLines() -> [MarkdownLine] {
        let lines = text.components(separatedBy: "\n")
        var result: [MarkdownLine] = []
        var isInCodeBlock = false
        var codeBlockContent = ""
        var numberItemCounter = 0
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Manejar bloques de código
            if trimmedLine.starts(with: "```") {
                if isInCodeBlock {
                    // Fin del bloque de código
                    if !codeBlockContent.isEmpty {
                        result.append(MarkdownLine(text: codeBlockContent, type: .codeBlock))
                        codeBlockContent = ""
                    }
                    isInCodeBlock = false
                } else {
                    // Inicio del bloque de código
                    isInCodeBlock = true
                }
                continue
            }
            
            if isInCodeBlock {
                codeBlockContent += trimmedLine + "\n"
                continue
            }
            
            // Parsear elementos de Markdown fuera de bloques de código
            if trimmedLine.starts(with: "# ") {
                let text = trimmedLine.replacingOccurrences(of: "^# ", with: "", options: .regularExpression)
                result.append(MarkdownLine(text: text, type: .h1))
            } else if trimmedLine.starts(with: "## ") {
                let text = trimmedLine.replacingOccurrences(of: "^## ", with: "", options: .regularExpression)
                result.append(MarkdownLine(text: text, type: .h2))
            } else if trimmedLine.starts(with: "### ") {
                let text = trimmedLine.replacingOccurrences(of: "^### ", with: "", options: .regularExpression)
                result.append(MarkdownLine(text: text, type: .h3))
            } else if trimmedLine.starts(with: "- ") || trimmedLine.starts(with: "* ") || trimmedLine.starts(with: "+ ") {
                let pattern = "^[-*+]\\s+"
                let text = trimmedLine.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                result.append(MarkdownLine(text: text, type: .bulletItem))
            } else if let match = trimmedLine.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                let numberString = trimmedLine[..<match.upperBound]
                    .replacingOccurrences(of: #"\.\s*$"#, with: "", options: .regularExpression)
                if let number = Int(numberString) {
                    numberItemCounter = number
                } else {
                    numberItemCounter += 1
                }
                
                let text = trimmedLine.replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
                result.append(MarkdownLine(text: text, type: .numberItem, number: numberItemCounter))
            } else if !trimmedLine.isEmpty {
                result.append(MarkdownLine(text: trimmedLine, type: .normal))
            } else {
                // Línea vacía - puede usarse para separar párrafos
                result.append(MarkdownLine(text: "", type: .normal))
            }
        }
        
        // Si quedó un bloque de código abierto
        if isInCodeBlock && !codeBlockContent.isEmpty {
            result.append(MarkdownLine(text: codeBlockContent, type: .codeBlock))
        }
        
        return result
    }
}

// Extensión para resolver problemas de tipo al retornar vistas
extension View {
    func eraseToAnyView() -> AnyView {
        AnyView(self)
    }
} 