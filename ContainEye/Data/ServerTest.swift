//
//  ServerTest.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/24/25.
//

import Blackbird
import KeychainAccess
import Citadel
import NIOSSH
import AppIntents
import SwiftUI
import CoreSpotlight

struct ServerTest: BlackbirdModel {

    static let primaryKey: [BlackbirdColumnKeyPath] = [
        \.$id
    ]

    static let indexes: [[BlackbirdColumnKeyPath]] = [
        [\.$status],
        [\.$lastRun]
    ]

    @BlackbirdColumn var id: Int
    @BlackbirdColumn var title: String
    @BlackbirdColumn var notes: String?
    @BlackbirdColumn var credentialKey: String
    @BlackbirdColumn var command: String
    @BlackbirdColumn var expectedOutput: String
    @BlackbirdColumn var lastRun: Date?
    @BlackbirdColumn var status: TestStatus
    @BlackbirdColumn var output: String?

    var entity : ServerTestAppEntitiy {
        let entity = ServerTestAppEntitiy(id: id, credentialKey: credentialKey)
        entity.title = title
        entity.command = command
        entity.expectedOutput = expectedOutput
        entity.lastRun = lastRun
        entity.status = status
        entity.output = output
        return entity
    }

    enum TestStatus: String , BlackbirdStringEnum, AppEnum {
        typealias RawValue = String

        static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Status of a test")
        static let caseDisplayRepresentations: [ServerTest.TestStatus : DisplayRepresentation] = [
            .failed: .init(
                title: "Failed",
                image: DisplayRepresentation.Image(systemName: "xmark.seal.fill")
            ),
            .success: .init(
                title: "Success",
                image: DisplayRepresentation.Image(systemName: "checkmark.seal.fill")
            ),
            .running: .init(
                title: "Running",
                image: DisplayRepresentation.Image(
                    systemName: "seal.fill"
                )
            ),
            .notRun: .init(
                title: "hasn't run",
                image: DisplayRepresentation.Image(
                    systemName: "seal"
                )
            ),
        ]

        case failed, success, running, notRun

        var localizedDescription: String {
            switch self {
            case .failed:
                "failed"
            case .success:
                "success"
            case .running:
                "running"
            case .notRun:
                "hasn't run"
            }
        }
        var image: Image {
            Image(systemName: imageName)
        }
        var imageName: String {
            switch self {
            case .failed:
                "xmark.seal.fill"
            case .success:
                "checkmark.seal.fill"
            case .running:
                "seal.fill"
            case .notRun:
                "seal"
            }
        }
    }

    func fetchOutput() async -> String {
        do {
        guard !credentialKey.isEmpty else {
            if let url = URL(string: command){
                let (data, response) = try await URLSession.shared.data(from: url)
                return "Status Code: " + ((response as? HTTPURLResponse)?.statusCode.formatted() ?? "No response") + "\n" + (String(data: data, encoding: .utf8) ?? "No data")
            } else {
                return "No host selected and not a valid url"
            }
        }
        guard let credential = keychain().getCredential(for: self.credentialKey) else {
            return "(Client Error) No credential in keychain"
        }
            let output = try await retry { try await SSHClientActor.shared.execute(self.command, on: credential) }
            return output
                .trimmingFromEnd(character: "\n", upto: 1)
        } catch {
            do{
                let _ = try await URLSession.shared.data(from: URL(string: "https://connectivitycheck.gstatic.com/generate_204")!)
                return error.generateDescription()
            } catch {
                return "Not connected to internet"
            }
        }
    }


    func test() async -> ServerTest {
        guard credentialKey != "-" else {return self}
        Logger.telemetry("testing server")
        Logger.flushTelemetry()
        var test = self
        test.lastRun = .now

        let output = await fetchOutput()

        let regex = try? Regex(test.expectedOutput)
        let isRegexMatch: Bool
        if let regex {
            do {
                isRegexMatch = (try regex.wholeMatch(in: output)) != nil
            } catch {
                isRegexMatch = false
            }
        } else {
            isRegexMatch = false
        }

        if isRegexMatch || output == test.expectedOutput {
            test.status = .success
        } else {
            test.status = .failed
        }
        test.output = output

        return test
    }

    func testIntent() -> TestServer {
        let intent = TestServer()
        intent.test = entity
        return intent
    }
}

func retry<T>(count: Int = 15, _ block: () async throws -> T) async rethrows -> T {
    do {
        return try await block()
    } catch {
        if count > 0 {


            if let error = error as? NIOSSHError,
               error.type == .protocolViolation {

                return try await retry { try await block() }
            }
            return try await retry(count: count - 1, block)
        } else {
            throw error
        }
    }
}

extension ServerTest {
    struct ServerTestAppEntitiy: AppEntity {

        var id: Int
        var credentialKey: String


        @Property var title: String
        @Property var notes: String?
        @Property var command: String
        @Property var expectedOutput: String
        @Property var lastRun: Date?
        @Property var status: TestStatus
        @Property var output: String?

