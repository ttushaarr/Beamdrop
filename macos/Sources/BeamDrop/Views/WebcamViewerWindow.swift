import SwiftUI
import AppKit
import WebKit

public class WebcamWindowManager {
    public static let shared = WebcamWindowManager()
    private var window: NSWindow?
    
    public func openWebcamWindow(streamURL: URL) {
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
        win.contentView = NSHostingView(rootView: WebcamStreamViewer(streamURL: streamURL))
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        self.window = win
    }
}

public struct WebcamStreamViewer: View {
    let streamURL: URL
    @ObservedObject var kde = KdeConnectService.shared
    @State private var copied: Bool = false
    @State private var isFrontCamera: Bool = false
    @State private var isTorchOn: Bool = false
    
    public init(streamURL: URL) {
        self.streamURL = streamURL
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Live Stream Video View
            WebcamStreamWKView(url: streamURL)
                .background(Color.black)
            
            // Floating Control Bar
            HStack(spacing: 16) {
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
        .frame(minWidth: 480, minHeight: 320)
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
                html, body {
                    margin: 0;
                    padding: 0;
                    background-color: #0b0c10;
                    overflow: hidden;
                    height: 100%;
                    width: 100%;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                img {
                    width: 100%;
                    height: 100%;
                    object-fit: contain;
                }
            </style>
        </head>
        <body>
            <img src="\(url.absoluteString)" alt="BeamDrop HD Stream" />
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }
    
    public func updateNSView(_ nsView: WKWebView, context: Context) {}
}
