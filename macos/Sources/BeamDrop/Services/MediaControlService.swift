import Foundation
import AppKit

public final class MediaControlService {
    public static let shared = MediaControlService()
    
    private init() {}
    
    public func handleMediaAction(_ action: KdeMediaAction) {
        switch action.action {
        case "play_pause":
            togglePlayPause()
        case "next":
            nextTrack()
        case "prev":
            previousTrack()
        case "volume_set":
            if let vol = action.volume {
                setVolume(vol)
            }
        case "volume_up":
            adjustVolume(by: 6)
        case "volume_down":
            adjustVolume(by: -6)
        case "mute":
            toggleMute()
        default:
            break
        }
    }
    
    public func togglePlayPause() {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify" to playpause
        else if application "Music" is running then
            tell application "Music" to playpause
        else
            tell application "System Events"
                key code 16 using {}
            end tell
        end if
        """
        runAppleScript(script)
    }
    
    public func nextTrack() {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify" to next track
        else if application "Music" is running then
            tell application "Music" to next track
        else
            tell application "System Events"
                key code 17 using {}
            end tell
        end if
        """
        runAppleScript(script)
    }
    
    public func previousTrack() {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify" to previous track
        else if application "Music" is running then
            tell application "Music" to previous track
        else
            tell application "System Events"
                key code 18 using {}
            end tell
        end if
        """
        runAppleScript(script)
    }
    
    public func setVolume(_ volumeFraction: Float) {
        let percent = Int(max(0.0, min(1.0, volumeFraction)) * 100)
        let script = "set volume output volume \(percent)"
        runAppleScript(script)
    }
    
    public func adjustVolume(by delta: Int) {
        let script = """
        set curVol to output volume of (get volume settings)
        set newVol to curVol + (\(delta))
        if newVol < 0 then set newVol to 0
        if newVol > 100 then set newVol to 100
        set volume output volume newVol
        """
        runAppleScript(script)
    }
    
    public func toggleMute() {
        let script = """
        set curMute to output muted of (get volume settings)
        set volume output muted (not curMute)
        """
        runAppleScript(script)
    }
    
    private func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let script = NSAppleScript(source: source) {
                script.executeAndReturnError(&error)
            }
        }
    }
}
