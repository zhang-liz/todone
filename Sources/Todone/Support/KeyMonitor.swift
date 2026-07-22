import AppKit
import Carbon.HIToolbox
import SwiftUI
import TodoneKit

/// Single-key shortcuts (Todoist style) active when no text field has focus:
/// q = quick add, / = search, t = today, u = upcoming, i = inbox,
/// 1–4 = set priority of the selected task, e = complete, ⌫ = delete.
final class KeyMonitor {
    static let shared = KeyMonitor()
    private var monitor: Any?

    func start(store: AppStore, model: AppModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Don't steal keys from text editing or when modifiers are held.
            if event.modifierFlags.intersection([.command, .option, .control]).isEmpty == false {
                return event
            }
            if let responder = NSApp.keyWindow?.firstResponder,
               responder is NSTextView || responder is NSText {
                return event
            }
            guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return event }

            switch chars {
            case "q":
                model.showQuickAdd = true
                return nil
            case "/":
                model.showSearch = true
                return nil
            case "t":
                model.select(.today)
                return nil
            case "u":
                model.select(.upcoming)
                return nil
            case "i":
                model.select(.inbox)
                return nil
            case "e":
                if let id = model.selectedTaskID, let task = store.task(id) {
                    store.complete(task)
                    model.selectedTaskID = nil
                    return nil
                }
                return event
            case "1", "2", "3", "4":
                if let id = model.selectedTaskID, let task = store.task(id),
                   let n = Int(chars), let p = Priority(rawValue: n) {
                    store.updateTask(task) { $0.priority = p }
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }
}

/// System-wide hotkey (default ⌥Space) that brings the app forward and opens
/// Quick Add, registered via Carbon RegisterEventHotKey.
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    func register(action: @escaping () -> Void) {
        self.action = action
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerProcPtr = { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                me.action?()
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x54444E45) /* "TDNE" */, id: 1)
        // kVK_Space = 49, optionKey modifier.
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
