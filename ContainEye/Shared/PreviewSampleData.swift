import Blackbird
import SwiftUI

enum PreviewSamples {
    static let credential = Credential(
        key: "preview-server",
        label: "Preview Server",
        host: "preview.local",
        port: 22,
        username: "root",
        password: "preview"
    )

    static var server: Server {
        var server = Server(credentialKey: credential.key)
        server.cpuUsage = 0.24
        server.memoryUsage = 0.43
        server.diskUsage = 0.37
        server.systemLoad = 0.12
        server.lastUpdate = .now
        server.isConnected = true
        server.osType = "Linux"
        server.containerRuntime = "docker"
        return server
    }

    static let test = ServerTest(
        id: 9001,
        title: "Nginx Responds",
        notes: "Checks if nginx endpoint is healthy",
        credentialKey: credential.key,
        command: "curl -s http://localhost/health",
        expectedOutput: "ok",
        lastRun: .now.addingTimeInterval(-300),
        status: .success,
        output: "ok"
    )

    static let snippet = Snippet(
        id: "preview-snippet",
        command: "docker ps --format 'table {{.Names}}\\t{{.Status}}'",
        comment: "List running containers",
        lastUse: .now.addingTimeInterval(-120),
        credentialKey: credential.key
    )

    static let container = Container(
        id: "preview-container",
        name: "web",
        status: "Up 2 minutes",
        cpuUsage: 0.17,
        memoryUsage: 0.31,
        serverId: credential.key
    )

    static let process = Process(
        id: "preview-process",
        serverId: credential.key,
        pid: 1234,
        command: "/usr/sbin/nginx -g daemon off;",
        user: "root",
        cpuUsage: 1.2,
        memoryUsage: 2.4
    )

    static let dockerCompose = DockerCompose(
        serverId: credential.key,
        filePath: "/srv/app/docker-compose.yml",
        projectName: "app",
        services: ["web", "db"],
        lastModified: .now.addingTimeInterval(-1800),
        isRunning: true
    )
}

struct PreviewSampleDataModifier: PreviewModifier {
    struct Context {
        let db: Blackbird.Database
    }

    static func makeSharedContext() async throws -> Context {
        let db = try Blackbird.Database.inMemoryDatabase()

        try await PreviewSamples.server.write(to: db)
        try await PreviewSamples.test.write(to: db)
        try await PreviewSamples.snippet.write(to: db)
        try await PreviewSamples.container.write(to: db)
        try await PreviewSamples.process.write(to: db)
        try await PreviewSamples.dockerCompose.write(to: db)

        return Context(db: db)
    }

    func body(content: Content, context: Context) -> some View {
        PreviewNamespaceContainer {
            content
        }
        .environment(\.blackbirdDatabase, context.db)
        .confirmator()
    }
}

private struct PreviewNamespaceContainer<Content: View>: View {
    @Namespace private var namespace
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.namespace, namespace)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    @MainActor
    static var sampleData: Self {
        .modifier(PreviewSampleDataModifier())
    }
}
