import AppKit
import SwiftUI
import TrainCore

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    let stats: () -> Stats

    @SwiftUI.State private var launchAtLogin = false
    @SwiftUI.State private var runningApps: [TrainCore.App] = []

    var body: some View {
        Form {
            Section {
                Stepper(value: $prefs.carIntervalMinutes, in: 1...30) {
                    HStack {
                        Text("Minutes per car")
                        Spacer()
                        Text("\(prefs.carIntervalMinutes)").foregroundColor(.secondary).monospacedDigit()
                    }
                }
                Stepper(value: $prefs.graceSeconds, in: 0...15) {
                    HStack {
                        Text("Grace period when switching")
                        Spacer()
                        Text(prefs.graceSeconds == 0 ? "none" : "\(prefs.graceSeconds) s").foregroundColor(.secondary).monospacedDigit()
                    }
                }
                Stepper(value: $prefs.idleMinutes, in: 2...60) {
                    HStack {
                        Text("Park at the station after")
                        Spacer()
                        Text("\(prefs.idleMinutes) min idle").foregroundColor(.secondary).monospacedDigit()
                    }
                }
            } header: {
                Text("Timetable")
            } footer: {
                Text("Switch away and come back inside the grace period and the train only wobbles.")
            }

            Section {
                Toggle("Notification banners derail the train", isOn: $prefs.derailOnNotification)
            } header: {
                Text("Derailments")
            } footer: {
                Text("Banners are detected from the window list; nothing in them is read. Turn on a macOS Focus and only you can derail the train.")
            }

            Section {
                if prefs.crew.isEmpty {
                    Text("No crew yet. Crew apps ride along without derailing the train, for example a terminal next to your editor.")
                        .foregroundColor(.secondary)
                }
                ForEach(prefs.crew, id: \.self) { bundleID in
                    HStack {
                        Text(displayName(for: bundleID))
                        Spacer()
                        Text(bundleID).foregroundColor(.secondary).font(.caption)
                        Button {
                            prefs.crew.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Menu("Add a running app…") {
                    ForEach(runningApps.filter { !prefs.crew.contains($0.bundleID) }, id: \.bundleID) { app in
                        Button(app.name) { prefs.crew.append(app.bundleID) }
                    }
                }
                .onAppear(perform: refreshRunningApps)
            } header: {
                Text("Crew")
            }

            Section {
                Toggle("Show the train on screen", isOn: $prefs.showTrain)
                Picker("Size", selection: $prefs.trainSize) {
                    ForEach(TrainSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Fade back when nothing is happening", isOn: $prefs.fadeWhenQuiet)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Events bring the train forward for a few seconds, then it settles into the background.")
            }

            Section {
                Toggle("Whistles, clacks and crashes", isOn: $prefs.soundEnabled)
                Toggle("Chugging while the train moves", isOn: $prefs.chugging)
            } header: {
                Text("Sound")
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { value in
                        prefs.launchesAtLogin = value
                        launchAtLogin = prefs.launchesAtLogin
                    }
                ))
            } header: {
                Text("Startup")
            }

            Section {
                let s = stats()
                row("Cars coupled", "\(s.totalCars)")
                row("Trains run", "\(s.totalRuns)")
                row("Derailments", "\(s.totalDerails)")
                if let best = s.bestRun {
                    row("Best run", "\(best.cars) cars · \(ShareText.format(best.duration)) in \(best.app.name)")
                }
                HStack {
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                        .foregroundColor(.secondary)
                    Spacer()
                    Link("GitHub", destination: URL(string: ShareText.repoURL)!)
                }
            } header: {
                Text("Logbook")
            } footer: {
                Text("Everything stays on this Mac. There is no network code in Train of Thought.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 820)
        .onAppear { launchAtLogin = prefs.launchesAtLogin }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(.secondary).multilineTextAlignment(.trailing)
        }
    }

    private func refreshRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map(TrainCore.App.init)
            .filter { !Rules.defaultPassengers.contains($0.bundleID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }
}

/// Hosts the settings view in a regular window and brings the app forward
/// while it is open. Train of Thought is a passenger, so opening it does
/// not derail anything.
final class SettingsWindowController {
    private var window: NSWindow?

    func show(prefs: Preferences, stats: @escaping () -> Stats) {
        if window == nil {
            let view = SettingsView(prefs: prefs, stats: stats)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Train of Thought"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
