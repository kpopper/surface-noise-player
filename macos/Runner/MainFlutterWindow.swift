import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Opens desktop-sized (wide layout) the first time; after that the
    // autosaved frame from the last session takes over.
    self.setContentSize(NSSize(width: 1280, height: 800))
    self.center()
    self.contentMinSize = NSSize(width: 360, height: 500)
    self.setFrameAutosaveName("MainWindow")

    RegisterGeneratedPlugins(registry: flutterViewController)
    BookmarkPlugin.register(with: flutterViewController.registrar(forPlugin: "BookmarkPlugin"))

    super.awakeFromNib()
  }
}
