//
//  EvaluationTargetingTests.swift
//  AmplitudeCoreTests
//
//  Created by Jin Xu on 9/25/26.
//
//  Session Replay targeting scenarios, written against the SPI surface only
//  (no @testable), the way Session Replay calls the engine. Every expected value
//  was produced by @amplitude/experiment-core 0.13.6, the JS reference
//  implementation, on the same flags and contexts.
//

import Foundation
import XCTest
@_spi(Internal) import AmplitudeCore

final class EvaluationTargetingTests: XCTestCase {

    private let engine = EvaluationEngine()

    // MARK: - Conditions

    func testEventTypeCondition() throws {
        let flag = try conditionFlag([(["context", "event", "event_type"], "is", ["Signup Started"])])
        XCTAssertEqual(evaluate(flag, context(eventType: "Signup Started")), "on")
        XCTAssertEqual(evaluate(flag, context(eventType: "Search")), "off")
    }

    func testFalsyPropertyValuesMatch() throws {
        let zero = try conditionFlag([(property("count"), "is", ["0"])])
        XCTAssertEqual(evaluate(zero, context(eventProperties: ["count": 0])), "on")
        let falseValue = try conditionFlag([(property("premium"), "is", ["false"])])
        XCTAssertEqual(evaluate(falseValue, context(eventProperties: ["premium": false])), "on")
        let empty = try conditionFlag([(property("name"), "is", [""])])
        XCTAssertEqual(evaluate(empty, context(eventProperties: ["name": ""])), "on")
    }

    func testArrayPropertyWithNonSetOperators() throws {
        let isFlag = try conditionFlag([(property("tags"), "is", ["b"])])
        XCTAssertEqual(evaluate(isFlag, context(eventProperties: ["tags": ["a", "b"]])), "on")
        let containsFlag = try conditionFlag([(property("tags"), "contains", ["sal"])])
        XCTAssertEqual(evaluate(containsFlag, context(eventProperties: ["tags": ["summer-sale"]])), "on")
    }

    func testEventTypesSeenInSession() throws {
        let flag = try conditionFlag([(["context", "event_types"], "set contains", ["Signup Started"])])
        XCTAssertEqual(evaluate(flag, context(eventType: "Checkout", eventTypes: ["Session Start", "Signup Started"])), "on")
        XCTAssertEqual(evaluate(flag, context(eventType: "Checkout", eventTypes: ["Session Start"])), "off")
    }

    func testConditionsWithinGroupAreAnded() throws {
        let flag = try conditionFlag([
            (["context", "event", "event_type"], "is", ["Signup Started"]),
            (["context", "user", "user_properties", "plan"], "is", ["Pro"]),
        ])
        XCTAssertEqual(evaluate(flag, context(eventType: "Signup Started", userProperties: ["plan": "Pro"])), "on")
        XCTAssertEqual(evaluate(flag, context(eventType: "Signup Started", userProperties: ["plan": "Free"])), "off")
        XCTAssertEqual(evaluate(flag, context(eventType: "Search", userProperties: ["plan": "Pro"])), "off")
    }

    func testGroupsAreOred() throws {
        let flag = try decodeFlag("""
        {"key":"sr_ios_targeting_config","variants":{"on":{"key":"on"},"off":{"key":"off"}},
         "segments":[{"conditions":[[{"selector":["context","event","event_type"],"op":"is","values":["A"]}],
                                    [{"selector":["context","event","event_type"],"op":"is","values":["B"]}]],
                      "variant":"on"},{"variant":"off"}]}
        """)
        XCTAssertEqual(evaluate(flag, context(eventType: "A")), "on")
        XCTAssertEqual(evaluate(flag, context(eventType: "B")), "on")
        XCTAssertEqual(evaluate(flag, context(eventType: "C")), "off")
    }

