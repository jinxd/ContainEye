import SwiftUI
import Blackbird
import ButtonKit
import KeychainAccess

struct ConfigureDisabledTestView: View {
    @BlackbirdLiveModel var test: ServerTest?

    var body: some View {
        ContentUnavailableView("This test is currently disabled", systemImage: "testtube.2", description: Text("Let's configure it for you needs."))
    }
}