        func getServerTest() -> ServerTest {
            ServerTest(id: id, title: title, notes: notes, credentialKey: credentialKey, command: command, expectedOutput: expectedOutput, status: status)
        }

        static var typeDisplayRepresentation: TypeDisplayRepresentation {
            .init(name: "ContainEye Test", numericFormat: LocalizedStringResource("\(placeholder: .int) tests"))
        }
        var displayRepresentation: DisplayRepresentation {
            .init(title: "\(title)", subtitle: "\(status == .failed ? "Failed" : "Succeded") on \(lastRun?.formatted(date: .abbreviated, time: .shortened) ?? "Never run")", image: .init(systemName: status.imageName))
        }
        static let defaultQuery = Query()

        struct Query {
            typealias ComparatorMappingType = Predicate< ServerTest.ServerTestAppEntitiy >


            static let properties = QueryProperties {
                // Title Property
                Property(\ServerTest.ServerTestAppEntitiy.$title) {
                    ContainsComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.title.localizedStandardContains(val) }
                    }
                    EqualToComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.title == val }
                    }
                    NotEqualToComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.title != val }
                    }
                }
                // Notes Property
                Property(\ServerTest.ServerTestAppEntitiy.$notes) {
                    ContainsComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.notes?.localizedStandardContains(val) ?? false }
                    }
                    EqualToComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.notes == val }
                    }
                    NotEqualToComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.notes != val }
                    }
                }

                // Command Property
                Property(\ServerTest.ServerTestAppEntitiy.$command) {
                    ContainsComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.command.localizedStandardContains(val) }
                    }
                    EqualToComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.command == val }
                    }
                    NotEqualToComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.command != val }
                    }
                }

                // ExpectedOutput Property
                Property(\ServerTest.ServerTestAppEntitiy.$expectedOutput) {
                    ContainsComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.expectedOutput.localizedStandardContains(val) }
                    }
                    EqualToComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.expectedOutput == val }
                    }
                    NotEqualToComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.expectedOutput != val }
                    }
                }

                // LastRun Property (Date?)
                Property(\ServerTest.ServerTestAppEntitiy.$lastRun) {
                    EqualToComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.lastRun == val }
                    }
                    NotEqualToComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.lastRun != val }
                    }
                }

                // Status Property
                Property(\ServerTest.ServerTestAppEntitiy.$status) {
                    EqualToComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.status == val }
                    }
                    NotEqualToComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.status != val }
                    }
                }

                // Output Property (Optional String)
                Property(\ServerTest.ServerTestAppEntitiy.$output) {
                    ContainsComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.output?.localizedStandardContains(val) == true }
                    }
                    EqualToComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.output == val }
                    }
                    NotEqualToComparator { val in
                        #Predicate<ServerTest.ServerTestAppEntitiy> { $0.output != val }
                    }
                }
            }

            static let sortingOptions = SortingOptions {
                SortableBy(\ServerTest.ServerTestAppEntitiy.$title)
                SortableBy(\ServerTest.ServerTestAppEntitiy.$notes)
                SortableBy(\ServerTest.ServerTestAppEntitiy.$command)
                SortableBy(\ServerTest.ServerTestAppEntitiy.$expectedOutput)
                SortableBy(\ServerTest.ServerTestAppEntitiy.$lastRun)
                SortableBy(\ServerTest.ServerTestAppEntitiy.$status)
                SortableBy(\ServerTest.ServerTestAppEntitiy.$output)
            }
        }
    }
}

extension ServerTest.ServerTestAppEntitiy.Query: EntityQuery {
    func entities(for identifiers: [ServerTest.ServerTestAppEntitiy.ID]) async throws -> [ServerTest.ServerTestAppEntitiy] {
        let db = SharedDatabase.db
        let serverTests = (
            try? await ServerTest.query(
                in: db,
                columns: [\.$id],
                matching: .valueIn(\.$id, identifiers),
                orderBy: .descending(\.$lastRun)
            )
        ) ?? []
        var tests: [ServerTest] = []
        for serverTest in serverTests {
            guard let test = try? await ServerTest.read(from: db, id: serverTest[\.$id]) else {continue}
            tests.append(test)
        }
        return tests.map { $0.entity }
    }
    func suggestedEntities() async throws -> [ServerTest.ServerTestAppEntitiy] {
        let db = SharedDatabase.db
        let serverTests = (
            try? await ServerTest.query(
                in: db,
                columns: [\.$id],
                matching: \.$credentialKey != "-",
                orderBy: .descending(\.$lastRun),
                limit: 10
            )
        ) ?? []
        var tests: [ServerTest] = []
        for serverTest in serverTests {
            guard let test = try? await ServerTest.read(from: db, id: serverTest[\.$id]) else {continue}
            tests.append(test)
        }
        return tests.map { $0.entity }
    }
}

