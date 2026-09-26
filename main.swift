import Foundation
import CoreLocation
import AppKit
import MapKit
import Security
import UniformTypeIdentifiers

var apiKey: String = ""

// MARK: - Keychain

let keychainService = "uk.g0fqb.gridradiolocator"
let keychainAccount = "grid.radio-api-key"

func keychainLoadAPIKey() -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: keychainAccount,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data, let str = String(data: data, encoding: .utf8) else {
        return nil
    }
    return str
}

func keychainSaveAPIKey(_ key: String) {
    let data = key.data(using: .utf8)!
    let baseQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: keychainAccount,
    ]
    SecItemDelete(baseQuery as CFDictionary)
    var attributes = baseQuery
    attributes[kSecValueData as String] = data
    SecItemAdd(attributes as CFDictionary, nil)
}

// MARK: - Last-known-location cache (used as a map fallback center when detection fails entirely)

func saveLastCoord(_ coord: CLLocationCoordinate2D) {
    UserDefaults.standard.set(coord.latitude, forKey: "lastLat")
    UserDefaults.standard.set(coord.longitude, forKey: "lastLon")
}

func loadLastCoord() -> CLLocationCoordinate2D? {
    let defaults = UserDefaults.standard
    guard defaults.object(forKey: "lastLat") != nil, defaults.object(forKey: "lastLon") != nil else { return nil }
    return CLLocationCoordinate2D(latitude: defaults.double(forKey: "lastLat"), longitude: defaults.double(forKey: "lastLon"))
}

// MARK: - Data models

struct RefRow {
    let scheme: String
    let code: String
    let name: String
    let distanceKm: Double
}

struct RepeaterRow {
    let callsign: String
    let location: String
    let band: String
    let modes: String
    let status: String
    let lat: Double
    let lon: Double
}

final class UserAnnotation: MKPointAnnotation {}

final class RepeaterAnnotation: MKPointAnnotation {
    var status: String = ""
}

// MARK: - Networking

func fetchJSON(urlString: String) -> [String: Any]? {
    guard let url = URL(string: urlString) else { return nil }
    var request = URLRequest(url: url)
    request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
    request.timeoutInterval = 12
    let semaphore = DispatchSemaphore(value: 0)
    var result: [String: Any]? = nil
    let task = URLSession.shared.dataTask(with: request) { data, _, _ in
        if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            result = json
        }
        semaphore.signal()
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 15)
    return result
}

// MARK: - UI helpers

func makeLabel(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = NSFont.systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.lineBreakMode = .byWordWrapping
    return l
}

func makeLinkLabel(_ text: String, url: String, size: CGFloat = 12) -> NSTextField {
    let field = NSTextField(labelWithString: "")
    let attrStr = NSMutableAttributedString(string: text)
    let range = NSRange(location: 0, length: text.utf16.count)
    attrStr.addAttribute(.link, value: url, range: range)
    attrStr.addAttribute(.font, value: NSFont.systemFont(ofSize: size), range: range)
    field.attributedStringValue = attrStr
    field.isSelectable = true
    field.isEditable = false
    field.isBezeled = false
    field.drawsBackground = false
    field.allowsEditingTextAttributes = true
    return field
}

func showReport(title: String, message: String) {
    NSApplication.shared.setActivationPolicy(.regular)
    let alert = NSAlert()
    alert.messageText = title
    alert.alertStyle = .informational

    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 260))
    scrollView.hasVerticalScroller = true
    scrollView.borderType = .bezelBorder
    let textView = NSTextView(frame: scrollView.bounds)
    textView.string = message
    textView.isEditable = false
    textView.isSelectable = true
    textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    textView.autoresizingMask = [.width]
    scrollView.documentView = textView
    alert.accessoryView = scrollView

    alert.addButton(withTitle: "OK")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
}

func statusColor(_ status: String) -> NSColor {
    let s = status.uppercased()
    if s.contains("NOT") { return .systemRed }
    if s.contains("ACTIVE") || s.contains("OPERATIONAL") { return .systemGreen }
    return .systemGray
}

func schemeColor(_ scheme: String) -> NSColor {
    switch scheme.lowercased() {
    case "pota": return .systemGreen
    case "sota": return .systemOrange
    case "wwff": return .systemTeal
    case "bota": return .systemBrown
    case "iota": return .systemBlue
    case "wca": return .systemPurple
    default: return .systemGray
    }
}

