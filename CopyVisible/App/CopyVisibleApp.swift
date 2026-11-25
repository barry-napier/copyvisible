import SwiftUI

@main
struct CopyVisibleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The menu bar icon and every window are made by AppDelegate. SwiftUI
    // needs one scene, so this empty one is never shown.
    var body: some Scene {
        Settings { EmptyView() }
    }
}
