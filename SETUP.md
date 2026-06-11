# Surface Noise Player — Setup Guide

## 0. Install Homebrew

Homebrew is a package manager for macOS. Skip this step if you already have it.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

The script will prompt for your password and install the Xcode command-line tools if needed. When it finishes, follow any instructions it prints about adding Homebrew to your PATH (required on Apple Silicon Macs):

```bash
# Apple Silicon only — paste the two lines the installer prints, e.g.:
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Verify it works:
```bash
brew --version
```

---

## 1. Install Flutter

### Option A: Homebrew (recommended)
```bash
brew install --cask flutter
```

### Option B: Manual
1. Download the Flutter SDK from https://docs.flutter.dev/get-started/install/macos
2. Extract to `~/development/flutter`
3. Add to your PATH in `~/.zshrc`:
   ```bash
   export PATH="$HOME/development/flutter/bin:$PATH"
   ```
4. Reload: `source ~/.zshrc`

---

## 2. Install Xcode

1. Install Xcode from the Mac App Store (it's large, ~10 GB)
2. After install, accept the license:
   ```bash
   sudo xcodebuild -license accept
   ```
3. Install Xcode command-line tools:
   ```bash
   xcode-select --install
   ```
4. Install a modern Ruby via Homebrew (macOS ships with Ruby 2.6, but CocoaPods requires 3.0+):
   ```bash
   brew install ruby
   ```
   Then add the Homebrew Ruby to your PATH so it takes precedence over the system one. Add these lines to your `~/.zshrc`:
   ```bash
   export PATH="$(brew --prefix ruby)/bin:$PATH"
   export PATH="$(gem environment gemdir)/bin:$PATH"
   ```
   Reload your shell:
   ```bash
   source ~/.zshrc
   ```
   Verify you're on the new Ruby:
   ```bash
   ruby --version   # should be 3.x or higher
   ```
5. Install CocoaPods:
   ```bash
   gem install cocoapods
   ```

---

## 3. Install VS Code (recommended editor)

Xcode has no Dart support, so use VS Code for editing the Flutter source code.

1. Install VS Code via Homebrew:
   ```bash
   brew install --cask visual-studio-code
   ```
   Or download it manually from https://code.visualstudio.com

2. Install the Flutter extension (includes Dart support):
   - Open VS Code
   - Press `Cmd+Shift+X` to open the Extensions panel
   - Search for **Flutter** (publisher: Dart Code)
   - Click **Install** — this also installs the Dart extension automatically

3. Install the `code` shell command so you can open projects from the terminal:
   - Open the Command Palette with `Cmd+Shift+P`
   - Type **Shell Command: Install 'code' command in PATH**
   - Press Enter

4. Open this project:
   ```bash
   code "/Users/ian/Dev/Surface Noise Player"
   ```

---

## 4. Verify your setup

```bash
flutter doctor
```

All items should show a green checkmark. The "Android toolchain" warning can be ignored — we're iOS only.

---

## 5. Create the Flutter project

From this directory:
```bash
flutter create . --org com.yourname --project-name surface_noise_player --platforms ios
```

Then install dependencies:
```bash
bash scripts/post_create.sh
```

---

## 6. Running and developing in VS Code

VS Code is the best place to write code, run the app, and use hot reload.

### Select a device

The Flutter extension adds a device picker to the VS Code status bar (bottom right). Click it to choose between:
- **iPhone Simulator** — for quick testing without a physical device
- **Your iPhone** — when plugged in via USB (must be trusted on the device first)

### Run the app

- Press `F5` (or **Run → Start Debugging**) to build and launch the app with the debugger attached
- Or press `Ctrl+F5` (or **Run → Run Without Debugging**) for a slightly faster launch without the debugger

The first build takes a minute or two. Subsequent runs are much faster.

### Hot reload and hot restart

Once the app is running, save any Dart file (`Cmd+S`) to trigger a **hot reload** — your changes appear on the device in under a second without losing app state.

For larger changes (e.g. adding a new widget to the tree), use **hot restart**:
- Click the ↺ restart button in the debug toolbar, or
- Press `Cmd+Shift+P` → **Flutter: Hot Restart**

### Useful VS Code commands (Command Palette: `Cmd+Shift+P`)

| Command | What it does |
|---|---|
| **Flutter: Hot Reload** | Apply UI changes instantly |
| **Flutter: Hot Restart** | Full restart, clears state |
| **Flutter: Select Device** | Switch between Simulator and iPhone |
| **Flutter: Run Flutter Doctor** | Check your setup |
| **Dart: Open DevTools** | Opens browser-based profiler and widget inspector |

### Debug panel

When running with `F5`, the **Debug Console** at the bottom shows `print()` output and errors. Click on an error to jump to the relevant line in your code.

### Widget Inspector

Open DevTools (`Cmd+Shift+P` → **Dart: Open DevTools**) to get a live widget tree — useful for understanding layout and spotting padding/sizing issues.

---

## 7. Run on your iPhone (free Apple account)

iCloud Drive is not available in the Simulator — you need a real device to test music folder access.

1. Plug your iPhone into your Mac via USB
2. Unlock your iPhone and tap **Trust** when prompted
3. Open `ios/Runner.xcworkspace` in Xcode
4. Sign in with your Apple ID: Xcode → Settings → Accounts → Add Apple ID
5. Under **Signing & Capabilities**, select your Personal Team
6. Select your iPhone in the Xcode toolbar and click Run (▶) once to register the device

After that first Xcode run, you can deploy directly from VS Code — just select your iPhone in the device picker and press `F5`.

Note: Free accounts require re-signing every 7 days. A paid Apple Developer account ($99/yr) removes this limit.

---

## 8. iCloud Drive access

The app will ask for permission to access your Files the first time it runs. Tap **Allow** and navigate to your iCloud Drive music folder. The app stores this location so you only have to do it once.

Your music folder should be structured like:
```
iCloud Drive/
  Music/
    Artist - Album Name/
      01 - Track Title.mp3
      02 - Track Title.mp3
    Another Album/
      track1.flac
      ...
```

Each subfolder = one release in the browser.
