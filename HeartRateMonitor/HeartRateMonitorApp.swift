//
//  HeartRateMonitorApp.swift
//  HeartRateMonitor
//
//  Created by Jason Luo on 7/8/22.
//

import SwiftUI

@main
struct HeartRateMonitorApp: App {
    @StateObject private var dataModel = DataModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataModel)
        }
    }
}
