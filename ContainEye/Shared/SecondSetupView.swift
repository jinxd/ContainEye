struct SecondSetupView: View {
    @Binding var screen: Int?

    var body: some View {
        VStack {
            Spacer()
            Text("Alright, let's add a Server")
                .font(.largeTitle.bold())
            Spacer()
            ContentUnavailableView(
                "First we'll add a server",
                systemImage: "server.rack",
                description: Text("You have to add a server to monitor it's status and test it.")
            )
            .font(.largeTitle.bold())
            .imageScale(.large)
            Spacer()
            Button("Get started") {
                Logger.telemetry("setup started")
                screen = 0
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            Spacer()
        }
    }
}
