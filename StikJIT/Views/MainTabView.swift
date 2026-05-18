//
//  MainTabView.swift
//  StikJIT
//
//  Created by Stephen on 3/27/25.
//

import SwiftUI
import Foundation

private struct TabDescriptor: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let builder: () -> AnyView
}

extension Notification.Name {
    static let switchToTab = Notification.Name("MainTabSwitchNotification")
}

struct MainTabView: View {
    @AppStorage(TabConfiguration.storageKey) private var enabledTabIdentifiers: String = TabConfiguration.defaultRawValue
    @AppStorage("primaryTabSelection") private var selection: String = TabConfiguration.defaultIDs.first ?? "home"
    @State private var switchObserver: Any?
    @State private var detachedTab: TabDescriptor?
    @State private var didSetInitialHome = false

    private var configurableTabs: [TabDescriptor] {
        let tabs: [TabDescriptor] = [
            TabDescriptor(id: "home", title: "Apps", systemImage: "square.grid.2x2") { AnyView(HomeView()) },
            TabDescriptor(id: "scripts", title: "Scripts", systemImage: "scroll") { AnyView(ScriptListView()) },
            TabDescriptor(id: "tools", title: "Tools", systemImage: "wrench.and.screwdriver") { AnyView(ToolsView()) },
            TabDescriptor(id: "deviceinfo", title: "Device Info", systemImage: "iphone.and.arrow.forward") { AnyView(DeviceInfoView()) },
            TabDescriptor(id: "profiles", title: "App Expiry", systemImage: "calendar.badge.clock") { AnyView(ProfileView()) },
            TabDescriptor(id: "processes", title: "Processes", systemImage: "rectangle.stack.person.crop") { AnyView(ProcessInspectorView()) },
            TabDescriptor(id: "location", title: "Location", systemImage: "location") { AnyView(LocationSimulationView()) }
        ]
        return tabs
    }
    
    private var availableTabs: [TabDescriptor] {
        configurableTabs
    }
    
    private let settingsTab = TabDescriptor(id: "settings", title: "Settings", systemImage: "gearshape.fill") {
        AnyView(SettingsView())
    }
    
    private var selectedTabDescriptors: [TabDescriptor] {
        let ids = TabConfiguration.sanitize(raw: enabledTabIdentifiers)
        return ids.compactMap { id in
            availableTabs.first(where: { $0.id == id })
        }
    }
    
    private func ensureSelectionIsValid() {
        let ids = displayTabs.map { $0.id }
        if ids.contains(selection) {
            return
        }
        selection = ids.first ?? settingsTab.id
    }

    private func handleURL(_ url: URL) {
        guard let host = url.host()?.lowercased() else { return }

        switch host {
        case "simulate-location", "set-location":
            simulateLocation(from: url)
        case "location", "location-simulation":
            if coordinate(from: url) == nil {
                openTab(id: "location")
            } else {
                simulateLocation(from: url)
            }
        case "clear-location", "stop-location":
            clearSimulatedLocation()
        default:
            break
        }
    }

    private func openTab(id: String) {
        if displayTabs.contains(where: { $0.id == id }) {
            selection = id
        } else if let descriptor = availableTabs.first(where: { $0.id == id }) {
            detachedTab = descriptor
        }
    }

    private func simulateLocation(from url: URL) {
        guard let coordinate = coordinate(from: url) else {
            showAlert(
                title: "Invalid Location URL",
                message: "Use stikdebug://simulate-location?lat=37.3349&lon=-122.0090",
                showOk: true
            )
            return
        }

        guard coordinateIsValid(latitude: coordinate.latitude, longitude: coordinate.longitude) else {
            showAlert(
                title: "Invalid Coordinates",
                message: "Latitude must be between -90 and 90. Longitude must be between -180 and 180.",
                showOk: true
            )
            return
        }

        let pairingFile = PairingFileStore.prepareURL()
        guard FileManager.default.fileExists(atPath: pairingFile.path) else {
            showAlert(
                title: "Pairing File Required",
                message: "Import a pairing file before simulating location from a URL.",
                showOk: true
            )
            return
        }

        LocationSimulationCommandQueue.shared.async {
            let code = simulate_location(
                DeviceConnectionContext.targetIPAddress,
                coordinate.latitude,
                coordinate.longitude,
                pairingFile.path
            )

            DispatchQueue.main.async {
                if code == 0 {
                    BackgroundLocationManager.shared.requestStart()
                    LogManager.shared.addInfoLog(
                        String(format: "Simulated location from URL: %.6f, %.6f", coordinate.latitude, coordinate.longitude)
                    )
                } else {
                    showAlert(
                        title: "Location Simulation Failed",
                        message: "Could not simulate location from URL (error \(code)). Make sure the device is connected and the DDI is mounted.",
                        showOk: true
                    )
                }
            }
        }
    }

