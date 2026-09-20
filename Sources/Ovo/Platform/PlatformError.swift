import Foundation

enum PlatformError: LocalizedError, Equatable {
    case cancelled
    case accessibilityPermissionRequired
    case screenRecordingPermissionRequired
    case noSourceApplication
    case noSelectedText
    case secureTextField
    case copyUnavailable
    case clipboardUnavailable
    case screenshotFailed(String)
    case noRecognizedText
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "已取消截图。"
        case .accessibilityPermissionRequired:
            return "请在系统设置 → 隐私与安全性 → 辅助功能中允许 OvO，然后重新尝试划词翻译。"
        case .screenRecordingPermissionRequired:
            return "请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 OvO，然后重新打开 OvO。"
        case .noSourceApplication:
            return "请先在其他应用中选中文字，再使用划词翻译快捷键。"
        case .noSelectedText:
            return "没有获取到选中文字。请先选中一段文字，或使用截图翻译。"
        case .secureTextField:
            return "密码输入框中的内容无法用于划词翻译。"
        case .copyUnavailable:
            return "无法读取选中文字。请检查辅助功能权限，或使用截图翻译。"
        case .clipboardUnavailable:
            return "暂时无法完整备份剪贴板内容。请重试或使用截图翻译。"
        case .screenshotFailed(let detail):
            return "截图失败。\(detail)"
        case .noRecognizedText:
            return "截图中没有识别到文字。请框选更清晰的文字区域后重试。"
        case .recognitionFailed(let detail):
            return "文字识别失败：\(detail)"
        }
    }
}
