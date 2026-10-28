import SwiftUI

@main
struct NothingOnMacApp: App {
    @State private var controller: HeadphoneController
    @State private var updates = UpdateChecker()

    init() {
        #if DEBUG
        PreviewRenderer.renderIfRequested()
        #endif
        AppResources.registerFonts()
        // Only once installed: a login item pointing at a DMG or Downloads copy would break.
        if Bundle.main.bundlePath.hasPrefix("/Applications/") {
            LoginItem.enableOnFirstLaunch()
        }
        _controller = State(initialValue: HeadphoneController())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller, updates: updates)
        } label: {
            MenuBarLabel(controller: controller)
                .task { updates.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let controller: HeadphoneController

    var body: some View {
        let session = controller.status == .connected ? controller.session : nil
        Image(nsImage: MenuBarIcon.image(
            battery: session?.feature(BatteryFeature.self)?.summary?.level,
            dimmed: session == nil
        ))
    }
}
