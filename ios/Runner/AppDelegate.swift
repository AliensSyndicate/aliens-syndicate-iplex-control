import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IplexAppSharing") else { return }
    let channel = FlutterMethodChannel(name: "iplex/app_sharing", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "share" else { result(FlutterMethodNotImplemented); return }
      guard let args = call.arguments as? [String: Any], let text = args["text"] as? String, !text.isEmpty else {
        result(FlutterError(code: "invalid-argument", message: nil, details: nil)); return
      }
      DispatchQueue.main.async {
        guard var presenter = self?.window?.rootViewController else {
          result(FlutterError(code: "share-unavailable", message: nil, details: nil)); return
        }
        while let next = presenter.presentedViewController { presenter = next }
        let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
          popover.sourceView = presenter.view
          popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
          popover.permittedArrowDirections = []
        }
        presenter.present(sheet, animated: true) { result(nil) }
      }
    }
  }
}