    private func clearSimulatedLocation() {
        LocationSimulationCommandQueue.shared.async {
            let code = clear_simulated_location()
            DispatchQueue.main.async {
                if code == 0 {
                    BackgroundLocationManager.shared.requestStop()
                    LogManager.shared.addInfoLog("Cleared simulated location from URL")
                } else {
                    showAlert(
                        title: "Clear Location Failed",
                        message: "Could not clear simulated location from URL (error \(code)).",
                        showOk: true
                    )
                }
            }
        }
    }

    private func coordinate(from url: URL) -> (latitude: Double, longitude: Double)? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        func queryValue(_ names: [String]) -> String? {
            for name in names {
                if let value = queryItems.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value {
                    return value
                }
            }
            return nil
        }

        if let latitudeText = queryValue(["lat", "latitude"]),
           let longitudeText = queryValue(["lon", "lng", "long", "longitude"]),
           let latitude = Double(latitudeText.trimmingCharacters(in: .whitespacesAndNewlines)),
           let longitude = Double(longitudeText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return (latitude, longitude)
        }

        let coordinateText = queryValue(["coordinate", "coordinates", "coords", "q", "ll"])
            ?? components?.path
            ?? ""
        let values = numbers(in: coordinateText)
        guard values.count >= 2 else { return nil }
        return (values[0], values[1])
    }

    private func coordinateIsValid(latitude: Double, longitude: Double) -> Bool {
        (-90.0...90.0).contains(latitude) && (-180.0...180.0).contains(longitude)
    }

    private func numbers(in text: String) -> [Double] {
        let pattern = #"[-+]?(?:\d+(?:\.\d*)?|\.\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return Double(text[matchRange])
        }
    }
    
    private var displayTabs: [TabDescriptor] {
        var tabs = ["home", "tools"].compactMap { id in
            configurableTabs.first(where: { $0.id == id })
        }
        tabs.insert(settingsTab, at: min(2, tabs.count))
        return tabs
    }
    
    var body: some View {
        ZStack {
            // Allow global themed background to show
            Color.clear.ignoresSafeArea()
            
            // Main tabs
            TabView(selection: $selection) {
                ForEach(displayTabs) { descriptor in
                    descriptor.builder()
                        .tabItem { Label(descriptor.title, systemImage: descriptor.systemImage) }
                        .tag(descriptor.id)
                }
            }
            .onAppear {
                enabledTabIdentifiers = TabConfiguration.serialize(TabConfiguration.sanitize(raw: enabledTabIdentifiers))
                ensureSelectionIsValid()
                if !didSetInitialHome {
                    if selectedTabDescriptors.contains(where: { $0.id == "home" }) {
                        selection = "home"
                    } else if let descriptor = availableTabs.first(where: { $0.id == "home" }) {
                        detachedTab = descriptor
                    }
                    didSetInitialHome = true
                }
                switchObserver = NotificationCenter.default.addObserver(forName: .switchToTab, object: nil, queue: .main) { note in
                    guard let id = note.object as? String else { return }
                    openTab(id: id)
                }
            }
            .onDisappear {
                if let observer = switchObserver {
                    NotificationCenter.default.removeObserver(observer)
                    switchObserver = nil
                }
            }
            .onChange(of: enabledTabIdentifiers) { _, _ in
                ensureSelectionIsValid()
            }
            .onOpenURL { url in
                handleURL(url)
            }
            .sheet(item: $detachedTab) { descriptor in
                NavigationStack {
                    descriptor.builder()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") {
                                    detachedTab = nil
                                }
                            }
                        }
                }
            }
        }
    }

}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