func statChip(title: String, value: String) -> NSView {
    let container = NSView()
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    container.layer?.cornerRadius = 8
    container.layer?.borderWidth = 1
    container.layer?.borderColor = NSColor.separatorColor.cgColor

    let valueLabel = makeLabel(value, size: 17, weight: .bold)
    valueLabel.alignment = .center
    let titleLabel = makeLabel(title, size: 10, weight: .regular, color: .secondaryLabelColor)
    titleLabel.alignment = .center

    let stack = NSStackView(views: [valueLabel, titleLabel])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 2
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)

    NSLayoutConstraint.activate([
        stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
        stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        container.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
    ])
    return container
}

func chip(text: String, color: NSColor) -> NSView {
    let label = makeLabel(text, size: 10, weight: .bold, color: .white)
    label.alignment = .center
    let container = NSView()
    container.wantsLayer = true
    container.layer?.backgroundColor = color.cgColor
    container.layer?.cornerRadius = 5
    label.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(label)
    NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
        label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
        label.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
        label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3),
    ])
    return container
}

func sectionHeader(_ text: String) -> NSTextField {
    return makeLabel(text, size: 12, weight: .bold, color: .secondaryLabelColor)
}

func refRowView(_ ref: RefRow) -> NSView {
    let tag = chip(text: ref.scheme.uppercased(), color: schemeColor(ref.scheme))
    tag.setContentCompressionResistancePriority(.required, for: .horizontal)

    let name = makeLabel("\(ref.code) - \(ref.name)", size: 12)
    name.lineBreakMode = .byTruncatingTail
    name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    name.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let dist = makeLabel(String(format: "%.1f km", ref.distanceKm), size: 11, color: .secondaryLabelColor)
    dist.setContentCompressionResistancePriority(.required, for: .horizontal)
    dist.setContentHuggingPriority(.required, for: .horizontal)

    let row = NSStackView(views: [tag, name, dist])
    row.orientation = .horizontal
    row.distribution = .fill
    row.spacing = 8
    row.alignment = .centerY
    row.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
    return row
}

// MARK: - Repeater table

