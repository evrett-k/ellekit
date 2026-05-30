import XCTest
@testable import ellekit

final class DecoderExtraTests: XCTestCase {
#if arch(x86_64)
    func testRejectsConditionalNearJump() {
        XCTAssertNil(x86_64InstructionLength([0x0F, 0x85, 0x01, 0x00, 0x00, 0x00], at: 0))
    }

    func testRejectsShortJump() {
        XCTAssertNil(x86_64InstructionLength([0xEB, 0x02, 0x90, 0x90], at: 0))
    }

    func testAcceptsModRMNoRip() {
        // mov rax, [rbx]  -> 48 8B 03
        XCTAssertEqual(x86_64InstructionLength([0x48, 0x8B, 0x03], at: 0), 3)
    }
#else
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
#endif
}
