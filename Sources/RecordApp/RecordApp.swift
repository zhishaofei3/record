import RecordCore
import SwiftUI

@main
struct RecordAppMain: App {
    @StateObject private var viewModel = RecorderViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1120, minHeight: 760)
        }
        .windowResizability(.contentMinSize)
    }
}
