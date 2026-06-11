import Flutter
import UIKit
import UniformTypeIdentifiers

class BookmarkPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
    static let channelName = "com.yourname.surface_noise_player/bookmarks"
    static let defaultsKey = "library_bookmark"

    private var pendingResult: FlutterResult?
    private var activeURL: URL?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = BookmarkPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "pickFolder":
            pickFolder(result: result)
        case "resolveBookmark":
            resolveBookmark(result: result)
        case "stopAccess":
            stopAccess()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Pick folder

    private func pickFolder(result: @escaping FlutterResult) {
        pendingResult = result
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
        }
        picker.allowsMultipleSelection = false
        picker.delegate = self

        DispatchQueue.main.async {
            guard let root = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                result(FlutterError(code: "NO_VC", message: "No root view controller found", details: nil))
                return
            }
            var top = root
            while let presented = top.presentedViewController { top = presented }
            top.present(picker, animated: true)
        }
    }

    // Called immediately while iOS security-scoped access is still open.
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let result = pendingResult else { return }
        pendingResult = nil

        let accessed = url.startAccessingSecurityScopedResource()

        do {
            let bookmark = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: BookmarkPlugin.defaultsKey)
            // Keep access open so the immediate library scan can read the folder.
            activeURL = accessed ? url : nil
            result(url.path)
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            result(FlutterError(code: "BOOKMARK_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingResult?(nil)
        pendingResult = nil
    }

    // MARK: - Resolve bookmark

    private func resolveBookmark(result: @escaping FlutterResult) {
        activeURL?.stopAccessingSecurityScopedResource()
        activeURL = nil

        guard let bookmark = UserDefaults.standard.data(forKey: BookmarkPlugin.defaultsKey) else {
            result(nil)
            return
        }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard url.startAccessingSecurityScopedResource() else {
                result(FlutterError(code: "ACCESS_DENIED", message: "Could not access security-scoped resource", details: nil))
                return
            }
            if isStale, let fresh = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: BookmarkPlugin.defaultsKey)
            }
            activeURL = url
            result(url.path)
        } catch {
            result(FlutterError(code: "RESOLVE_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Stop access

    private func stopAccess() {
        activeURL?.stopAccessingSecurityScopedResource()
        activeURL = nil
    }
}
