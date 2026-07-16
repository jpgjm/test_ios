import Flutter
import UIKit
import FileProvider

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        registerFileProviderDomain()
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    /// Files.appの側面板に「Music Player」を出現させるためのドメイン登録。
    /// 初回起動時のみ登録され、以降は既に登録済みとして扱われる。
    private func registerFileProviderDomain() {
        let identifier = NSFileProviderDomainIdentifier(rawValue: "MusicPlayerRoot")
        let displayName = "Music Player"
        let domain = NSFileProviderDomain(identifier: identifier, displayName: displayName)

        NSFileProviderManager.add(domain) { error in
            if let error = error {
                NSLog("[MusicPlayer] File Provider domain registration failed: \(error)")
            } else {
                NSLog("[MusicPlayer] File Provider domain registered: \(displayName)")
            }
        }
    }
}
