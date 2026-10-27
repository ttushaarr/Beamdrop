import SwiftUI
import AppKit

public class KdeConnectViewModel: ObservableObject {
    @Published public var urlToOpen: String = ""
    @Published public var showUrlSuccess: Bool = false
    @Published public var snapshotError: String? = nil
    @Published public var showWebcamCopied: Bool = false
    public init() {}
}

public struct KdeConnectView: View {
    @StateObject private var vm = KdeConnectViewModel()
    @ObservedObject var kde = KdeConnectService.shared
    @ObservedObject var battery = BatteryService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            // Incoming Call Alert Banner
            if let call = kde.activeIncomingCall {
                IncomingCallAlertBanner(call: call, kde: kde)
            }
            
            // Hero Status Banner
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(kde.isConnected ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: kde.isConnected ? "link.circle.fill" : "link.badge.plus")
                        .font(.system(size: 22))
                        .foregroundColor(kde.isConnected ? .green : .orange)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(kde.isConnected ? "KDE Connect Stream Active" : "Connecting to Android Device...")
                        .font(.system(size: 15, weight: .bold))
                    Text(kde.isConnected ? "Bidirectional remote control, notifications, camera & battery sync active" : "Ensure tablet is on same Wi-Fi with BeamDrop open")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if kde.isConnected {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Live SSE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // Battery Status Row
            HStack(spacing: 14) {
                // Tablet Battery Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "ipad.landscape")
                            .foregroundColor(.blue)
                        Text("Android Battery")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        if battery.tabletBattery?.isCharging == true {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 11))
                        }
                    }
                    
                    if let tablet = battery.tabletBattery {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(tablet.percentage)%")
                                .font(.system(size: 24, weight: .bold))
                            Text(tablet.isCharging ? "Charging ⚡" : "On Battery")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Connecting...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                
                // Mac Battery Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "laptopcomputer")
                            .foregroundColor(.purple)
                        Text("MacBook Battery")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        if battery.macBattery?.isCharging == true {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 11))
                        }
                    }
                    
                    if let mac = battery.macBattery {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(mac.percentage)%")
                                .font(.system(size: 24, weight: .bold))
                            Text(mac.isCharging ? "Charging ⚡" : "On Battery")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("--%")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
            }
            
            // Continuity Camera Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "camera.fill")
                        .foregroundColor(.cyan)
                    Text("Continuity Camera / Live Capture")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    Button(action: {
                        Task {
                            vm.snapshotError = nil
                            do {
                                _ = try await kde.captureContinuitySnapshot()
                            } catch {
                                await MainActor.run {
                                    vm.snapshotError = error.localizedDescription
                                }
                            }
                        }
                    }) {
                        HStack {
                            if kde.isTakingSnapshot {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Snapping...")
                            } else {
                                Image(systemName: "camera.aperture")
                                Text("Take Photo from Android")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(kde.isTakingSnapshot)
                    
                    if let snapshotURL = kde.lastSnapshotURL {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([snapshotURL])
                        }
                        .buttonStyle(.bordered)
                        
                        Text("Saved: \(snapshotURL.lastPathComponent)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                if let err = vm.snapshotError {
                    Text("Error: \(err)")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // Wireless HD Webcam Card
            WebcamControlCardView(vm: vm, kde: kde)
            
            // 1-Click Wireless ADB Card
            AdbControlCardView()
            
            // Custom Mac Script Launchers Card
            CustomScriptLaunchersCardView()
            
            // Find My Device (Ring Tablet) Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(.red)
                    Text("Find My Device")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                }
                
                HStack {
                    Text("Lost your tablet under a couch or in another room? Sound full-volume alarm.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if kde.isTabletRinging {
                        Button(action: { kde.stopTabletRinging() }) {
                            HStack {
                                Image(systemName: "stop.circle.fill")
                                Text("Stop Alarm")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        Button(action: { kde.ringTablet() }) {
                            HStack {
                                Image(systemName: "bell.badge.fill")
                                Text("Ring Android Device")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // Send URL to Tablet Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "safari.fill")
                        .foregroundColor(.blue)
                    Text("Send Web Link to Tablet")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                }
                
                HStack {
                    TextField("Enter URL (e.g. https://youtube.com)", text: $vm.urlToOpen)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Open on Tablet") {
                        let raw = vm.urlToOpen.trimmingCharacters(in: .whitespaces)
                        let target = raw.hasPrefix("http") ? raw : "https://\(raw)"
                        kde.openUrlOnTablet(target)
                        vm.urlToOpen = ""
                        vm.showUrlSuccess = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            vm.showUrlSuccess = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.urlToOpen.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                
                if vm.showUrlSuccess {
                    Text("✓ Web page opened instantly on tablet!")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // Mirrored Android Notifications Feed with Quick Reply
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.purple)
                    Text("Mirrored Notifications (\(kde.recentNotifications.count))")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    if !kde.recentNotifications.isEmpty {
                        Button("Clear") {
                            kde.recentNotifications.removeAll()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                    }
                }
                
                if kde.recentNotifications.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "bell.slash")
                                .foregroundColor(.secondary)
                            Text("No incoming notifications yet")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 16)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(kde.recentNotifications.prefix(5)) { notif in
                            NotificationRowView(notif: notif, kde: kde)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
    }
}

public struct NotificationRowView: View {
    let notif: KdeNotification
    let kde: KdeConnectService
    @State private var replyText: String = ""
    @State private var isSendingReply: Bool = false
    @State private var replySent: Bool = false
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "app.badge.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.purple)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(notif.appName)
                            .font(.system(size: 11, weight: .bold))
                        Spacer()
                        Text(Date(timeIntervalSince1970: TimeInterval(notif.timestamp / 1000)), style: .time)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    Text(notif.title)
                        .font(.system(size: 11, weight: .semibold))
                    Text(notif.text)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            // Inline Quick Reply for notifications supporting RemoteInput
            if notif.canReply == true, let key = notif.key, !key.isEmpty {
                HStack(spacing: 8) {
                    TextField("Quick Reply...", text: $replyText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    
                    Button(action: {
                        let text = replyText.trimmingCharacters(in: .whitespaces)
                        guard !text.isEmpty else { return }
                        isSendingReply = true
                        Task {
                            let ok = await kde.replyToNotification(key: key, text: text)
                            await MainActor.run {
                                isSendingReply = false
                                if ok {
                                    replySent = true
                                    replyText = ""
                                }
                            }
                        }
                    }) {
                        if isSendingReply {
                            ProgressView().scaleEffect(0.6)
                        } else if replySent {
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                        } else {
                            Text("Reply")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty || isSendingReply)
                }
                .padding(.leading, 34)
            }
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Incoming Call Alert Banner

public struct IncomingCallAlertBanner: View {
    let call: KdeNotification
    let kde: KdeConnectService
    @State private var isMuted: Bool = false
    @State private var isDeclining: Bool = false
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "phone.badge.waveform.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.green)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("📞 Incoming Phone Call")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green)
                        Text("• Ringing")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Text(call.title.isEmpty ? (call.phoneNumber ?? "Incoming Call") : call.title)
                        .font(.system(size: 16, weight: .bold))
                    if let phone = call.phoneNumber, !phone.isEmpty, phone != call.title {
                        Text(phone)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Mute Ringer
                Button(action: {
                    Task {
                        let ok = await kde.muteRinger()
                        await MainActor.run { isMuted = ok }
                    }
                }) {
                    Label(isMuted ? "Ringer Muted" : "Mute Ringer", systemImage: isMuted ? "speaker.slash.fill" : "bell.slash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                // Decline Call
                Button(action: {
                    isDeclining = true
                    Task {
                        _ = await kde.declineCall()
                        await MainActor.run { isDeclining = false }
                    }
                }) {
                    if isDeclining {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Label("Decline", systemImage: "phone.down.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
            
            // Quick Decline with Message Pills
            VStack(alignment: .leading, spacing: 6) {
                Text("Decline with Quick Message:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Button("💬 Can't talk right now.") {
                        Task { await kde.declineCall(message: "Can't talk right now.") }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    
                    Button("🕒 In a meeting, call back later.") {
                        Task { await kde.declineCall(message: "In a meeting, call back later.") }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    
                    Button("🚗 On my way.") {
                        Task { await kde.declineCall(message: "On my way.") }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.4), lineWidth: 1.5))
        .cornerRadius(12)
    }
}

// MARK: - Wireless HD Webcam Card

public struct WebcamControlCardView: View {
    @ObservedObject var vm: KdeConnectViewModel
    @ObservedObject var kde: KdeConnectService
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "video.fill")
                    .foregroundColor(.blue)
                Text("Wireless HD Webcam (Zoom, Meet, OBS)")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text("720p 30 FPS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            
            Text("Stream your phone or tablet's high-res camera directly into Zoom, Meet, OBS Studio, or browser.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Button(action: {
                    if let streamURL = kde.getWebcamStreamURL() {
                        WebcamWindowManager.shared.openWebcamWindow(streamURL: streamURL)
                    }
                }) {
                    HStack {
                        Image(systemName: "macwindow.badge.plus")
                        Text("Launch Live Camera Viewer")
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: {
                    if let streamURL = kde.getWebcamStreamURL() {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(streamURL.absoluteString, forType: .string)
                        vm.showWebcamCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            vm.showWebcamCopied = false
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: vm.showWebcamCopied ? "checkmark" : "doc.on.doc")
                        Text(vm.showWebcamCopied ? "Copied OBS Link!" : "Copy Stream URL (OBS / VLC)")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - 1-Click Wireless ADB Card

public struct AdbControlCardView: View {
    @ObservedObject var adb = AdbService.shared
    @State private var pairingPort: String = ""
    @State private var pairingCode: String = ""
    @State private var showPairingSheet: Bool = false
    
    private var targetHost: String {
        if let dev = DeviceDiscoveryService.shared.selectedDevice, !dev.host.isEmpty {
            return dev.host
        }
        let prefs = UserDefaults(suiteName: "com.beamdrop.BeamDrop") ?? .standard
        return prefs.string(forKey: "target_ip") ?? "192.168.1.7"
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .foregroundColor(.orange)
                Text("1-Click Wireless ADB")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                
                if let adbPath = AdbService.findAdbPath() {
                    Text("ADB: \(URL(fileURLWithPath: adbPath).lastPathComponent)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                } else {
                    Text("adb not found")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red)
                }
            }
            
            Text("Wirelessly connect and debug your Android device over Wi-Fi without typing adb connect ip:port.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Button(action: {
                    Task {
                        _ = await adb.connect(host: targetHost, port: 5555)
                    }
                }) {
                    HStack {
                        if adb.isConnecting {
                            ProgressView().scaleEffect(0.6)
                            Text("Connecting...")
                        } else {
                            Image(systemName: "wifi")
                            Text("1-Click Connect to \(targetHost):5555")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(adb.isConnecting)
                
                Button(action: { showPairingSheet.toggle() }) {
                    HStack {
                        Image(systemName: "qrcode")
                        Text("Pair with Code")
                    }
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    Task { await adb.refreshConnectedDevices() }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            
            if !adb.connectedDevices.isEmpty {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("Connected Devices: \(adb.connectedDevices.joined(separator: ", "))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                }
            }
            
            if !adb.lastOutput.isEmpty {
                Text(adb.lastOutput)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .popover(isPresented: $showPairingSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Wireless Debugging Pairing")
                    .font(.headline)
                Text("Enter the 5-digit port and 6-digit code shown in Android Developer Options > Wireless Debugging > 'Pair device with pairing code'")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("Pairing Port (e.g. 38472)", text: $pairingPort)
                    .textFieldStyle(.roundedBorder)
                TextField("6-digit Code (e.g. 123456)", text: $pairingCode)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    Button("Cancel") { showPairingSheet = false }
                    Spacer()
                    Button("Pair & Connect") {
                        if let port = Int(pairingPort.trimmingCharacters(in: .whitespaces)) {
                            let code = pairingCode.trimmingCharacters(in: .whitespaces)
                            showPairingSheet = false
                            Task {
                                let (ok, _) = await adb.pair(host: targetHost, port: port, code: code)
                                if ok {
                                    _ = await adb.connect(host: targetHost, port: 5555)
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pairingPort.isEmpty || pairingCode.isEmpty)
                }
            }
            .padding(16)
            .frame(width: 320)
        }
    }
}

// MARK: - Custom Mac Script Launchers Card

public struct CustomScriptLaunchersCardView: View {
    @ObservedObject var scriptService = CustomScriptService.shared
    @State private var showAddSheet: Bool = false
    @State private var newName: String = ""
    @State private var newCommand: String = ""
    @State private var newIcon: String = "⚡"
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.green)
                Text("Custom Mac Script Launchers (\(scriptService.scripts.count))")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                
                Button(action: { showAddSheet = true }) {
                    Label("Add Script", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
            }
            
            Text("One-tap triggers for your favorite developer shell scripts on Mac. Also accessible from tablet/phone!")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
                ForEach(scriptService.scripts) { script in
                    HStack {
                        Text(script.icon)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(script.name)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Text(script.command)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(action: {
                            Task { _ = await scriptService.executeScript(id: script.id) }
                        }) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    }
                    .padding(8)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(8)
                }
            }
            
            if !scriptService.lastExecutionOutput.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Terminal Output")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        if scriptService.isExecuting {
                            ProgressView().scaleEffect(0.5)
                        }
                    }
                    ScrollView {
                        Text(scriptService.lastExecutionOutput)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                    .frame(height: 60)
                    .background(Color.black.opacity(0.8))
                    .foregroundColor(.green)
                    .cornerRadius(6)
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .popover(isPresented: $showAddSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add Custom Script")
                    .font(.headline)
                
                TextField("Script Name (e.g. npm run dev)", text: $newName)
                    .textFieldStyle(.roundedBorder)
                TextField("Shell Command (e.g. npm run dev)", text: $newCommand)
                    .textFieldStyle(.roundedBorder)
                TextField("Icon Emoji (e.g. 🚀, 🐙, ⚡)", text: $newIcon)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    Button("Cancel") { showAddSheet = false }
                    Spacer()
                    Button("Save Script") {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        let cmd = newCommand.trimmingCharacters(in: .whitespaces)
                        let icon = newIcon.trimmingCharacters(in: .whitespaces).isEmpty ? "⚡" : newIcon.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty && !cmd.isEmpty {
                            scriptService.addOrUpdateScript(CustomScript(name: name, command: cmd, icon: icon))
                            newName = ""
                            newCommand = ""
                            newIcon = "⚡"
                            showAddSheet = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.isEmpty || newCommand.isEmpty)
                }
            }
            .padding(16)
            .frame(width: 300)
        }
    }
}