final class RepeaterTableSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var rows: [RepeaterRow] = []

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let r = rows[row]
        let identifier = tableColumn?.identifier.rawValue ?? ""
        let cell = NSView()

        switch identifier {
        case "status":
            let dot = NSView(frame: NSRect(x: 4, y: 6, width: 8, height: 8))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = statusColor(r.status).cgColor
            dot.layer?.cornerRadius = 4
            cell.addSubview(dot)
        case "callsign":
            let l = makeLabel(r.callsign, size: 12, weight: .semibold)
            l.frame = NSRect(x: 4, y: 1, width: (tableColumn?.width ?? 100) - 8, height: 18)
            cell.addSubview(l)
        case "location":
            let l = makeLabel(r.location, size: 12)
            l.frame = NSRect(x: 4, y: 1, width: (tableColumn?.width ?? 100) - 8, height: 18)
            cell.addSubview(l)
        case "band":
            let l = makeLabel(r.band, size: 12)
            l.frame = NSRect(x: 4, y: 1, width: (tableColumn?.width ?? 100) - 8, height: 18)
            cell.addSubview(l)
        case "modes":
            let l = makeLabel(r.modes, size: 12, color: .secondaryLabelColor)
            l.frame = NSRect(x: 4, y: 1, width: (tableColumn?.width ?? 100) - 8, height: 18)
            cell.addSubview(l)
        default:
            break
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 22 }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, CLLocationManagerDelegate, NSWindowDelegate, MKMapViewDelegate {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    let locationManager = CLLocationManager()
    let tableSource = RepeaterTableSource()

    var statusLabel: NSTextField!
    var spinner: NSProgressIndicator!
    var loadingView: NSView!
    var contentView: NSView!

    var headerLocator: NSTextField!
    var headerCoord: NSTextField!
    var statChipsContainer: NSStackView!
    var mapView: MKMapView!
    var refsStack: NSStackView!
    var refsScroll: NSScrollView!
    var tableView: NSTableView!
    var refreshButton: NSButton!
    var editLocationButton: NSButton!
    var dmrLookupButton: NSButton!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window.title = "GridRadio Locator"
        window.center()
        window.delegate = self
        buildUI()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if ensureAPIKey() {
            startLookup()
        } else {
            statusLabel.stringValue = "No API key set. Relaunch the app and enter one when prompted."
            spinner.stopAnimation(nil)
        }
    }

    func ensureAPIKey() -> Bool {
        if let key = keychainLoadAPIKey(), !key.isEmpty {
            apiKey = key
            return true
        }
        let alert = NSAlert()
        alert.messageText = "grid.radio API Key"
        alert.informativeText = "This app needs a free grid.radio API key. It's stored in your macOS Keychain, not in this app's code, so it's safe to share this source."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let linkLabel = makeLinkLabel("Don't have one? Create a key at grid.radio/developer", url: "https://grid.radio/developer/")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "gr_xxxxxxxxxxxxxxxxxxxxxxxx"
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let accessory = NSStackView(views: [linkLabel, field])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 8
        alert.accessoryView = accessory
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        keychainSaveAPIKey(key)
        apiKey = key
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return true
    }

    // MARK: Map annotations

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is UserAnnotation {
            let id = "user"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.markerTintColor = .systemBlue
            view.glyphImage = NSImage(systemSymbolName: "location.fill", accessibilityDescription: nil)
            view.canShowCallout = true
            view.displayPriority = .required
            view.collisionMode = .none
            return view
        }
        if let repAnn = annotation as? RepeaterAnnotation {
            let id = "repeater"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.markerTintColor = statusColor(repAnn.status)
            view.glyphImage = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: nil)
            view.canShowCallout = true
            view.displayPriority = .required
            view.collisionMode = .none
            return view
        }
        return nil
    }

    // MARK: UI construction

    func buildUI() {
        let root = NSView(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        window.contentView = root

        // Loading state
        loadingView = NSView(frame: root.bounds)
        loadingView.autoresizingMask = [.width, .height]
        spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.sizeToFit()
        statusLabel = makeLabel("Getting your location...", size: 13, color: .secondaryLabelColor)

        let loadingStack = NSStackView(views: [spinner, statusLabel])
        loadingStack.orientation = .vertical
        loadingStack.alignment = .centerX
        loadingStack.spacing = 12
        loadingStack.translatesAutoresizingMaskIntoConstraints = false
        loadingView.addSubview(loadingStack)
        NSLayoutConstraint.activate([
            loadingStack.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            loadingStack.centerYAnchor.constraint(equalTo: loadingView.centerYAnchor),
        ])
        root.addSubview(loadingView)
        spinner.startAnimation(nil)

        // Content state (built now, populated later, hidden until ready)
        contentView = NSView(frame: root.bounds)
        contentView.autoresizingMask = [.width, .height]
        contentView.isHidden = true
        root.addSubview(contentView)

        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: nil) {
            img.isTemplate = true
            iconView.image = img
        }
        iconView.contentTintColor = .controlAccentColor

        headerLocator = makeLabel("--", size: 30, weight: .bold)
        headerCoord = makeLabel("", size: 12, color: .secondaryLabelColor)

        let headerTextStack = NSStackView(views: [headerLocator, headerCoord])
        headerTextStack.orientation = .vertical
        headerTextStack.alignment = .leading
        headerTextStack.spacing = 2

        let headerStack = NSStackView(views: [iconView, headerTextStack])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 12
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 36).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 36).isActive = true

        statChipsContainer = NSStackView(views: [])
        statChipsContainer.orientation = .horizontal
        statChipsContainer.spacing = 10
        statChipsContainer.distribution = .fillEqually

        mapView = MKMapView()
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.delegate = self
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.heightAnchor.constraint(equalToConstant: 200).isActive = true
        mapView.layer?.cornerRadius = 10
        mapView.wantsLayer = true
        mapView.layer?.cornerRadius = 10
        mapView.layer?.masksToBounds = true

        let mapClickGesture = NSClickGestureRecognizer(target: self, action: #selector(mapWasClicked(_:)))
        mapView.addGestureRecognizer(mapClickGesture)

        refsStack = NSStackView(views: [])
        refsStack.orientation = .vertical
        refsStack.alignment = .leading
        refsStack.spacing = 6
        refsStack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        refsStack.translatesAutoresizingMaskIntoConstraints = false

        let refsScroll = NSScrollView()
        refsScroll.hasVerticalScroller = true
        refsScroll.borderType = .lineBorder
        refsScroll.translatesAutoresizingMaskIntoConstraints = false
        refsScroll.heightAnchor.constraint(equalToConstant: 140).isActive = true
        refsScroll.documentView = refsStack
        NSLayoutConstraint.activate([
            refsStack.topAnchor.constraint(equalTo: refsScroll.contentView.topAnchor),
            refsStack.leadingAnchor.constraint(equalTo: refsScroll.contentView.leadingAnchor),
            refsStack.trailingAnchor.constraint(equalTo: refsScroll.contentView.trailingAnchor),
            refsStack.widthAnchor.constraint(equalTo: refsScroll.contentView.widthAnchor),
        ])
        self.refsScroll = refsScroll

        tableView = NSTableView()
        tableView.dataSource = tableSource
        tableView.delegate = tableSource
        tableView.headerView = NSTableHeaderView()
        tableView.rowSizeStyle = .custom
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = []

        let columns: [(String, String, CGFloat)] = [
            ("status", "", 20),
            ("callsign", "Callsign", 90),
            ("location", "Location", 130),
            ("band", "Band", 60),
            ("modes", "Modes", 110),
        ]
        for (identifier, title, width) in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            col.title = title
            col.width = width
            tableView.addTableColumn(col)
        }

        let tableScroll = NSScrollView()
        tableScroll.documentView = tableView
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .lineBorder
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.heightAnchor.constraint(equalToConstant: 220).isActive = true

        refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshTapped))
        refreshButton.bezelStyle = .rounded

        editLocationButton = NSButton(title: "Edit Location...", target: self, action: #selector(editLocationTapped))
        editLocationButton.bezelStyle = .rounded

        dmrLookupButton = NSButton(title: "Look Up DMR ID...", target: self, action: #selector(dmrLookupTapped))
        dmrLookupButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [refreshButton, editLocationButton, dmrLookupButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let mainStack = NSStackView(views: [
            headerStack,
            statChipsContainer,
            mapView,
            sectionHeader("NEAREST AWARD REFERENCES"),
            refsScroll,
            sectionHeader("NEARBY REPEATERS (~20 KM)"),
            tableScroll,
            buttonRow,
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let outerScroll = NSScrollView()
        outerScroll.hasVerticalScroller = true
        outerScroll.hasHorizontalScroller = false
        outerScroll.autohidesScrollers = true
        outerScroll.drawsBackground = false
        outerScroll.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(outerScroll)

        NSLayoutConstraint.activate([
            outerScroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            outerScroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            outerScroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            outerScroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        outerScroll.documentView = mainStack
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: outerScroll.contentView.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: outerScroll.contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: outerScroll.contentView.trailingAnchor),
            mainStack.widthAnchor.constraint(equalTo: outerScroll.contentView.widthAnchor),
        ])
        mapView.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        tableScroll.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        refsScroll.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        statChipsContainer.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
    }

    @objc func refreshTapped() {
        contentView.isHidden = true
        loadingView.isHidden = false
        statusLabel.stringValue = "Getting your location..."
        spinner.startAnimation(nil)
        startLookup()
    }

    @objc func editLocationTapped() {
        let alert = NSAlert()
        alert.messageText = "Set Location Manually"
        alert.informativeText = "Enter a Maidenhead locator (e.g. IO93oc) or coordinates as \"lat,lon\" (e.g. 53.10,-0.79)."
        alert.addButton(withTitle: "Use This Location")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "IO93oc or 53.10,-0.79"
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        locationManager.stopUpdatingLocation()
        locationResolved = true // block any pending auto-detect from overwriting this

        contentView.isHidden = true
        loadingView.isHidden = false
        statusLabel.stringValue = "Looking up \"\(text)\"..."
        spinner.startAnimation(nil)

        DispatchQueue.global(qos: .userInitiated).async {
            var resolvedCoord: CLLocationCoordinate2D? = nil

            let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                resolvedCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else if let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let geo = fetchJSON(urlString: "https://api.grid.radio/v1/geo?maidenhead=\(encoded)"),
                      let coords = geo["coordinates"] as? [String: Any],
                      let decimal = coords["decimal"] as? [String: Any],
                      let lat = decimal["latitude"] as? Double,
                      let lon = decimal["longitude"] as? Double {
                resolvedCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }

            DispatchQueue.main.async {
                guard let coord = resolvedCoord else {
                    self.showError("Could not understand \"\(text)\" as a locator or coordinates.")
                    return
                }
                self.loadData(for: coord, sourceLabel: "Manual entry")
            }
        }
    }

    @objc func dmrLookupTapped() {
        let alert = NSAlert()
        alert.messageText = "Look Up DMR ID"
        alert.informativeText = "Enter a callsign, name, city, or DMR ID to search the RadioID database."
        alert.addButton(withTitle: "Search")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "e.g. G0FQB"
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            showReport(title: "DMR ID Lookup", message: "Enter at least 2 characters to search.")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var report = "Search: \"\(query)\"\n\n"
            if let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let json = fetchJSON(urlString: "https://api.grid.radio/v1/dmrid/search?q=\(encoded)"),
               let results = json["results"] as? [[String: Any]] {
                if results.isEmpty {
                    report += "No matches found."
                } else {
                    for r in results.prefix(25) {
                        let id = r["id"].map { "\($0)" } ?? "?"
                        let callsign = r["callsign"] as? String ?? "?"
                        let name = r["name"] as? String ?? ""
                        let city = r["city"] as? String ?? ""
                        let country = r["country"] as? String ?? ""
                        report += "\(callsign)   DMR ID \(id)\n  \(name) - \(city), \(country)\n\n"
                    }
                    let total = json["total"] as? Int ?? results.count
                    if total > 25 {
                        report += "...and \(total - 25) more (refine your search to narrow this down).\n"
                    }
                }
            } else {
                report += "Could not reach grid.radio DMR ID lookup."
            }

            DispatchQueue.main.async {
                showReport(title: "DMR ID Results", message: report)
            }
        }
    }

    // MARK: Location

    var locationResolved = false
    var fallbackAttempted = false

    func startLookup() {
        locationResolved = false
        fallbackAttempted = false
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()

        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self = self, !self.locationResolved else { return }
            self.locationManager.stopUpdatingLocation()
            self.tryIPFallback(reason: "Wi-Fi/GPS location timed out")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, !locationResolved else { return }
        locationResolved = true
        manager.stopUpdatingLocation()
        DispatchQueue.main.async { self.statusLabel.stringValue = "Fetching grid.radio data..." }
        loadData(for: loc.coordinate, sourceLabel: "GPS/Wi-Fi")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !locationResolved else { return }
        manager.stopUpdatingLocation()
        tryIPFallback(reason: "Wi-Fi/GPS location unavailable (\(error.localizedDescription))")
    }

    func tryIPFallback(reason: String) {
        guard !locationResolved, !fallbackAttempted else { return }
        fallbackAttempted = true
        DispatchQueue.main.async {
            self.statusLabel.stringValue = "\(reason) - trying approximate IP-based location..."
        }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = URL(string: "https://ipapi.co/json/") else {
                self.showError("Could not get your current location, and the IP-based fallback URL was invalid.")
                return
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let semaphore = DispatchSemaphore(value: 0)
            var coord: CLLocationCoordinate2D? = nil
            let task = URLSession.shared.dataTask(with: request) { data, _, _ in
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let lat = json["latitude"] as? Double,
                   let lon = json["longitude"] as? Double {
                    coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 12)

            guard let coord = coord, !self.locationResolved else {
                DispatchQueue.main.async {
                    self.showMapFallback(reason: "Could not get your location automatically (no Wi-Fi/GPS fix, and IP-based lookup failed too). Click anywhere on the map below to set your position, or use \"Edit Location...\".")
                }
                return
            }
            self.locationResolved = true
            DispatchQueue.main.async { self.statusLabel.stringValue = "Fetching grid.radio data..." }
            self.loadData(for: coord, sourceLabel: "Approximate - IP-based")
        }
    }

    func showError(_ message: String) {
        DispatchQueue.main.async {
            self.spinner.stopAnimation(nil)
            self.statusLabel.stringValue = message
            self.statusLabel.maximumNumberOfLines = 0
            self.statusLabel.preferredMaxLayoutWidth = 380
        }
    }

    /// Shown when automatic location detection fails entirely. Rather than a dead-end error,
    /// this puts up the normal content view with an empty report and a clickable map
    /// (centered on the last known position, if any) so the user can tap their location in directly.
    func showMapFallback(reason: String) {
        spinner.stopAnimation(nil)
        loadingView.isHidden = true
        contentView.isHidden = false

        headerLocator.stringValue = "Location unknown"
        headerCoord.stringValue = reason
        headerCoord.textColor = .systemOrange
        headerCoord.maximumNumberOfLines = 0

        statChipsContainer.subviews.forEach { $0.removeFromSuperview() }
        refsStack.subviews.forEach { $0.removeFromSuperview() }
        refsStack.addView(makeLabel("Set a location to see nearby references.", size: 12, color: .secondaryLabelColor), in: .leading)
        tableSource.rows = []
        tableView.reloadData()

        mapView.removeAnnotations(mapView.annotations)
        let center = loadLastCoord() ?? CLLocationCoordinate2D(latitude: 54.5, longitude: -3.5)
        let span: CLLocationDistance = loadLastCoord() != nil ? 30000 : 900000
        mapView.setRegion(MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span), animated: false)
    }

    @objc func mapWasClicked(_ gesture: NSClickGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let point = gesture.location(in: mapView)

        // If the click landed on (or very near) an existing pin, let its own callout
        // handle the click instead of treating this as a "set my location here" tap.
        for annotation in mapView.annotations {
            let annotationPoint = mapView.convert(annotation.coordinate, toPointTo: mapView)
            let dx = annotationPoint.x - point.x
            let dy = annotationPoint.y - point.y
            if (dx * dx + dy * dy) < (22 * 22) {
                return
            }
        }

        let coord = mapView.convert(point, toCoordinateFrom: mapView)

        locationManager.stopUpdatingLocation()
        locationResolved = true

        contentView.isHidden = true
        loadingView.isHidden = false
        statusLabel.stringValue = "Fetching grid.radio data..."
        spinner.startAnimation(nil)

        loadData(for: coord, sourceLabel: "Manual entry (map click)")
    }

    // MARK: Data loading

    func loadData(for coord: CLLocationCoordinate2D, sourceLabel: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let lat = coord.latitude
            let lon = coord.longitude

            var maidenhead = "--"
            var cqZone = "?"
            var ituZone = "?"
            var region = "?"
            var gridRef = "?"
            var wabSquare = "?"

            if let geo = fetchJSON(urlString: "https://api.grid.radio/v1/geo?lat=\(lat)&lon=\(lon)") {
                maidenhead = geo["maidenhead"] as? String ?? "--"
                if let zones = geo["radioZones"] as? [String: Any] {
                    cqZone = "\(zones["cqZone"] ?? "?")"
                    ituZone = "\(zones["ituZone"] ?? "?")"
                    region = "\(zones["ituRegion"] ?? "?")"
                }
                if let grid = geo["grid"] as? [String: Any] {
                    gridRef = "\(grid["reference"] ?? "?")"
                }
                wabSquare = geo["wabSquare"] as? String ?? "?"
            }

            var refRows: [RefRow] = []
            if let nearby = fetchJSON(urlString: "https://api.grid.radio/v1/nearby?lat=\(lat)&lon=\(lon)&radius=20&limit=3"),
               let results = nearby["results"] as? [String: Any] {
                for (scheme, val) in results {
                    guard let items = val as? [[String: Any]] else { continue }
                    for r in items {
                        refRows.append(RefRow(
                            scheme: scheme,
                            code: r["reference"] as? String ?? "",
                            name: r["name"] as? String ?? "",
                            distanceKm: r["distance"] as? Double ?? 0
                        ))
                    }
                }
                refRows.sort { $0.distanceKm < $1.distanceKm }
            }

            let latDelta = 0.18
            let lonDelta = 0.18 / max(cos(lat * Double.pi / 180), 0.2)
            var repeaterRows: [RepeaterRow] = []
            if let repData = fetchJSON(urlString: "https://api.grid.radio/v1/repeaters/combined/bbox?south=\(lat - latDelta)&west=\(lon - lonDelta)&north=\(lat + latDelta)&east=\(lon + lonDelta)"),
               let features = repData["features"] as? [[String: Any]] {
                for f in features {
                    guard let props = f["properties"] as? [String: Any] else { continue }
                    guard let geometry = f["geometry"] as? [String: Any],
                          let coords = geometry["coordinates"] as? [Double], coords.count == 2 else { continue }
                    var modes: [String] = []
                    if (props["hasFM"] as? Bool) == true { modes.append("FM") }
                    if (props["hasDMR"] as? Bool) == true { modes.append("DMR") }
                    if (props["hasDStar"] as? Bool) == true { modes.append("D-Star") }
                    if let others = props["otherModes"] as? [String] { modes.append(contentsOf: others) }
                    repeaterRows.append(RepeaterRow(
                        callsign: props["callsign"] as? String ?? "?",
                        location: props["location"] as? String ?? "",
                        band: props["band"] as? String ?? "",
                        modes: modes.joined(separator: "/"),
                        status: props["status"] as? String ?? "",
                        lat: coords[1],
                        lon: coords[0]
                    ))
                }
                let here = CLLocation(latitude: lat, longitude: lon)
                repeaterRows.sort {
                    let d1 = CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: here)
                    let d2 = CLLocation(latitude: $1.lat, longitude: $1.lon).distance(from: here)
                    return d1 < d2
                }
            }

            DispatchQueue.main.async {
                self.populate(
                    coord: coord, maidenhead: maidenhead, cqZone: cqZone, ituZone: ituZone,
                    region: region, gridRef: gridRef, wabSquare: wabSquare, refs: refRows,
                    repeaters: repeaterRows, sourceLabel: sourceLabel
                )
            }
        }
    }

    func populate(coord: CLLocationCoordinate2D, maidenhead: String, cqZone: String, ituZone: String, region: String, gridRef: String, wabSquare: String, refs: [RefRow], repeaters: [RepeaterRow], sourceLabel: String) {
        saveLastCoord(coord)
        headerLocator.stringValue = maidenhead
        headerCoord.stringValue = String(format: "%.5f, %.5f   OS: %@   source: %@", coord.latitude, coord.longitude, gridRef, sourceLabel)
        headerCoord.textColor = (sourceLabel == "GPS/Wi-Fi") ? .secondaryLabelColor : .systemOrange

        statChipsContainer.subviews.forEach { $0.removeFromSuperview() }
        statChipsContainer.addView(statChip(title: "CQ ZONE", value: cqZone), in: .leading)
        statChipsContainer.addView(statChip(title: "ITU ZONE", value: ituZone), in: .leading)
        statChipsContainer.addView(statChip(title: "IARU REGION", value: region), in: .leading)
        statChipsContainer.addView(statChip(title: "WAB SQUARE", value: wabSquare), in: .leading)
        statChipsContainer.addView(statChip(title: "REPEATERS", value: "\(repeaters.count)"), in: .leading)

        let region2 = MKCoordinateRegion(center: coord, latitudinalMeters: 30000, longitudinalMeters: 30000)
        mapView.setRegion(region2, animated: false)
        mapView.removeAnnotations(mapView.annotations)

        let pin = UserAnnotation()
        pin.coordinate = coord
        pin.title = maidenhead
        pin.subtitle = "You are here"
        mapView.addAnnotation(pin)

        for r in repeaters {
            let ann = RepeaterAnnotation()
            ann.coordinate = CLLocationCoordinate2D(latitude: r.lat, longitude: r.lon)
            ann.title = r.callsign
            ann.subtitle = "\(r.location)  \(r.band)  \(r.modes)  [\(r.status)]"
            ann.status = r.status
            mapView.addAnnotation(ann)
        }

        refsStack.subviews.forEach { $0.removeFromSuperview() }
        if refs.isEmpty {
            refsStack.addView(makeLabel("No award references within range.", size: 12, color: .secondaryLabelColor), in: .leading)
        } else {
            for ref in refs {
                let row = refRowView(ref)
                refsStack.addView(row, in: .leading)
                row.widthAnchor.constraint(equalTo: refsStack.widthAnchor).isActive = true
            }
        }

        tableSource.rows = repeaters
        tableView.reloadData()

        spinner.stopAnimation(nil)
        loadingView.isHidden = true
        contentView.isHidden = false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