extension ServerTest.ServerTestAppEntitiy.Query: EntityStringQuery {
    func entities(matching string: String) async throws -> [ServerTest.ServerTestAppEntitiy] {
        let db = SharedDatabase.db
        let serverTests = (
            try? await ServerTest.query(
                in: db,
                columns: [\.$id],
                matching: .like(\.$title, "%\(string)%"),
                orderBy: .descending(\.$lastRun),
                limit: 10
            )
        ) ?? []
        var tests: [ServerTest] = []
        for serverTest in serverTests {
            guard let test = try? await ServerTest.read(from: db, id: serverTest[\.$id]) else {continue}
            tests.append(test)
        }
        return tests.map { $0.entity }
    }
}

extension ServerTest.ServerTestAppEntitiy.Query: EntityPropertyQuery {
    func entities(matching comparators: [Predicate<ServerTest.ServerTestAppEntitiy>], mode: ComparatorMode, sortedBy: [EntityQuerySort<ServerTest.ServerTestAppEntitiy>], limit: Int?) async throws -> [ServerTest.ServerTestAppEntitiy] {
        var orderClauses: [BlackbirdModelOrderClause<ServerTest>] = []
        for sortedBy in sortedBy.prefix(2) {
            let column : ServerTest.BlackbirdColumnKeyPath = column(for: sortedBy.by)
            let orderBy : BlackbirdModelOrderClause<ServerTest> = sortedBy.order == .ascending ? .ascending(column) : .descending(column)
            orderClauses.append(orderBy)
        }

        let db = SharedDatabase.db

        let serverTests = (
            try? await ServerTest.query(
                in: db,
                columns: [\.$id],
                matching: .like(\.$credentialKey, "[^-]"),
                orderBy: orderClauses.first ?? .ascending(\.$title), orderClauses.last ?? .ascending(\.$title)
            )
        ) ?? []
        var tests: [ServerTest] = []
        for serverTest in serverTests {
            guard let test = try? await ServerTest.read(from: db, id: serverTest[\.$id]) else {continue}
            tests.append(test)
        }

        return try Array(
            tests
                .map{$0.entity}
                .filter { test in
                    switch mode {
                    case .and:
                        try comparators.reduce(true) { partialResult, predicate in
                            try predicate.evaluate(test) && partialResult
                        }
                    case .or:
                        try comparators.reduce(false) { partialResult, predicate in
                            try predicate.evaluate(test) || partialResult
                        }
                    }
                }
                .prefix(limit ?? Int.max)
        )

    }
    func column(for keyPath: PartialKeyPath<ServerTest.ServerTestAppEntitiy>) -> ServerTest.BlackbirdColumnKeyPath {
        return switch keyPath {
        case \.$title:
            \.$title
        case \.$notes:
            \.$notes
        case \.$command:
            \.$command
        case \.$output:
            \.$output
        case \.$status:
            \.$status
        default:
            \.$title
        }
    }
}


extension ServerTest.ServerTestAppEntitiy: IndexedEntity {
    static func updateSpotlightIndex() async {
        guard CSSearchableIndex.isIndexingAvailable() else {
            return
        }
        let db = SharedDatabase.db

        let serverTests = (
            try? await ServerTest.query(
                in: db,
                columns: [\.$id],
                matching: .all,
                orderBy: .descending(\.$lastRun)
            )
        ) ?? []
        var tests: [ServerTest] = []
        for serverTest in serverTests {
            guard let test = try? await ServerTest.read(from: db, id: serverTest[\.$id]) else {continue}
            tests.append(test)
        }
        try! await CSSearchableIndex.default().indexAppEntities(tests.map{$0.entity})
    }
//    var attributeSet: CSSearchableItemAttributeSet{
//        let attributes = CSSearchableItemAttributeSet()
//
//        attributes.containerTitle = "Server Tests"
//        attributes.containerDisplayName = "Server Tests"
//        attributes.title = self.title
//        attributes.contentDescription = status.localizedDescription
//        attributes.keywords = ["Server Test", title, command, status.localizedDescription]
//        attributes.contentModificationDate = lastRun
//        attributes.displayName = title
//        attributes.creator = "ContainEye"
//        attributes.url = URL(string: "https://hannesnagel.com/open/containeye/test/\(id)/details")
//
//        return attributes
//    }
}

extension ServerTest.ServerTestAppEntitiy: URLRepresentableEntity {
    static var urlRepresentation: URLRepresentation {
        "https://hannesnagel.com/open/containeye/test/\(.id)/details"
    }
}

extension EntityQueryProperties<ServerTest.ServerTestAppEntitiy, Predicate<ServerTest.ServerTestAppEntitiy>> : @unchecked @retroactive Sendable{}

extension EntityQuerySortingOptions<ServerTest.ServerTestAppEntitiy> : @unchecked @retroactive Sendable {}
