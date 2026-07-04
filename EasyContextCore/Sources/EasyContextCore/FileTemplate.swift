public enum FileTemplate: String, CaseIterable, Codable, Sendable {
    case markdown
    case text
    case shell
    case json

    public var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .text: return "txt"
        case .shell: return "sh"
        case .json: return "json"
        }
    }

    public var initialContent: String {
        switch self {
        case .text, .markdown: return ""
        case .shell: return "#!/bin/bash\n"
        case .json: return "{}\n"
        }
    }

    public var isExecutable: Bool {
        self == .shell
    }

    public var displayName: String {
        switch self {
        case .markdown: return String(localized: "Markdown (.md)", bundle: .module)
        case .text:     return String(localized: "Text (.txt)", bundle: .module)
        case .shell:    return String(localized: "Shell (.sh)", bundle: .module)
        case .json:     return String(localized: "JSON (.json)", bundle: .module)
        }
    }

    /// 命名面板预填的默认完整文件名（如「未命名.md」）。
    public var defaultFileName: String {
        String(localized: "Untitled", bundle: .module) + "." + fileExtension
    }
}
