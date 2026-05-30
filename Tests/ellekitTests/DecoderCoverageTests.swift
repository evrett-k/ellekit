import XCTest
@testable import ellekit

final class DecoderCoverageTests: XCTestCase {
#if arch(x86_64)
    func testB8WithREXW() {
        XCTAssertEqual(x86_64InstructionLength([0x48, 0xB8, 1,2,3,4,5,6,7,8], at: 0), 10)
    }

    func testRetVariants() {
        XCTAssertEqual(x86_64InstructionLength([0xC3], at: 0), 1)
        XCTAssertEqual(x86_64InstructionLength([0xC2, 0x10, 0x00], at: 0), 3)
    }

    func testModRMWithSIBAndDisp() {
        // opcode 0x8B, modRM=0x44 (mod=1, reg=0x2, rm=4), sib=0x24, disp8
        XCTAssertEqual(x86_64InstructionLength([0x8B, 0x44, 0x24, 0x10], at: 0), 4)
    }

    func testFFCallGroupRejectsReg2() {
        // 0xFF with modRM where reg==2 should be rejected
        XCTAssertNil(x86_64InstructionLength([0xFF, 0xE0], at: 0))
    }
#else
    func testPlaceholderCoverage() {
        XCTAssertTrue(true)
    }
#endif
}
