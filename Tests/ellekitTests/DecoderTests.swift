import XCTest
@testable import ellekit

final class DecoderTests: XCTestCase {
#if arch(x86_64)
    func withBuffer(_ bytes: [UInt8], _ body: (UnsafeMutableRawPointer) -> Void) {
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
        ptr.initialize(from: bytes, count: bytes.count)
        body(UnsafeMutableRawPointer(ptr))
        ptr.deinitialize(count: bytes.count)
        ptr.deallocate()
    }

    func testSimplePrologue() {
        let bytes: [UInt8] = [0x55, 0x48, 0x89, 0xE5, 0x90, 0xC3]
        withBuffer(bytes) { buf in
            let size = findFunctionSize(buf, minimumSize: 4)
            XCTAssertEqual(size, 6)
        }
    }

    func testRejectRelativeCall() {
        let bytes: [UInt8] = [0xE8, 0x01, 0x02, 0x03, 0x04, 0xC3]
        XCTAssertNil(x86_64InstructionLength(bytes, at: 0))
    }
#else
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
#endif
}
