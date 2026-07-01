public enum FileTemplate: String, CaseIterable, Codable, Sendable {
    case blank
    case markdown
    case text
    case shell
    case json

    public var fileExtension: String {
        switch self {
        case .blank: return ""
        case .markdown: return "md"
        case .text: return "txt"
        case .shell: return "sh"
        case .json: return "json"
        }
    }

    public var initialContent: String {
        switch self {
        case .blank, .text, .markdown: return ""
        case .shell: return "#!/bin/bash\n"
        case .json: return "{}\n"
        }
    }

    public var isExecutable: Bool {
        self == .shell
    }

    public var displayName: String {
        switch self {
        case .blank: return "空白文件"
        case .markdown: return "Markdown (.md)"
        case .text: return "文本 (.txt)"
        case .shell: return "Shell (.sh)"
        case .json: return "JSON (.json)"
        }
    }

    /// 命名面板预填的默认完整文件名（如「未命名.md」；空白模板无扩展名）。
    public var defaultFileName: String {
        fileExtension.isEmpty ? "未命名" : "未命名." + fileExtension
    }
}
