import Foundation

/// Native-only browser tool contract. No script, credential, file or shell tool.
public enum CodexPolicy {
    public static let tools: Set<String> = ["moon_tabs", "moon_read", "moon_inspect", "moon_click", "moon_fill", "moon_scroll", "moon_navigate", "moon_open", "moon_close"]
    public static func webURL(_ text: String) -> URL? {
        guard text.utf8.count <= 8_192, let url = URL(string: text),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return url
    }
    public static func endpoint(_ url: URL) -> Bool {
        url.scheme == "ws" && url.host == "127.0.0.1" && (url.port.map { (1024...65535).contains($0) } ?? false)
            && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
            && (url.path.isEmpty || url.path == "/")
    }
    public static func origin(_ url: URL) -> String {
        "\(url.scheme?.lowercased() ?? "")://\(url.host?.lowercased() ?? ""):\(url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80))"
    }
    public static func protectedField(type: String, autocomplete: String) -> Bool {
        let type = type.lowercased(), completion = autocomplete.lowercased()
        return ["password", "file", "hidden"].contains(type) || completion.contains("password")
            || completion.contains("one-time-code") || completion.split(separator: " ").contains { $0.hasPrefix("cc-") }
    }
    public static func requiresHandoff(_ label: String) -> Bool {
        label.range(of: #"(?i)\b(pay now|place order|confirm purchase|buy now|accept terms|sign agreement|delete account|reset password|verify captcha)\b"#, options: .regularExpression) != nil
    }
    public static let configuration = """
    approval_policy = "never"
    default_permissions = "moon-browser"
    web_search = "disabled"
    project_doc_max_bytes = 0
    cli_auth_credentials_store = "file"
    [permissions.moon-browser.filesystem]
    ":root" = "deny"
    ":minimal" = "read"
    [permissions.moon-browser.network]
    enabled = false
    [features]
    shell_tool = false
    unified_exec = false
    view_image = false
    image_generation = false
    apps = false
    plugins = false
    multi_agent = false
    js_repl = false
    code_mode_host = false
    [features.code_mode]
    enabled = false
    direct_only_tool_namespaces = ["moon"]
    [shell_environment_policy]
    inherit = "none"
    """
}
