// 启动器卸载应用的保护、关联文件和失败重试；废纸篓与退出操作都用替身。

import AppKit
import Carbon.HIToolbox
import Testing

@testable import KittyTools

struct AppUninstallTests {
  private func app(_ path: String, id: String? = "com.example.App") -> LauncherItem {
    LauncherItem(
      kind: .app, target: path, title: "Example", subtitle: "", names: ["example"],
      appBundleID: id)
  }

  @Test func protectsSystemAndOwnApp() throws {
    let own = URL(filePath: "/Applications/Kitty Tools.app")
    let currentID = "com.example.kitty"
    #expect(AppUninstall.canUninstall(app("/Applications/Example.app"), currentApp: own))
    #expect(
      !AppUninstall.canUninstall(
        app("/System/Applications/Example.app"), currentApp: own, currentBundleID: currentID))
    #expect(
      !AppUninstall.canUninstall(
        app(own.path), currentApp: own, currentBundleID: currentID))
    #expect(
      !AppUninstall.canUninstall(
        app("/Applications/Copy.app", id: currentID), currentApp: own, currentBundleID: currentID))
    #expect(
      !AppUninstall.canUninstall(
        app("/Applications/Parent.app/Contents/Helper.app"), currentApp: own))
    #expect(!AppUninstall.canUninstall(app("Example.app"), currentApp: own))

    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let link = directory.appending(path: "Alias.app")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: own)
    #expect(!AppUninstall.canUninstall(app(link.path), currentApp: own))
  }

  @Test func onlyFindsExactUnsharedIdentifiers() throws {
    let library = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: library) }
    let caches = library.appending(path: "Caches")
    let preferences = library.appending(path: "Preferences")
    try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
    let exact = caches.appending(path: "com.example.App")
    try FileManager.default.createDirectory(at: exact, withIntermediateDirectories: true)
    let other = caches.appending(path: "com.example.AppBeta")
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    let plist = preferences.appending(path: "com.example.App.plist")
    try Data().write(to: plist)
    let link = library.appending(path: "Logs/com.example.App")
    try FileManager.default.createDirectory(
      at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)

    let found = AppUninstall.relatedFiles(
      bundleID: "com.example.App", otherBundleIDs: [], library: library)
    #expect(Set(found) == Set([exact, plist]))
    #expect(
      AppUninstall.relatedFiles(
        bundleID: "com.example.App", otherBundleIDs: ["COM.EXAMPLE.APP"], library: library
      )
      .isEmpty)
    #expect(
      AppUninstall.relatedFiles(bundleID: "../Caches", otherBundleIDs: [], library: library).isEmpty
    )
    #expect(AppUninstall.relatedFiles(bundleID: nil, otherBundleIDs: [], library: library).isEmpty)
  }

  @Test func menuUninstallsOnlySelectedFilesAndKeepsFavorites() async throws {
    let item = app("/Applications/Example.app")
    let usage = try LauncherUsage(db: Database(path: ":memory:"))
    usage.record(item, query: "")
    _ = usage.toggleFavorite(item)
    let model = LauncherModel(usage: usage, apps: [item])
    let first = URL(filePath: "/tmp/example-cache")
    let second = URL(filePath: "/tmp/example-preferences")
    model.uninstallFiles = { _, _ in [first, second] }
    var quit: [URL] = []
    var moved: [URL] = []
    model.quitForUninstall = {
      quit.append($0)
      return true
    }
    model.recycle = { moved.append($0) }
    model.prepareForShow()
    let action = try #require(model.actions(for: item).first { $0.title == "卸载应用" })
    #expect(action.isDestructive)
    action.run()
    #expect(model.uninstall?.checked.isEmpty == true)
    #expect(model.handleCommand(#selector(NSResponder.moveDown(_:))))
    #expect(model.handleCommand(#selector(NSResponder.moveDown(_:))))
    let toggle = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
        context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
        keyCode: UInt16(kVK_Return)))
    #expect(model.handleKeyEquivalent(toggle))
    #expect(model.uninstall?.checked == Set([second]))
    model.confirmUninstall()
    for _ in 0..<100 where model.uninstall != nil { await Task.yield() }
    #expect(quit == [URL(filePath: item.target)])
    #expect(moved == [second, URL(filePath: item.target)])
    #expect(model.uninstall == nil && !model.results.contains { $0.id == item.id })
    #expect(usage.isFavorite(item))
  }

  @Test func failureDoesNotMoveAppAndCanBeRetried() async throws {
    let item = app("/Applications/Example.app")
    let model = LauncherModel(
      usage: try LauncherUsage(db: Database(path: ":memory:")), apps: [item])
    let first = URL(filePath: "/tmp/example-cache")
    let second = URL(filePath: "/tmp/example-preferences")
    model.uninstallFiles = { _, _ in [first, second] }
    model.quitForUninstall = { _ in false }
    var moved: [URL] = []
    model.recycle = { moved.append($0) }
    model.beginUninstall(item)
    model.selectUninstallFile(0)
    model.selectUninstallFile(1)
    model.confirmUninstall()
    for _ in 0..<100 where model.uninstall?.isRunning == true { await Task.yield() }
    #expect(moved.isEmpty && model.error == "应用未退出，请退出后重试")
    model.quitForUninstall = { _ in true }
    model.recycle = { url in
      if url == second { throw CocoaError(.fileWriteNoPermission) }
      moved.append(url)
    }
    model.confirmUninstall()
    for _ in 0..<100 where model.uninstall?.isRunning == true { await Task.yield() }
    #expect(moved == [first])
    #expect(model.uninstall?.files == [second])
    #expect(model.uninstall?.checked == Set([second]))
    #expect(model.error?.contains("没能移到废纸篓") == true)
    model.recycle = { moved.append($0) }
    model.confirmUninstall()
    for _ in 0..<100 where model.uninstall != nil { await Task.yield() }
    #expect(moved == [first, second, URL(filePath: item.target)])
  }
}
