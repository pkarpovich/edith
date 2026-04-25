import AppKit
import Foundation

struct PasteboardSnapshot: Sendable, Equatable {
    struct Item: Sendable, Equatable {
        let payloads: [String: Data]
    }

    let items: [Item]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item -> Item in
            var payloads: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    payloads[type.rawValue] = data
                }
            }
            return Item(payloads: payloads)
        }
        return PasteboardSnapshot(items: items)
    }

    func apply(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let nsItems = items.map { item -> NSPasteboardItem in
            let ns = NSPasteboardItem()
            for (type, data) in item.payloads {
                ns.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return ns
        }
        pasteboard.writeObjects(nsItems)
    }
}
