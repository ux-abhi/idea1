// © Pexilim
import BlinkKit
import SwiftUI

/// Phase 0 placeholder: who and where you're connected, last sync, sign out.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let host = model.server?.config.host ?? "your server"
        Form {
            Section {
                switch model.status {
                case .checking:
                    Label("Checking \(host)…", systemImage: "arrow.triangle.2.circlepath")
                case .connected:
                    Label("Connected to \(host) as \(model.email ?? "you")", systemImage: "checkmark.circle")
                case .unreachable:
                    Label("Can't reach \(host) right now. Blink will try again when you open it.",
                          systemImage: "wifi.exclamationmark")
                    Button("Try again") { Task { await model.refresh() } }
                }
                if let lastSync = model.lastSync {
                    LabeledContent("Last sync") { Text(lastSync, format: .relative(presentation: .named)) }
                } else {
                    LabeledContent("Last sync", value: "Not yet")
                }
            }
            Section {
                switch model.calendarAccess {
                case .notAsked:
                    Button("Connect Calendar") { Task { await model.connectCalendar() } }
                case .denied:
                    Label("Calendar access is off", systemImage: "calendar.badge.exclamationmark")
                    Button("Open System Settings", action: openPrivacySettings)
                case .granted:
                    TimelineView(.everyMinute) { context in
                        LabeledContent("Next", value: model.agenda.statusLine(now: context.date))
                    }
                }
            } header: {
                Text("Calendar")
            } footer: {
                if model.calendarAccess != .granted {
                    Text("Blink reads the calendars and reminders on this device to show what's next. Turn on full access for both.")
                }
            }
            Section {
                NavigationLink("Blink's eyes") { EyesPreview() }
            }
            Section {
                Button("Sign out", role: .destructive) { Task { await model.signOut() } }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Blink")
        .task { await model.refresh() }
    }

    private func openPrivacySettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }
}