    func testOperators() throws {
        XCTAssertEqual(evaluate(try conditionFlag([(property("missing"), "is not", ["x"])]), context()), "on")
        XCTAssertEqual(evaluate(try conditionFlag([(property("amount"), "greater", ["99.5"])]),
                                context(eventProperties: ["amount": 100])), "on")
        XCTAssertEqual(evaluate(try conditionFlag([(["context", "user", "user_properties", "app_version"],
                                                    "version greater or equal", ["2.10.0"])]),
                                context(userProperties: ["app_version": "2.9.3"])), "off")
        XCTAssertEqual(evaluate(try conditionFlag([(property("path"), "regex match", [#"^/checkout/\d+$"#])]),
                                context(eventProperties: ["path": "/checkout/42"])), "on")
    }

    func testUnknownOperatorNeverMatches() throws {
        let flag = try conditionFlag([(["context", "event", "event_type"], "no such operator", ["X"])])
        XCTAssertEqual(evaluate(flag, context(eventType: "X")), "off")
    }

    func testBridgedNumbersFromJSONSerialization() throws {
        let properties = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(#"{"count":1,"premium":true,"ratio":0.5}"#.utf8)) as? [String: Any])
        let bridged = context(eventProperties: properties)
        XCTAssertEqual(evaluate(try conditionFlag([(property("count"), "is", ["1"])]), bridged), "on")
        XCTAssertEqual(evaluate(try conditionFlag([(property("count"), "is", ["true"])]), bridged), "off")
        XCTAssertEqual(evaluate(try conditionFlag([(property("premium"), "is", ["true"])]), bridged), "on")
        XCTAssertEqual(evaluate(try conditionFlag([(property("ratio"), "less", ["1"])]), bridged), "on")
    }

    // MARK: - Result metadata

    func testResultCarriesTheMatchedSegmentsMetadata() throws {
        // Shaped as the SR config service generates it: every segment names itself in its metadata.
        let flag = try decodeFlag(#"""
        {"key": "sr_ios_targeting_config", "metadata": {"evaluationMode": "local"},
         "variants": {"on": {"key": "on"}, "off": {"key": "off"}},
         "segments": [
           {"metadata": {"segmentName": "signup", "segmentId": "uuid1"},
            "conditions": [[{"selector": ["context", "event", "event_type"], "op": "is", "values": ["Signup Started"]}]],
            "variant": "on"},
           {"metadata": {"segmentName": "default random sample", "segmentId": "__internal_random_sample__"},
            "variant": "on"},
           {"variant": "off"}]}
        """#)
        let condition = engine.evaluate(context: context(eventType: "Signup Started"), flags: [flag])["sr_ios_targeting_config"]
        XCTAssertEqual(metadata(condition, "segmentId"), "uuid1")
        XCTAssertEqual(metadata(condition, "segmentName"), "signup")
        // Flag metadata is merged in as well.
        XCTAssertEqual(metadata(condition, "evaluationMode"), "local")

        let randomSample = engine.evaluate(context: context(eventType: "Search"), flags: [flag])["sr_ios_targeting_config"]
        XCTAssertEqual(metadata(randomSample, "segmentId"), "__internal_random_sample__")
    }

    private func metadata(_ variant: EvaluationVariant?, _ key: String) -> String? {
        guard case .string(let value)? = variant?.metadata?[key] else {
            return nil
        }
        return value
    }

    // MARK: - Web targeting config

    /// `flagConfig` from Amplitude-TypeScript `packages/session-replay-browser/test/flag-config-data.ts`.
    private let webTargetingConfig = #"""
{
  "key": "sr_targeting_config",
  "variants": {
    "on": {
      "key": "on"
    },
    "off": {
      "key": "off"
    }
  },
  "segments": [
    {
      "metadata": {
        "segmentName": "sign in trigger"
      },
      "bucket": {
        "selector": [
          "context",
          "session_id"
        ],
        "salt": "xdfrewd",
        "allocations": [
          {
            "range": [
              0,
              99
            ],
            "distributions": [
              {
                "variant": "on",
                "range": [
                  0,
                  42949673
                ]
              }
            ]
          }
        ]
      },
      "conditions": [
        [
          {
            "selector": [
              "context",
              "event",
              "event_type"
            ],
            "op": "is",
            "values": [
              "Sign In"
            ]
          }
        ]
      ]
    },
    {
      "metadata": {
        "segmentName": "user property"
      },
      "bucket": {
        "selector": [
          "context",
          "session_id"
        ],
        "salt": "Rpr5h4vy",
        "allocations": [
          {
            "range": [
              0,
              99
            ],
            "distributions": [
              {
                "variant": "on",
                "range": [
                  0,
                  42949673
                ]
              }
            ]
          }
        ]
      },
      "conditions": [
        [
          {
            "selector": [
              "context",
              "user",
              "user_properties",
              "country"
            ],
            "op": "set contains any",
            "values": [
              "united states"
            ]
          }
        ]
      ]
    },
    {
      "metadata": {
        "segmentName": "leftover allocation"
      },
      "bucket": {
        "selector": [
          "context",
          "session_id"
        ],
        "salt": "T5lhyRo",
        "allocations": [
          {
            "range": [
              0,
              9
            ],
            "distributions": [
              {
                "variant": "on",
                "range": [
                  0,
                  42949673
                ]
              }
            ]
          }
        ]
      }
    },
    {
      "variant": "off"
    }
  ]
}
"""#

    func testWebTargetingConfigSignInTrigger() throws {
        let flag = try decodeFlag(webTargetingConfig)
        let variants = sessionVariants(flag, key: webKey, eventType: "Sign In", count: 400)
        XCTAssertEqual(indices(of: "off", in: variants), [338, 353, 377])
        XCTAssertEqual(indices(of: "on", in: variants).count, 397)
    }

    func testWebTargetingConfigFallsThroughToLaterSegment() throws {
        // Session 49 matches the 'sign in trigger' conditions but misses its allocation, so it
        // continues to the 'leftover allocation' segment, which selects it.
        let full = try decodeFlag(webTargetingConfig)
        let triggerOnly = try decodeFlag(webTargetingConfig, keepingSegments: [0])
        let session49 = context(sessionId: firstSessionId + 49 * sessionStep, eventType: "Sign In")
        XCTAssertEqual(evaluate(triggerOnly, session49, key: webKey), "off")
        XCTAssertEqual(evaluate(full, session49, key: webKey), "on")
    }

    func testWebTargetingConfigUserPropertySet() throws {
        let flag = try decodeFlag(webTargetingConfig)
        let variants = sessionVariants(flag, key: webKey, eventType: "Browse",
                                       userProperties: ["country": ["united states"]], count: 400)
        XCTAssertEqual(indices(of: "off", in: variants), [56, 71, 126, 148, 158])
        XCTAssertEqual(indices(of: "on", in: variants).count, 395)
    }

    func testWebTargetingConfigLeftoverAllocation() throws {
        let flag = try decodeFlag(webTargetingConfig)
        // A plain string never satisfies a set operator, so these sessions only reach the
        // 'leftover allocation' segment, which selects a salted subset of sessions.
        let leftover = [13, 19, 22, 25, 38, 49, 58, 68, 69, 104, 109, 112, 116, 123, 127, 135, 139, 144, 145, 149,
                        178, 185, 207, 214, 219, 227, 233, 260, 264, 278, 305, 310, 326, 329, 337, 352, 356, 361,
                        373, 376, 384, 393, 394]
        let plainString = sessionVariants(flag, key: webKey, eventType: "Browse",
                                          userProperties: ["country": "united states"], count: 400)
        XCTAssertEqual(indices(of: "on", in: plainString), leftover)
        let otherCountry = sessionVariants(flag, key: webKey, eventType: "Browse",
                                           userProperties: ["country": ["canada"]], count: 400)
        XCTAssertEqual(indices(of: "on", in: otherCountry), leftover)
    }

    // MARK: - Bucketing

    private let twentyPercentConfig = #"""
{
  "key": "sr_ios_targeting_config",
  "variants": {
    "on": {
      "key": "on"
    },
    "off": {
      "key": "off"
    }
  },
  "segments": [
    {
      "metadata": {
        "segmentName": "signup"
      },
      "bucket": {
        "selector": [
          "context",
          "session_id"
        ],
        "salt": "trc-salt",
        "allocations": [
          {
            "range": [
              0,
              20
            ],
            "distributions": [
              {
                "variant": "on",
                "range": [
                  0,
                  42949673
                ]
              }
            ]
          }
        ]
      },
      "conditions": [
        [
          {
            "selector": [
              "context",
              "event",
              "event_type"
            ],
            "op": "is",
            "values": [
              "Signup Started"
            ]
          }
        ]
      ]
    },
    {
      "variant": "off"
    }
  ]
}
"""#

    func testSessionBucketing() throws {
        let flag = try decodeFlag(twentyPercentConfig)
        let matching = sessionVariants(flag, key: iosKey, eventType: "Signup Started", count: 100)
        XCTAssertEqual(indices(of: "on", in: matching), [8, 10, 11, 29, 31, 35, 37, 39, 40, 46, 47, 49, 50, 53, 57, 65, 68, 70, 91, 93, 97])
        let notMatching = sessionVariants(flag, key: iosKey, eventType: "Search", count: 100)
        XCTAssertEqual(indices(of: "on", in: notMatching), [])
    }

    func testSessionBucketingFallbacks() throws {
        let flag = try decodeFlag(twentyPercentConfig)
        let event: [String: Any?] = ["event_type": "Signup Started"]
        // Without a usable bucketing value the segment has no default variant, so it falls through to off.
        XCTAssertEqual(evaluate(flag, ["event": event], key: iosKey), "off")
        XCTAssertEqual(evaluate(flag, ["session_id": nil, "event": event], key: iosKey), "off")
        XCTAssertEqual(evaluate(flag, ["session_id": "", "event": event], key: iosKey), "off")
        // Zero is an ordinary bucketing value and is hashed like any other.
        XCTAssertEqual(evaluate(flag, ["session_id": Int64(0), "event": event], key: iosKey), "off")
        // A numeric session id and its string form land in the same bucket.
        let sessionId = firstSessionId + 8 * sessionStep
        XCTAssertEqual(evaluate(flag, ["session_id": sessionId, "event": event], key: iosKey), "on")
        XCTAssertEqual(evaluate(flag, ["session_id": String(sessionId), "event": event], key: iosKey), "on")
    }

    // MARK: - Helpers

    private let iosKey = "sr_ios_targeting_config"
    private let webKey = "sr_targeting_config"
    private let firstSessionId: Int64 = 1_726_380_000_000
    private let sessionStep: Int64 = 7_919

    /// Variant key for each of `count` consecutive sessions. Fails the test if any session gets
    /// something other than "on" or "off", so a missing result cannot pass as "not on".
    private func sessionVariants(_ flag: EvaluationFlag, key: String, eventType: String,
                                 userProperties: [String: Any?] = [:], count: Int,
                                 file: StaticString = #filePath, line: UInt = #line) -> [String?] {
        let variants: [String?] = (0..<count).map { index in
            let sessionId = firstSessionId + Int64(index) * sessionStep
            return evaluate(flag, context(sessionId: sessionId, eventType: eventType, eventTypes: [eventType],
                                          userProperties: userProperties), key: key)
        }
        XCTAssertTrue(variants.allSatisfy { $0 == "on" || $0 == "off" }, "every session resolves to on or off",
                      file: file, line: line)
        return variants
    }

    private func indices(of variant: String, in variants: [String?]) -> [Int] {
        return variants.indices.filter { variants[$0] == variant }
    }

    private func evaluate(_ flag: EvaluationFlag, _ context: [String: Any?],
                          key: String = "sr_ios_targeting_config") -> String? {
        return engine.evaluate(context: context, flags: [flag])[key]?.key
    }

    private func context(sessionId: Int64 = 1_726_380_000_000,
                         eventType: String = "X",
                         eventProperties: [String: Any] = [:],
                         eventTypes: [String] = [],
                         userProperties: [String: Any?] = [:]) -> [String: Any?] {
        return [
            "session_id": sessionId,
            "event": ["event_type": eventType, "event_properties": eventProperties] as [String: Any?],
            "event_types": eventTypes,
            "user": ["device_id": "d", "user_properties": userProperties] as [String: Any?],
        ]
    }

    private func property(_ name: String) -> [String] {
        return ["context", "event", "event_properties", name]
    }

    /// One segment whose conditions all sit in a single AND group, falling back to `off`.
    private func conditionFlag(_ conditions: [([String], String, [String])]) throws -> EvaluationFlag {
        let group: [[String: Any]] = conditions.map { selector, op, values in
            ["selector": selector, "op": op, "values": values]
        }
        let json: [String: Any] = [
            "key": "sr_ios_targeting_config",
            "variants": ["on": ["key": "on"], "off": ["key": "off"]],
            "segments": [["conditions": [group], "variant": "on"], ["variant": "off"]],
        ]
        return try JSONDecoder().decode(EvaluationFlag.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func decodeFlag(_ json: String) throws -> EvaluationFlag {
        return try JSONDecoder().decode(EvaluationFlag.self, from: Data(json.utf8))
    }

    /// Decodes `json` keeping only the segments at `keepingSegments`, followed by an `off` fallback.
    private func decodeFlag(_ json: String, keepingSegments kept: [Int]) throws -> EvaluationFlag {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let segments = try XCTUnwrap(object["segments"] as? [Any])
        object["segments"] = kept.map { segments[$0] } + [["variant": "off"]]
        return try JSONDecoder().decode(EvaluationFlag.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
