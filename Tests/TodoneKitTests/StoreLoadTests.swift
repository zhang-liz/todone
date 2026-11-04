import Foundation
import Testing
@testable import TodoneKit

@Suite struct StoreLoadTests {
    private func tempStoreURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("todone-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("todone.json")
    }

    @Test func missingFileStartsFreshAndSaves() throws {
        let url = try tempStoreURL()
        let store = AppStore()
        store.load(from: url)
        #expect(store.lastSaveError == nil)

        _ = store.addTask(title: "first")
        store.saveNow()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    // A failed read used to look like a first run, so the next save replaced the
    // user's file with an empty store.
    @Test func unreadableFileIsNeverOverwritten() throws {
        let url = try tempStoreURL()
        let first = AppStore()
        first.load(from: url)
        _ = first.addTask(title: "precious")
        first.saveNow()
        let original = try Data(contentsOf: url)

        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

        let second = AppStore()
        second.load(from: url)
        #expect(second.lastSaveError != nil)
        _ = second.addTask(title: "new")
        second.saveNow()

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(try Data(contentsOf: url) == original)
    }
}
