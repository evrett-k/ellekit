import XCTest
@testable import ellekit
import Darwin

final class HookIntegrationTests: XCTestCase {
#if arch(x86_64)
    func allocateExecutableBuffer(_ bytes: [UInt8]) -> UnsafeMutableRawPointer {
        let ptr = UnsafeMutableRawPointer(malloc(bytes.count))!
        _ = bytes.withUnsafeBufferPointer { buf in
            memcpy(ptr, buf.baseAddress, bytes.count)
        }

        let page = Int(vm_page_size)
        let start = Int(bitPattern: ptr) & ~(page - 1)
        let res = mprotect(UnsafeMutableRawPointer(bitPattern: start), page, PROT_READ | PROT_WRITE | PROT_EXEC)
        XCTAssertEqual(res, 0)
        return ptr
    }

    func testTrampolineReturnsImmediate() {
        // mov rax, imm64; ret
        let imm: UInt64 = 42
        var code: [UInt8] = [0x48, 0xB8]
        code.append(contentsOf: withUnsafeBytes(of: imm.littleEndian) { Array($0) })
        code.append(0xC3)

        let target = allocateExecutableBuffer(code)

        let orig = getOriginal(target, code.count, desiredRebindSize: code.count, shouldBranchAfter: false)
        XCTAssertNotNil(orig.0)

        let trampoline = orig.0!
        typealias Fn = @convention(c) () -> Int64
        let f = unsafeBitCast(trampoline, to: Fn.self)
        let ret = f()
        XCTAssertEqual(ret, 42)
    }
#else
    func testPlaceholderIntegration() { XCTAssertTrue(true) }
#endif
}
