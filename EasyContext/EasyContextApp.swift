import SwiftUI

@main
struct EasyContextApp: App {
    var body: some Scene {
        Window("Easy Context", id: "main") {
            ContentView()
                .onOpenURL { url in CommandLauncher.handle(url) }
        }
        .windowResizability(.contentSize)
    }
}
