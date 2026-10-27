cask "beamdrop" do
  version "1.4.0"
  sha256 "57bd990f8bc1b05050ba286e9ee1f87063d8472ac98e6b21dffdbe9e0018629b"

  url "https://github.com/ttushaarr/Beamdrop/releases/download/v#{version}/BeamDrop-Mac.zip"
  name "BeamDrop"
  desc "AirDrop, KDE Connect, Wireless ADB & Webcam bridge for macOS and Android"
  homepage "https://ttushaarr.github.io/Beamdrop/"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "BeamDrop.app"

  zap trash: [
    "~/Library/Preferences/com.beamdrop.BeamDrop.plist",
    "~/Downloads/BeamDrop",
  ]
end
