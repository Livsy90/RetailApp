import SwiftUI

@main
struct RetailAppApp: App {
    private let composition = AppComposition.demo()

    var body: some Scene {
        WindowGroup {
            composition.makeRootView()
        }
    }
}

#Preview {
    AppComposition
        .demo()
        .makeRootView()
}
