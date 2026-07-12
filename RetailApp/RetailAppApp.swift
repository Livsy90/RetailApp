//
//  RetailAppApp.swift
//  RetailApp
//
//  Created by Artem Mir on 10.07.26.
//

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
