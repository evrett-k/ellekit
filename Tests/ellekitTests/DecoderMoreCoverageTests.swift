import XCTest
@testable import ellekit

final class DecoderMoreCoverageTests: XCTestCase {
#if arch(x86_64)
    func testRejectsTwoByteConditionalNearJump() {
        // 0x0F 0x8C is a 32-bit conditional near jump (JL)
        let bytes: [UInt8] = [0x0F, 0x8C, 0x01, 0x00, 0x00, 0x00]
        XCTAssertNil(x86_64InstructionLength(bytes, at: 0))
    }

    func testRejectsShortConditionalJump() {
        // 0x7C is JL short (8-bit displacement)
        let bytes: [UInt8] = [0x7C, 0x05]
        XCTAssertNil(x86_64InstructionLength(bytes, at: 0))
    }

    func testAcceptsModRMNoRip() {
        // MOV rax, [rbx] encoded as: 0x48 0x8B 0x03
        let bytes: [UInt8] = [0x48, 0x8B, 0x03, 0xC3]
        XCTAssertEqual(x86_64InstructionLength(bytes, at: 0), 3)
    }

    func testRejectsRipRelativeLEA() {
        // LEA rax, [RIP + disp32] -> 0x8D 0x05 <disp32>
        let bytes: [UInt8] = [0x8D, 0x05, 0x01, 0x00, 0x00, 0x00]
        XCTAssertNil(x86_64InstructionLength(bytes, at: 0))
    }

    func testAcceptsSIBWithDisp() {
        // opcode 0x8B, modRM=0x44 (mod=1, rm=4 -> SIB), sib=0x24, disp8
        XCTAssertEqual(x86_64InstructionLength([0x8B, 0x44, 0x24, 0x10], at: 0), 4)
    }
#else
    func testPlaceholderMoreCoverage() {
        XCTAssertTrue(true)
    }
#endif
}
