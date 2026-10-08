import XCTest
@testable import CodexIsland

final class CubeGlowTests: XCTestCase {
    func testGlowTracksLitCellAcrossRandomCycles() {
        for seed in 0..<6 {
            for sample in 0..<240 {
                let elapsed = Double(sample) / 60
                for index in 0..<9 {
                    let glow = CubeTimeline.glow(index: index, elapsed: elapsed, seed: seed,
                                                 state: .thinking, enabled: true)
                    let intensity = CubeTimeline.intensity(index: index, elapsed: elapsed, seed: seed, state: .thinking)
                    XCTAssertEqual(glow, (intensity - 0.64) / 0.36, accuracy: 0.00001)
                    XCTAssertTrue((0...1).contains(glow))
                }
            }
        }
    }

    func testGlowStopsOutsideSolvingAndWhenMotionDisabled() {
        for state in ActivityState.allCases {
            let glow = CubeTimeline.glow(index: 0, elapsed: 0.05, seed: 0, state: state, enabled: true)
            if !state.isActive || state.needsAttention { XCTAssertEqual(glow, 0) }
            XCTAssertEqual(CubeTimeline.glow(index: 0, elapsed: 0.05, seed: 0,
                                            state: state, enabled: false), 0)
        }
    }

    func testAllStatesHaveExplicitActivityBudgets() {
        let expected: [ActivityState: Int] = [
            .starting: 1, .reading: 1, .writing: 1,
            .planning: 2, .thinking: 2,
            .scanning: 3, .searching: 3, .editing: 3, .running: 3,
            .waitingForInput: 0, .attentionRequired: 0, .completed: 0,
            .failed: 0, .cancelled: 0, .idle: 0
        ]
        XCTAssertEqual(expected.count, ActivityState.allCases.count)
        for state in ActivityState.allCases {
            XCTAssertEqual(CubeTimeline.litCellCount(for: state), expected[state])
        }
    }

    func testDistinctLitCellsRespectBudgetAndVisitEntireFace() {
        for state in ActivityState.allCases where CubeTimeline.litCellCount(for: state) > 0 {
            for seed in 0..<6 {
                var visited = Set<Int>()
                for step in 0..<27 {
                    let time = Double(step) * 0.22 + 0.05
                    let lit = (0..<9).filter {
                        CubeTimeline.glow(index: $0, elapsed: time, seed: seed, state: state, enabled: true) > 0.99
                    }
                    XCTAssertEqual(lit.count, CubeTimeline.litCellCount(for: state))
                    visited.formUnion(lit)
                }
                XCTAssertEqual(visited, Set(0..<9))
                for sample in 0..<600 {
                    let lit = (0..<9).filter {
                        CubeTimeline.glow(index: $0, elapsed: Double(sample) / 120,
                                          seed: seed, state: state, enabled: true) > 0
                    }
                    XCTAssertLessThanOrEqual(lit.count, CubeTimeline.litCellCount(for: state))
                }
            }
        }
    }

    func testStateChangesSharePhaseAndAreDeterministic() {
        for step in 0..<18 {
            let time = Double(step) * 0.22 + 0.05
            let light = (0..<9).filter { CubeTimeline.solvingPulse(index: $0, elapsed: time, seed: 4, state: .starting) > 0 }
            let heavy = (0..<9).filter { CubeTimeline.solvingPulse(index: $0, elapsed: time, seed: 4, state: .searching) > 0 }
            XCTAssertTrue(Set(light).isSubset(of: Set(heavy)))
            for index in 0..<9 {
                XCTAssertEqual(CubeTimeline.solvingPulse(index: index, elapsed: time, seed: 4, state: .searching),
                               CubeTimeline.solvingPulse(index: index, elapsed: time, seed: 4, state: .running))
            }
        }
    }
}
