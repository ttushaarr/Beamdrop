import SwiftUI
import AppKit

public struct RemoteFileBrowserView: View {
    @ObservedObject var fileService = RemoteFileService.shared
    @State private var downloadingItem: String? = nil
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            // Header & Quick Directory Shortcuts
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("📂 Android Remote File Browser")
                        .font(.system(size: 15, weight: .bold))
                    Text("Browse and download files stored on your Android device over Wi-Fi")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    Task { await fileService.fetchFolder(fileService.currentFolder) }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // Directory Navigation Pills
            HStack(spacing: 10) {
                FolderPill(title: "Downloads", icon: "folder.badge.gearshape", folder: "Download", current: fileService.currentFolder) {
                    Task { await fileService.fetchFolder("Download") }
                }
                FolderPill(title: "Pictures", icon: "photo.stack", folder: "Pictures", current: fileService.currentFolder) {
                    Task { await fileService.fetchFolder("Pictures") }
                }
                FolderPill(title: "Movies", icon: "film", folder: "Movies", current: fileService.currentFolder) {
                    Task { await fileService.fetchFolder("Movies") }
                }
                FolderPill(title: "Camera", icon: "camera", folder: "DCIM/Camera", current: fileService.currentFolder) {
                    Task { await fileService.fetchFolder("DCIM/Camera") }
                }
                Spacer()
            }
            
            // Files List View
            ZStack {
                Color(NSColor.controlBackgroundColor)
                    .cornerRadius(12)
                
                if fileService.isLoading {
                    ProgressView("Loading remote files...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if fileService.files.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No files found in '\(fileService.currentFolder)'")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(fileService.files) { file in
                                HStack(spacing: 12) {
                                    Image(systemName: file.isDirectory ? "folder.fill" : fileIcon(file.name))
                                        .foregroundColor(file.isDirectory ? .blue : .secondary)
                                        .font(.system(size: 20))
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(1)
                                        HStack(spacing: 8) {
                                            if !file.isDirectory {
                                                Text(formatBytes(file.size))
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                            }
                                            if file.lastModified > 0 {
                                                Text(Date(timeIntervalSince1970: TimeInterval(file.lastModified / 1000)), style: .date)
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if file.isDirectory {
                                        Button("Open") {
                                            Task { await fileService.fetchFolder(file.path) }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    } else {
                                        Button(action: {
                                            downloadingItem = file.name
                                            Task {
                                                _ = await fileService.downloadFile(file)
                                                await MainActor.run { downloadingItem = nil }
                                            }
                                        }) {
                                            if downloadingItem == file.name {
                                                ProgressView()
                                                    .scaleEffect(0.6)
                                            } else {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "arrow.down.circle")
                                                    Text("Download")
                                                }
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        .disabled(downloadingItem != nil)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(NSColor.windowBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            
            if let msg = fileService.statusMessage {
                HStack {
                    Text(msg)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(msg.hasPrefix("✓") ? .green : .primary)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
        .onAppear {
            if fileService.files.isEmpty {
                Task { await fileService.fetchFolder("Download") }
            }
        }
    }
    
    private func fileIcon(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "webp", "gif", "heic": return "photo.fill"
        case "mp4", "mkv", "mov", "webm", "avi": return "film.fill"
        case "mp3", "m4a", "wav", "flac": return "music.note"
        case "pdf": return "doc.richtext.fill"
        case "zip", "tar", "gz", "7z": return "doc.zipper"
        default: return "doc.fill"
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        }
        let kb = Double(bytes) / 1024.0
        return String(format: "%.0f KB", kb)
    }
}

private struct FolderPill: View {
    let title: String
    let icon: String
    let folder: String
    let current: String
    let action: () -> Void
    
    var isSelected: Bool { current == folder || current.hasPrefix(folder) }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue.opacity(0.15) : Color(NSColor.controlBackgroundColor))
            .foregroundColor(isSelected ? .blue : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
