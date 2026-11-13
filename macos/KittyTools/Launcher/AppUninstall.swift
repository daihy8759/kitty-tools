// 启动器卸载应用时查找可选的关联文件。

import AppKit

enum AppUninstall {
  static func canUninstall(
    _ item: LauncherItem, currentApp: URL = Bundle.main.bundleURL,
    currentBundleID: String? = Bundle.main.bundleIdentifier
  ) -> Bool {
    guard item.kind == .app, item.target.hasPrefix("/") else { return false }
    let url = URL(filePath: item.target).standardizedFileURL
    guard url.pathExtension.lowercased() == "app",
      !url.deletingLastPathComponent().pathComponents.contains(where: {
        $0.lowercased().hasSuffix(".app")
      }),
      (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
    else { return false }
    let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
    let ownPath = currentApp.resolvingSymlinksInPath().standardizedFileURL.path
    let bundleID = item.appBundleID ?? Bundle(url: url)?.bundleIdentifier
    return !url.path.hasPrefix("/System/") && !resolved.hasPrefix("/System/")
      && resolved != ownPath
      && !(bundleID != nil
        && bundleID?.caseInsensitiveCompare(currentBundleID ?? "") == .orderedSame)
  }

  static func relatedFiles(
    bundleID: String?, otherBundleIDs: [String], library: URL
  ) -> [URL] {
    guard let bundleID, !bundleID.isEmpty,
      bundleID.unicodeScalars.allSatisfy({
        CharacterSet(
          charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"
        )
        .contains($0)
      }),
      bundleID.split(separator: ".").count >= 2,
      !otherBundleIDs.contains(where: { $0.caseInsensitiveCompare(bundleID) == .orderedSame })
    else { return [] }
    let paths = [
      ("Application Support", bundleID),
      ("Caches", bundleID),
      ("Containers", bundleID),
      ("HTTPStorages", bundleID),
      ("WebKit", bundleID),
      ("Logs", bundleID),
      ("Application Scripts", bundleID),
      ("Preferences", bundleID + ".plist"),
      ("Saved Application State", bundleID + ".savedState"),
    ]
    return paths.compactMap { directory, name in
      let url = library.appending(path: directory, directoryHint: .isDirectory).appending(
        path: name)
      guard FileManager.default.fileExists(atPath: url.path),
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false
      else { return nil }
      return url
    }
  }

  static func quit(_ url: URL) async -> Bool {
    let path = url.resolvingSymlinksInPath().standardizedFileURL.path
    let running = NSWorkspace.shared.runningApplications.filter {
      $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == path && !$0.isTerminated
    }
    for app in running where !app.terminate() { return false }
    for _ in 0..<50 {
      if running.allSatisfy(\.isTerminated) { return true }
      try? await Task.sleep(for: .milliseconds(100))
    }
    return running.allSatisfy(\.isTerminated)
  }
}
