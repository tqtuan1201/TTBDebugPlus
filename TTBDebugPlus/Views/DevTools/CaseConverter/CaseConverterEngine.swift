//
//  CaseConverterEngine.swift
//  TTBDebugPlus
//
//  Created by Codex on 2026-05-27.
//  Text case conversion helpers for Dev Tools
//

import Foundation

enum CaseConversionMode: String, CaseIterable, Identifiable {
    case title = "Title Case"
    case sentence = "Sentence case"
    case upper = "UPPER CASE"
    case lower = "lower case"
    case firstLetter = "First Letter"
    case alternate = "aLtErNaTe"
    case toggle = "tOGGLE"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .title: return "textformat.size"
        case .sentence: return "textformat"
        case .upper: return "a.square"
        case .lower: return "a.square.fill"
        case .firstLetter: return "textformat.abc"
        case .alternate: return "textformat.alt"
        case .toggle: return "arrow.up.arrow.down"
        }
    }
    
    var description: String {
        switch self {
        case .title:
            return "Capitalize headline words while keeping common short words lowercase."
        case .sentence:
            return "Lowercase text, then capitalize the first letter after sentence breaks."
        case .upper:
            return "Convert every character to uppercase."
        case .lower:
            return "Convert every character to lowercase."
        case .firstLetter:
            return "Capitalize the first letter of each word and lowercase the rest."
        case .alternate:
            return "Alternate lowercase and uppercase letters across the text."
        case .toggle:
            return "Swap uppercase letters to lowercase and lowercase letters to uppercase."
        }
    }
}

enum CaseConverterEngine {
    static func convert(_ input: String, mode: CaseConversionMode) -> String {
        switch mode {
        case .title:
            return titleCase(input)
        case .sentence:
            return sentenceCase(input)
        case .upper:
            return input.uppercased()
        case .lower:
            return input.lowercased()
        case .firstLetter:
            return mapWords(input) { word, _ in
                capitalizedWord(word)
            }
        case .alternate:
            return alternateCase(input)
        case .toggle:
            return toggleCase(input)
        }
    }
    
    static func wordCount(_ input: String) -> Int {
        input
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
    
    static func characterCount(_ input: String) -> Int {
        input.count
    }
    
    private static func titleCase(_ input: String) -> String {
        let minorWords: Set<String> = [
            "a", "an", "the",
            "and", "but", "or", "for", "nor", "so", "yet",
            "as", "at", "by", "in", "of", "on", "per", "to", "up", "via"
        ]
        
        return mapWords(input) { word, index in
            let lowercasedWord = word.lowercased()
            if index > 0, minorWords.contains(lowercasedWord) {
                return lowercasedWord
            }
            return capitalizedWord(word)
        }
    }
    
    private static func sentenceCase(_ input: String) -> String {
        var output = ""
        var shouldCapitalize = true
        
        for character in input.lowercased() {
            if character.isLetter {
                output += shouldCapitalize ? String(character).uppercased() : String(character)
                shouldCapitalize = false
            } else {
                output.append(character)
                if character.isSentenceBreak {
                    shouldCapitalize = true
                }
            }
        }
        
        return output
    }
    
    private static func alternateCase(_ input: String) -> String {
        var output = ""
        var letterIndex = 0
        
        for character in input {
            guard character.isLetter else {
                output.append(character)
                continue
            }
            
            output += letterIndex.isMultiple(of: 2)
                ? String(character).lowercased()
                : String(character).uppercased()
            letterIndex += 1
        }
        
        return output
    }
    
    private static func toggleCase(_ input: String) -> String {
        var output = ""
        
        for character in input {
            guard character.isLetter else {
                output.append(character)
                continue
            }
            
            let text = String(character)
            output += text == text.uppercased() ? text.lowercased() : text.uppercased()
        }
        
        return output
    }
    
    private static func mapWords(_ input: String, transform: (String, Int) -> String) -> String {
        var output = ""
        var currentWord = ""
        var wordIndex = 0
        
        func flushWordIfNeeded() {
            guard !currentWord.isEmpty else { return }
            output += transform(currentWord, wordIndex)
            currentWord = ""
            wordIndex += 1
        }
        
        for character in input {
            if character.isLetterOrNumber {
                currentWord.append(character)
            } else {
                flushWordIfNeeded()
                output.append(character)
            }
        }
        
        flushWordIfNeeded()
        return output
    }
    
    private static func capitalizedWord(_ word: String) -> String {
        let lowercasedWord = word.lowercased()
        guard let first = lowercasedWord.first else { return lowercasedWord }
        return first.uppercased() + String(lowercasedWord.dropFirst())
    }
}

private extension Character {
    var isLetter: Bool {
        unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
    }
    
    var isLetterOrNumber: Bool {
        unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
        }
    }
    
    var isSentenceBreak: Bool {
        self == "." || self == "!" || self == "?" || self == "\n"
    }
}
