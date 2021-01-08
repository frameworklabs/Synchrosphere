// Project Synchrosphere
// Copyright 2021, Framework Labs.

import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(SynchrosphereTests.allTests),
    ]
}
#endif
