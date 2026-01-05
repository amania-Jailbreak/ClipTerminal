import Cocoa
import Carbon

class GlobalHotKey {
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let action: () -> Void
    
    // Command + Shift + V
    // Virtual Key Code for 'V' is 0x09 (9)
    // Modifiers: cmdKey + shiftKey
    
    init(action: @escaping () -> Void) {
        self.action = action
        register()
    }
    
    deinit {
        unregister()
    }
    
    private func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let instance = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            instance.action()
            return noErr
        }, 1, &eventType, selfPointer, &eventHandler)
        
        let hotKeyID = EventHotKeyID(signature: OSType(0x1111), id: 1) // Arbitrary ID
        
        // Command (cmdKey) + Shift (shiftKey) = 0xCmd | 0xShift
        // Carbon modifiers: cmdKey = 256 (bit 8), shiftKey = 512 (bit 9) -> 768
        // Actually Carbon constants: cmdKey (55), shiftKey (56)? No, those are keycodes.
        // It's `cmdKey` constant from Carbon.
        
        // V key code is 9.
        var gEventHotKeyRef: EventHotKeyRef?
        RegisterEventHotKey(9, UInt32(cmdKey | shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &gEventHotKeyRef)
        self.hotKeyRef = gEventHotKeyRef
    }
    
    private func unregister() {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
    }
}
