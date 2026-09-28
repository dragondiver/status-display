import StatusCore
import SwiftUI

/// Die Status-Menüeinträge (Vorgaben × Dauern) als eigene View – **einmal** gebaut, genutzt in der
/// Menüleiste (`MenuContent`), im Dashboard-Etikett (`DashboardView`) und im Board-Fenster
/// (`BoardWindowController`, dort über `NSMenu` statt SwiftUI, siehe `StatusMenuFactory`).
/// Entscheidung Florian, 28.09.2026, status-display#33: keine dritte, abweichende Liste.
struct StatusMenuItems: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ForEach(StatusMenuBuilder.entries(presets: model.presets), id: \.presetID) { entry in
            Menu(entry.presetName) {
                ForEach(entry.choices, id: \.title) { choice in
                    Button(choice.title) { apply(choice, presetID: entry.presetID) }
                }
            } primaryAction: {
                model.setStatus(entry.presetID, duration: nil)
            }
        }
    }

    private func apply(_ choice: StatusMenuBuilder.DurationChoice, presetID: String) {
        if choice.untilEndOfDay {
            model.setStatusUntilEndOfDay(presetID)
        } else {
            model.setStatus(presetID, duration: choice.duration)
        }
    }
}

/// Baut dasselbe Menü als `NSMenu`, fürs Board-Fenster (AppKit, kein SwiftUI-`Menu` dort möglich).
/// Nutzt dieselbe `StatusMenuBuilder.entries`-Datenquelle wie `StatusMenuItems`.
enum StatusMenuFactory {
    @MainActor
    static func makeStatusMenu(model: AppModel) -> NSMenu {
        let menu = NSMenu()
        for entry in StatusMenuBuilder.entries(presets: model.presets) {
            let item = NSMenuItem(title: entry.presetName, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for choice in entry.choices {
                let choiceItem = NSMenuItem(title: choice.title, action: nil, keyEquivalent: "")
                choiceItem.representedObject = StatusMenuAction { [weak model] in
                    guard let model else { return }
                    if choice.untilEndOfDay {
                        model.setStatusUntilEndOfDay(entry.presetID)
                    } else {
                        model.setStatus(entry.presetID, duration: choice.duration)
                    }
                }
                choiceItem.target = choiceItem.representedObject as? StatusMenuAction
                choiceItem.action = #selector(StatusMenuAction.performAction)
                submenu.addItem(choiceItem)
            }
            item.submenu = submenu
            menu.addItem(item)
        }
        return menu
    }
}

/// Hüllt eine Closure als Zielobjekt für `NSMenuItem.action`, da `NSMenuItem` einen
/// Objective-C-Selector auf einem Objekt braucht, keine Swift-Closure direkt.
@MainActor
final class StatusMenuAction: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) { self.action = action }

    @objc func performAction() { action() }
}
