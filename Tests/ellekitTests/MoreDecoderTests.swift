import XCTest
@testable import ellekit

final class MoreDecoderTests: XCTestCase {
#if arch(x86_64)
    func testAcceptsImmediatePushAndRet() {
        XCTAssertEqual(x86_64InstructionLength([0x6A, 0x10], at: 0), 2)
        XCTAssertEqual(x86_64InstructionLength([0x68, 0x01,0x02,0x03,0x04], at: 0), 5)
    }

    func testRejectsConditionalJump() {
        XCTAssertNil(x86_64InstructionLength([0x75, 0x02], at: 0))
    }
#else
    func testPlaceholderMore() {
        XCTAssertTrue(true)
    }
#endif
}
