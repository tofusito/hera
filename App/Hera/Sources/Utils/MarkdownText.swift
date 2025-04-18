import SwiftUI

struct MarkdownText: View {
    let markdown: String
    var font: Font = .body
    var accentColor: Color = AppColors.accent
    var lineSpacing: CGFloat = 5
    
    @Environment(\.colorScheme) private var colorScheme
    
    // Process text to convert escape sequences to actual characters
    private var processedText: String {
        var text = markdown
        
        // Replace common escape sequences
        let replacements: [String: String] = [
            "\\n": "\n",
            "\\t": "\t",
            "\\r": "\r",
            "\\\\": "\\",
            "\\\"": "\"",
            "\\\'": "\'",
            "\\n\\n": "\n\n", // Double line break
            "\\n\\r": "\n\r"  // Line break and carriage return combination
        ]
        
        // Apply all substitutions
        for (escape, replacement) in replacements {
            text = text.replacingOccurrences(of: escape, with: replacement)
        }
        
        return text
    }
    
    var body: some View {
        // Always use native Markdown renderer (iOS 16+ minimum)
        renderMarkdownWithTextMarkdown()
    }
    
    @available(iOS 16.0, *)
    private func renderMarkdownWithTextMarkdown() -> some View {
        Text(.init(processedText))
            .font(font)
            .lineSpacing(lineSpacing)
            .textSelection(.enabled)
    }
    
    private var plainText: some View {
        Text(processedText)
            .font(font)
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .lineSpacing(lineSpacing)
            .textSelection(.enabled)
    }
    
    // Function to detect if the text appears to contain Markdown formatting
    private func containsMarkdown(_ text: String) -> Bool {
        // Detect headers
        let headerPattern = #"^#{1,6}\s"#
        if text.range(of: headerPattern, options: .regularExpression, range: nil, locale: nil) != nil {
            return true
        }
        
        // Detect emphasis
        if text.contains("**") || text.contains("__") || 
           (text.contains("*") && !text.contains("* ")) || 
           (text.contains("_") && !text.contains("_ ")) {
            return true
        }
        
        // Detect code blocks
        if text.contains("```") || text.contains("`") {
            return true
        }
        
        // Detect lists
        let listItemPattern = #"^[\s]*[-\*\+]\s"#
        let numberedListPattern = #"^[\s]*\d+\.\s"#
        if text.range(of: listItemPattern, options: .regularExpression, range: nil, locale: nil) != nil ||
           text.range(of: numberedListPattern, options: .regularExpression, range: nil, locale: nil) != nil {
            return true
        }
        
        // Detect links
        let linkPattern = #"\[.*?\]\(.*?\)"#
        if text.range(of: linkPattern, options: .regularExpression, range: nil, locale: nil) != nil {
            return true
        }
        
        // Doesn't appear to contain Markdown formatting
        return false
    }
}

// Custom renderer for earlier versions or if the native parser fails
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
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }
    
    // Structure for each parsed line
    private struct MarkdownLine: Identifiable {
        let id = UUID()
        let text: String
        let type: LineType
        var number: Int = 0
        
        enum LineType {
            case h1, h2, h3, bulletItem, numberItem, codeBlock, normal
        }
    }
    
    // Parse Markdown text line by line
    private func parseMarkdownLines() -> [MarkdownLine] {
        let lines = text.components(separatedBy: "\n")
        var result: [MarkdownLine] = []
        var isInCodeBlock = false
        var codeBlockContent = ""
        var numberItemCounter = 0
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Handle code blocks
            if trimmedLine.starts(with: "```") {
                if isInCodeBlock {
                    // End of code block
                    if !codeBlockContent.isEmpty {
                        result.append(MarkdownLine(text: codeBlockContent, type: .codeBlock))
                        codeBlockContent = ""
                    }
                    isInCodeBlock = false
                } else {
                    // Start of code block
                    isInCodeBlock = true
                }
                continue
            }
            
            if isInCodeBlock {
                codeBlockContent += trimmedLine + "\n"
                continue
            }
            
            // Parse Markdown elements outside code blocks
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
                // Empty line - can be used to separate paragraphs
                result.append(MarkdownLine(text: "", type: .normal))
            }
        }
        
        // If a code block was left open
        if isInCodeBlock && !codeBlockContent.isEmpty {
            result.append(MarkdownLine(text: codeBlockContent, type: .codeBlock))
        }
        
        return result
    }
}

// Extension to solve type problems when returning views
extension View {
    func eraseToAnyView() -> AnyView {
        AnyView(self)
    }
} 