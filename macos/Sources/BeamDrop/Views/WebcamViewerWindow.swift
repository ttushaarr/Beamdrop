import SwiftUI
import AppKit
import WebKit

public class WebcamWindowManager: NSObject, NSWindowDelegate {
    public static let shared = WebcamWindowManager()
    private var window: NSWindow?
    
    public func openWebcamWindow(streamURL: URL) {
        Task {
            _ = await KdeConnectService.shared.controlWebcam(action: "start")
        }
        
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let win = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "📹 BeamDrop HD Wireless Webcam"
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.delegate = self
        win.contentView = NSHostingView(rootView: WebcamStreamViewer(streamURL: streamURL))
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        self.window = win
    }
    
    public func windowWillClose(_ notification: Notification) {
        self.window = nil
        Task {
            _ = await KdeConnectService.shared.controlWebcam(action: "stop")
        }
    }
}

public struct WebcamStreamViewer: View {
    let streamURL: URL
    @ObservedObject var kde = KdeConnectService.shared
    @State private var copied: Bool = false
    @State private var isFrontCamera: Bool = false
    @State private var isTorchOn: Bool = false
    @State private var useDirectFrames: Bool = false
    @State private var reloadKey: UUID = UUID()
    
    public init(streamURL: URL) {
        self.streamURL = streamURL
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Live Stream Video View
            ZStack {
                Color.black
                if useDirectFrames {
                    if let frameURL = kde.getWebcamFrameURL() {
                        DirectFrameStreamView(frameURL: frameURL)
                    }
                } else {
                    WebcamStreamWKView(url: streamURL)
                        .id(reloadKey)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Floating Control Bar
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("LIVE 720p HD")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.12))
                .cornerRadius(6)
                
                // Refresh stream button
                Button(action: {
                    Task {
                        _ = await kde.controlWebcam(action: "start")
                        await MainActor.run { reloadKey = UUID() }
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Reconnect Video Stream")
                
                Spacer()
                
                // Flip Camera
                Button(action: {
                    Task {
                        _ = await kde.controlWebcam(action: "toggle_camera")
                        await MainActor.run { isFrontCamera.toggle() }
                    }
                }) {
                    Label(isFrontCamera ? "Use Back Lens" : "Flip to Selfie", systemImage: "arrow.triangle.2.circlepath.camera")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                // Toggle Torch
                Button(action: {
                    Task {
                        _ = await kde.controlWebcam(action: "toggle_torch")
                        await MainActor.run { isTorchOn.toggle() }
                    }
                }) {
                    Label(isTorchOn ? "Torch ON" : "Torch", systemImage: isTorchOn ? "bolt.fill" : "bolt.slash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                // Direct Frames vs MJPEG Stream
                Button(action: {
                    useDirectFrames.toggle()
                }) {
                    Label(useDirectFrames ? "Mode: Direct Frame" : "Mode: MJPEG Stream", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                // Copy OBS / Browser Link
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(streamURL.absoluteString, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                }) {
                    Label(copied ? "Copied OBS Link!" : "Copy OBS Link", systemImage: copied ? "checkmark" : "link")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}

public struct DirectFrameStreamView: View {
    let frameURL: URL
    @State private var currentImage: NSImage?
    @State private var isRunning: Bool = true
    
    public var body: some View {
        ZStack {
            Color.black
            if let img = currentImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                VStack(spacing: 12) {
                    ProgressView().scaleEffect(0.8)
                    Text("Fetching Direct Frames from Tablet...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .onAppear {
            isRunning = true
            startPolling()
        }
        .onDisappear {
            isRunning = false
        }
    }
    
    private func startPolling() {
        Task.detached(priority: .high) {
            let session = URLSession(configuration: .ephemeral)
            while !Task.isCancelled {
                do {
                    let (data, resp) = try await session.data(from: frameURL)
                    if let http = resp as? HTTPURLResponse, http.statusCode == 200, let nsImg = NSImage(data: data) {
                        await MainActor.run {
                            self.currentImage = nsImg
                        }
                    }
                } catch {}
                try? await Task.sleep(nanoseconds: 33_000_000) // ~30 FPS
            }
        }
    }
}

public struct WebcamStreamWKView: NSViewRepresentable {
    let url: URL
    
    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * { box-sizing: border-box; }
                html, body {
                    margin: 0;
                    padding: 0;
                    background-color: #0b0c10;
                    overflow: hidden;
                    height: 100%;
                    width: 100%;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    justify-content: center;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                }
                #stream-container {
                    width: 100%;
                    height: 100%;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    position: relative;
                }
                img {
                    width: 100%;
                    height: 100%;
                    object-fit: contain;
                    display: none;
                }
                .spinner {
                    border: 3px solid rgba(255, 255, 255, 0.1);
                    border-top: 3px solid #ef4444;
                    border-radius: 50%;
                    width: 32px;
                    height: 32px;
                    animation: spin 1s linear infinite;
                    margin-bottom: 12px;
                }
                @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
                #loader {
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    justify-content: center;
                    color: #9ca3af;
                    font-size: 13px;
                }
            </style>
        </head>
        <body>
            <div id="stream-container">
                <div id="loader">
                    <div class="spinner"></div>
                    <div>Connecting to Android HD Camera Stream...</div>
                </div>
                <img id="stream" src="\(url.absoluteString)"
                     onload="document.getElementById('loader').style.display='none'; this.style.display='block';"
                     onerror="document.getElementById('loader').style.display='flex'; this.style.display='none'; setTimeout(function() { var s = document.getElementById('stream'); s.src = '\(url.absoluteString)' + (s.src.indexOf('?') > -1 ? '&' : '?') + 'r=' + Date.now(); }, 1200);" />
            </div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: url)
        return webView
    }
    
    public func updateNSView(_ nsView: WKWebView, context: Context) {}
}
