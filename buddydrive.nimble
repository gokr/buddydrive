import os, strutils

version = "0.1.0"
author = "Göran Krampe"
description = "P2P encrypted folder sync with buddies"
license = "MIT"
srcDir = "src"
binDir = "bin"
bin = @["buddydrive"]

requires "nim >= 2.2.8"
requires "libp2p >= 1.15"
requires "libsodium >= 0.7"
requires "parsetoml"
requires "results >= 0.5.1"
requires "stew"
requires "uuids"
requires "db_connector"
requires "mummy"
requires "nat_traversal"
requires "curly"
requires "https://github.com/gokr/lz4wrapper"
requires "https://github.com/status-im/nim-zlib#daa8723"

task test, "Run tests":
  exec "nimble c -r tests/harness/test_sync_policy.nim"
  exec "nimble c -r tests/harness/test_peer_discovery.nim"
  exec "nimble c -r tests/harness/test_relay_fallback.nim"
  exec "nimble c -r tests/harness/test_relay_file_sync.nim"

task build, "Build release CLI":
  exec "nim c -d:release src/buddydrive.nim"

task gui, "Build GUI (debug)":
  exec "nim c -d:gtk4 -o:bin/buddydrive-gui src/buddydrive_gui.nim"

task gui_release, "Build GUI (release)":
  exec "nim c -d:release -d:gtk4 -o:bin/buddydrive-gui src/buddydrive_gui.nim"

task icons, "Install icons to ~/.local/share/icons":
  let home = getHomeDir()
  let iconsBase = home / ".local/share/icons/hicolor"
  let cwd = getCurrentDir()
  
  echo "Installing icons..."
  
  for size in ["48", "128", "256", "512"]:
    let srcDir = cwd / "icons/hicolor" / (size & "x" & size) / "apps"
    let destDir = iconsBase / (size & "x" & size) / "apps"
    exec "mkdir -p " & destDir.quoteShell()
    if fileExists(srcDir / "buddydrive.png"):
      exec "cp " & (srcDir / "buddydrive.png").quoteShell() & " " & (destDir / "buddydrive.png").quoteShell()
      echo "  Installed " & size & "x" & size & " icon"
  
  # Create index.theme if not exists
  let indexTheme = iconsBase / "index.theme"
  if not fileExists(indexTheme):
    let content = """[Icon Theme]
Name=Hicolor
Comment=Freedesktop.org compatibility icon theme
Directories=48x48/apps,128x128/apps,256x256/apps,512x512/apps

[48x48/apps]
Size=48
Context=Applications
Type=Fixed

[128x128/apps]
Size=128
Context=Applications
Type=Fixed

[256x256/apps]
Size=256
Context=Applications
Type=Fixed

[512x512/apps]
Size=512
Context=Applications
Type=Fixed
"""
    writeFile(indexTheme, content)
    echo "Created icon theme index"
  
  exec "gtk4-update-icon-cache -f " & iconsBase.quoteShell() & " 2>/dev/null || true"

task install_gui, "Install GUI with desktop integration":
  let home = getHomeDir()
  let desktopDir = home / ".local/share/applications"
  let binDir = home / ".local/bin"
  let iconsBase = home / ".local/share/icons/hicolor"
  let cwd = getCurrentDir()
  
  echo "Creating directories..."
  exec "mkdir -p " & desktopDir.quoteShell()
  exec "mkdir -p " & binDir.quoteShell()
  
  let guiSource = cwd / "bin" / "buddydrive-gui"
  let guiDest = binDir / "buddydrive-gui"
  if not fileExists(guiSource):
    echo "Error: buddydrive-gui binary not found. Run 'nimble gui_release' first."
    system.quit(1)
  echo "Installing buddydrive-gui binary to " & guiDest & "..."
  exec "cp " & guiSource.quoteShell() & " " & guiDest.quoteShell()
  exec "chmod +x " & guiDest.quoteShell()
  
  echo "Installing buddydrive.desktop..."
  exec "cp " & (cwd / "buddydrive.desktop").quoteShell() & " " & (desktopDir / "buddydrive.desktop").quoteShell()
  exec "sed -i 's|Exec=.*|Exec=" & guiDest & "|g' " & (desktopDir / "buddydrive.desktop").quoteShell()
  exec "sed -i 's|StartupWMClass=.*|StartupWMClass=org.buddydrive.app|g' " & (desktopDir / "buddydrive.desktop").quoteShell()
  
  echo "Installing icons..."
  for size in ["48", "128", "256", "512"]:
    let srcDir = cwd / "icons/hicolor" / (size & "x" & size) / "apps"
    let destDir = iconsBase / (size & "x" & size) / "apps"
    exec "mkdir -p " & destDir.quoteShell()
    if fileExists(srcDir / "buddydrive.png"):
      exec "cp " & (srcDir / "buddydrive.png").quoteShell() & " " & (destDir / "buddydrive.png").quoteShell()
  
  # Create index.theme if not exists
  let indexTheme = iconsBase / "index.theme"
  if not fileExists(indexTheme):
    let content = """[Icon Theme]
Name=Hicolor
Comment=Freedesktop.org compatibility icon theme
Directories=48x48/apps,128x128/apps,256x256/apps,512x512/apps

[48x48/apps]
Size=48
Context=Applications
Type=Fixed

[128x128/apps]
Size=128
Context=Applications
Type=Fixed

[256x256/apps]
Size=256
Context=Applications
Type=Fixed

[512x512/apps]
Size=512
Context=Applications
Type=Fixed
"""
    writeFile(indexTheme, content)
    echo "Created icon theme index"
  
  exec "gtk4-update-icon-cache -f " & iconsBase.quoteShell() & " 2>/dev/null || true"
  
  exec "update-desktop-database " & desktopDir.quoteShell() & " 2>/dev/null || true"
  
  echo ""
  echo "BuddyDrive GUI installed!"
  echo "You may need to log out/in for icons to appear in the dock."
