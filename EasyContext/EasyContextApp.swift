import SwiftUI

@main
struct EasyContextApp: App {
    var body: some Scene {
        Window("Easy Context", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
