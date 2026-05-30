import XCTest
@testable import ellekit

#if arch(x86_64)
final class X86_64BackendSafetyTests: XCTestCase {
    func testInstructionLengthAcceptsSimpleInstructions() {
        XCTAssertEqual(x86_64InstructionLength([0x90], at: 0), 1)
        XCTAssertEqual(x86_64InstructionLength([0x55], at: 0), 1)
        XCTAssertEqual(x86_64InstructionLength([0x48, 0xB8, 0, 1, 2, 3, 4, 5, 6, 7], at: 0), 10)
    }

    func testInstructionLengthRejectsRelativeControlFlow() {
        XCTAssertNil(x86_64InstructionLength([0xE8, 0x11, 0x22, 0x33, 0x44], at: 0))
        XCTAssertNil(x86_64InstructionLength([0xE9, 0x11, 0x22, 0x33, 0x44], at: 0))
        XCTAssertNil(x86_64InstructionLength([0x74, 0x02], at: 0))
    }

    func testInstructionLengthRejectsRipRelativeMemoryAccess() {
        XCTAssertNil(x86_64InstructionLength([0x48, 0x8B, 0x05, 0x11, 0x22, 0x33, 0x44], at: 0))
    }

    func testFunctionSizeStopsOnUnsafeStream() {
        let bytes: [UInt8] = [
            0x55,
            0x48, 0x89, 0xE5,
            0x48, 0x8B, 0x05, 0x11, 0x22, 0x33, 0x44
        ]

        let size = bytes.withUnsafeBufferPointer { buffer -> Int? in
            guard let base = buffer.baseAddress else { return nil }
            return findFunctionSize(UnsafeMutableRawPointer(mutating: base), minimumSize: 4, maximumSize: bytes.count)
        }

        XCTAssertNil(size)
    }
}
#else
final class X86_64BackendSafetyTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
#endif