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
        case .markdown: return "Markdown (.md)"
        case .text: return "文本 (.txt)"
        case .shell: return "Shell (.sh)"
        case .json: return "JSON (.json)"
        }
    }

    /// 命名面板预填的默认完整文件名（如「未命名.md」）。
    public var defaultFileName: String {
        "未命名." + fileExtension
    }
}
