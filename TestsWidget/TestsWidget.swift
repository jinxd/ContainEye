//
//  TestsWidget.swift
//  TestsWidget
//
//  Created by Hannes Nagel on 2/18/25.
//

import WidgetKit
import SwiftUI
import Blackbird
import OrderedCollections

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
            ), url: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TestTimelineEntry) -> ()) {
        Task {
            let db = SharedDatabase.db

            let stati : OrderedSet<ServerTest.TestStatus> = [
                .failed,
                .running,
                .success,
                .notRun
            ]
            var all = try await ServerTest.read(
                from: db,
                matching: \.$credentialKey != "-",
                orderBy: .ascending(\.$lastRun)
            )
            all.sort{
                stati.firstIndex(of: $0.status)! < stati.firstIndex(of: $1.status)!
            }
            let entry = await TestTimelineEntry(date: Date(), test: all.first, url: all.first?.entity.urlRepresentation)
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        Task {
            let db = SharedDatabase.db

            let stati : OrderedSet<ServerTest.TestStatus> = [
                .failed,
                .running,
                .success,
                .notRun
            ]
            var all = try await ServerTest.read(
                from: db,
                matching: \.$credentialKey != "-",
                orderBy: .ascending(\.$lastRun)
            )
            all.sort{
                stati.firstIndex(of: $0.status)! < stati.firstIndex(of: $1.status)!
            }
            let timeline = await Timeline(entries: [
                TestTimelineEntry(date: .now, test: all.first, url: all.first?.entity.urlRepresentation)
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
    let url: URL?
}

struct TestsWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack {
            if let test = entry.test {
                WidgetTestSummaryView(test: test)
                    .widgetURL(entry.url)
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
                VStack(alignment: .center) {
                    (Text(lastRun, style: .relative) + Text(" ago")).font(.caption)
                        .multilineTextAlignment(.center)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }

            Button(test.status.localizedDescription, systemImage: "arrow.clockwise", intent: test.testIntent())
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .invalidatableContent()
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
        ), url: nil
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
        ), url: nil
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
        ), url: nil
    )
}
