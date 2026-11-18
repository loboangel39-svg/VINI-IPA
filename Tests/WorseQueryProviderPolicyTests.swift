import Darwin
import Foundation

@main
struct WorseQueryProviderPolicyTests {
    private static var failures = 0

    static func main() {
        // Existing verified range keeps bad_query first, with worse_query as a
        // permitted fallback because upstream supports these versions too.
        expect(
            decision(26, 0, 0, "23A344"),
            requested: .badQuery,
            order: [.badQuery, .worseQuery],
            compatible: true,
            verified: true,
            name: "iOS 26.0 keeps bad_query priority"
        )
        expect(
            decision(26, 6, 1, "23G80"),
            requested: .badQuery,
            order: [.badQuery, .worseQuery],
            compatible: true,
            verified: true,
            name: "iOS 26.6.1 keeps bad_query priority"
        )

        // Requested worse_query range inside upstream's declared support.
        expect(
            decision(26, 6, 2, "23G93"),
            requested: .worseQuery,
            order: [.worseQuery, .badQuery],
            compatible: true,
            verified: false,
            name: "iOS 26.6.2 requests worse_query"
        )
        expect(
            decision(26, 7, 2, "23H20"),
            requested: .worseQuery,
            order: [.worseQuery, .badQuery],
            compatible: true,
            verified: false,
            name: "iOS 26.7.2 requests worse_query"
        )

        // Outside both the requested map and upstream's ceiling.
        expect(
            decision(26, 7, 3, "23H30"),
            requested: .badQuery,
            order: [.badQuery],
            compatible: false,
            verified: false,
            name: "iOS 26.7.3 stays on bad_query"
        )

        // iOS 27.0 beta 1-4 are the only builds VINI can identify today.
        expect(
            decision(27, 0, 0, "24A5355q"),
            requested: .badQuery,
            order: [.badQuery, .worseQuery],
            compatible: true,
            verified: true,
            name: "iOS 27.0 beta 1 keeps bad_query priority"
        )
        expect(
            decision(27, 0, 0, "24A5390f"),
            requested: .badQuery,
            order: [.badQuery, .worseQuery],
            compatible: true,
            verified: true,
            name: "iOS 27.0 beta 4 keeps bad_query priority"
        )

        let unknownBeta = decision(27, 0, 0, "24A9999z")
        expect(
            unknownBeta,
            requested: .badQuery,
            order: [.badQuery, .worseQuery],
            compatible: true,
            verified: false,
            name: "Unknown iOS 27.0 build is not guessed to be beta 5+"
        )
        require(
            unknownBeta.notes.contains { $0.contains("not in VINI's verified beta table") },
            "Unknown iOS 27.0 build must record why the beta map was not applied"
        )

        // iOS 27.1/27.2 are inside upstream's declared ceiling.
        expect(
            decision(27, 1, 0, "24B100"),
            requested: .worseQuery,
            order: [.worseQuery, .badQuery],
            compatible: true,
            verified: false,
            name: "iOS 27.1 requests worse_query"
        )
        expect(
            decision(27, 2, 0, "24C100"),
            requested: .worseQuery,
            order: [.worseQuery, .badQuery],
            compatible: true,
            verified: false,
            name: "iOS 27.2 requests worse_query"
        )

        // Requested map says 27.3 beta 1, upstream says only through 27.2.
        // The conservative result is to retain bad_query and document why.
        let ios273 = decision(27, 3, 0, "24D100")
        expect(
            ios273,
            requested: .worseQuery,
            order: [.badQuery],
            compatible: false,
            verified: false,
            name: "iOS 27.3 does not use worse_query without upstream support"
        )
        require(
            ios273.notes.contains { $0.contains("only through iOS 27.2") },
            "iOS 27.3 conflict must be documented in the decision"
        )

        // Unknown future OS and older OS never invent worse_query support.
        expect(
            decision(28, 0, 0, "25A100"),
            requested: .badQuery,
            order: [.badQuery],
            compatible: false,
            verified: false,
            name: "iOS 28 stays on bad_query"
        )
        expect(
            decision(25, 9, 0, "22Z100"),
            requested: .badQuery,
            order: [.badQuery],
            compatible: false,
            verified: false,
            name: "iOS 25 never selects worse_query"
        )

        // Provider order is always sequential and has no duplicates.
        for version in [(26, 0, 0), (26, 6, 2), (27, 0, 0), (27, 3, 0), (28, 0, 0)] {
            let item = decision(version.0, version.1, version.2, "test")
            require(
                Set(item.attemptOrder).count == item.attemptOrder.count,
                "Provider order must not contain duplicates"
            )
            require(
                item.attemptOrder.count <= 2,
                "At most two providers may be attempted sequentially"
            )
        }

        if failures == 0 {
            print("PASS: all WorseQueryProviderPolicy tests")
            exit(0)
        } else {
            print("FAIL: \(failures) assertion(s)")
            exit(1)
        }
    }

    private static func decision(
        _ major: Int,
        _ minor: Int,
        _ patch: Int,
        _ build: String
    ) -> ContainerAccessProviderDecision {
        WorseQueryProviderPolicy.decision(
            major: major,
            minor: minor,
            patch: patch,
            build: build
        )
    }

    private static func expect(
        _ actual: ContainerAccessProviderDecision,
        requested: ContainerAccessProvider,
        order: [ContainerAccessProvider],
        compatible: Bool,
        verified: Bool,
        name: String
    ) {
        require(actual.requestedByMap == requested, "\(name): requestedByMap")
        require(actual.attemptOrder == order, "\(name): attemptOrder \(actual.attemptOrder)")
        require(
            actual.worseQueryCompatible == compatible,
            "\(name): worseQueryCompatible"
        )
        require(actual.mapVerified == verified, "\(name): mapVerified")
        print("PASS: \(name)")
    }

    private static func require(_ condition: Bool, _ message: String) {
        if condition {
            return
        }
        failures += 1
        print("FAIL: \(message)")
    }
}
