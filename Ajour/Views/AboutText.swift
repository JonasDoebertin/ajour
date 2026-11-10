enum AboutText {
    static let tagline = "Quick aliases for SimpleLogin."
    static let disclaimer = "Ajour is an independent app and is not affiliated with SimpleLogin or Proton AG."

    /// The build number in parentheses is what the updater compares, so it helps when reporting a problem.
    static func version(info: [String: Any]) -> String? {
        guard let version = info["CFBundleShortVersionString"] as? String else { return nil }
        guard let build = info["CFBundleVersion"] as? String else { return "Version \(version)" }
        return "Version \(version) (\(build))"
    }
}
