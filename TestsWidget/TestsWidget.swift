//
//  TestsWidget.swift
//  TestsWidget
//
//  Created by Hannes Nagel on 2/18/25.
//

import WidgetKit
import SwiftUI
import Blackbird

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TestTimelineEntry {
        TestTimelineEntry(
            date: Date(),
            test: ServerTest(
                id: .random(in: (.min)...(.max)),
                title: "A recent test",
                credentialKey: "",
                command: "echo test",
                expectedOutput: "test",
                status: .success
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TestTimelineEntry) -> ()) {
        Task {
            let db = SharedDatabase.db

            let stati : Set<ServerTest.TestStatus> = [
                .failed,
                .running,
                .success,
                .notRun
            ]
            let all = try await ServerTest.read(
                from: db,
                matching: \.$credentialKey != "-",
                orderBy: .ascending(\.$lastRun)
            )
                .sorted {
                    stati.firstIndex(of: $0.status)! < stati.firstIndex(of: $1.status)!
                }

            let entry = TestTimelineEntry(date: Date(), test: all.first)
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        Task {
            let db = SharedDatabase.db

            let stati : Set<ServerTest.TestStatus> = [
                .failed,
                .running,
                .success,
                .notRun
            ]
            let all = try await ServerTest.read(
                from: db,
                matching: \.$credentialKey != "-",
                orderBy: .ascending(\.$lastRun)
            )
                .sorted {
                    stati.firstIndex(of: $0.status)! < stati.firstIndex(of: $1.status)!
                }

            let timeline = Timeline(entries: [
                TestTimelineEntry(date: .now, test: all.first)
            ], policy: .atEnd)

            completion(timeline)
        }
    }

//    func relevances() async -> WidgetRelevances<Void> {
//        // Generate a list containing the contexts this widget is relevant in.
//    }
}

struct TestTimelineEntry: TimelineEntry {
    let date: Date
    let test: ServerTest?
}

struct TestsWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack {
            if let test = entry.test {
                WidgetTestSummaryView(test: test)
            } else {
                ContentUnavailableView("No tests available", systemImage: "testtube.2")
            }
        }
    }
}

struct WidgetTestSummaryView: View {
    let test: ServerTest

    var body: some View {

        VStack {
            Text(test.title)
                .font(.title3)
                .lineLimit(3)
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let lastRun = test.lastRun {
                (Text(lastRun, style: .relative) + Text(" ago")).font(.caption)
            }

            Button(test.status.localizedDescription, systemImage: "arrow.clockwise", intent: test.testIntent())
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(test.status == .failed ? Color.red : test.status == .success ? Color.green.opacity(0.2) : Color.blue.opacity(0.5), for: .widget)
    }
}

struct TestsWidget: Widget {
    let kind: String = "TestsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TestsWidgetEntryView(entry: entry)
        }
        .supportedFamilies([.systemSmall])
        .configurationDisplayName("Test Widget")
        .description("View recently failed tests and run them again.")
    }
}

#Preview(as: .systemSmall) {
    TestsWidget()
} timeline: {
    TestTimelineEntry(
        date: .now,
        test: ServerTest(
            id: 712893,
            title: "Title of the test",
            credentialKey: "",
            command: "",
            expectedOutput: "",
            status: .failed
        )
    )
    TestTimelineEntry(
        date: .now,
        test: ServerTest(
            id: 712893,
            title: "Title of the test",
            credentialKey: "",
            command: "",
            expectedOutput: "",
            status: .running
        )
    )
    TestTimelineEntry(
        date: .now,
        test: ServerTest(
            id: 712893,
            title: "Title of the test",
            credentialKey: "",
            command: "",
            expectedOutput: "",
            status: .success
        )
    )
}
