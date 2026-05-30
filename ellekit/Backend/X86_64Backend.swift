// This file is licensed under the BSD-3 Clause License
// Copyright 2022 © ElleKit Team

import Foundation

#if arch(x86_64)

struct X86_64Backend: ElleKitBackend {
    let architecture: ElleKitArchitecture = .x86_64

    func hook(
        _ stockTarget: UnsafeMutableRawPointer,
        _ stockReplacement: UnsafeMutableRawPointer,
        _ internalSkipChecks: Bool
    ) -> UnsafeMutableRawPointer? {
        x86_64Hook(stockTarget, stockReplacement, internalSkipChecks)
    }
}

func x86_64Hook(
    _ stockTarget: UnsafeMutableRawPointer,
    _ stockReplacement: UnsafeMutableRawPointer,
    _ internalSkipChecks: Bool = false
) -> UnsafeMutableRawPointer? {

    let target = stockTarget.makeReadable()
    let replacement = stockReplacement.makeReadable()

    if let newReplacement = hooks[target], !internalSkipChecks {
        return hook(newReplacement.makeReadable(), replacement)
    }

    hooks[target] = replacement

    let patchSize = 12
    let targetSize = findFunctionSize(target, minimumSize: patchSize)

    guard let targetSize, targetSize >= patchSize else {
        print("[-] ellekit: x86_64 target is too small or unsafe to patch")
        hooks.removeValue(forKey: target)
        return nil
    }

    let orig = getOriginal(
        target,
        targetSize,
        desiredRebindSize: patchSize,
        shouldBranchAfter: true
    )

    let code = absoluteJump(to: replacement)
    let size = mach_vm_size_t(code.count)

    let ret = code.withUnsafeBufferPointer { buf in
        rawHook(address: target, code: buf.baseAddress, size: size)
    }

    if ret != 0 {
        hooks.removeValue(forKey: target)
        return nil
    }

    return orig.0?.makeCallable()
}

func isReturnInstruction(_ bytes: [UInt8], at offset: Int) -> Bool {
    var idx = offset
    while idx < bytes.count {
        let b = bytes[idx]
        switch b {
        case 0xF0, 0xF2, 0xF3, 0x2E, 0x36, 0x3E, 0x26, 0x64, 0x65, 0x66, 0x67:
            idx += 1
        case 0x40...0x4F:
            idx += 1
        default:
            let opcode = bytes[idx]
            return opcode == 0xC3 || opcode == 0xC2 || opcode == 0xCB || opcode == 0xCA || opcode == 0xC9
        }
    }
    return false
}

func findFunctionSize(_ target: UnsafeMutableRawPointer, minimumSize: Int = 12, maximumSize: Int = 128) -> Int? {
    let maxCount = max(0, maximumSize)
    let bytes = target.withMemoryRebound(to: UInt8.self, capacity: maxCount) { ptr in
        Array(UnsafeBufferPointer(start: ptr, count: maxCount))
    }

    var size = 0
    while size < bytes.count && size < maximumSize {
        let start = size
        guard let instructionLength = x86_64InstructionLength(bytes, at: start) else {
            return nil
        }

        size += instructionLength

        if isReturnInstruction(bytes, at: start) {
            return size
        }

        // If we've reached the minimum, keep scanning until we either find a return
        // or reach the maximumSize. This prevents stopping early before unsafe
        // instructions that may follow the minimum boundary.
        if size >= minimumSize {
            // continue scanning; loop termination will return size if no return found
            continue
        }
    }

    return size >= minimumSize ? size : nil
}

func getOriginal(
    _ target: UnsafeMutableRawPointer,
    _ size: Int,
    desiredRebindSize: Int,
    shouldBranchAfter: Bool = true,
    jmpReg: Register = .x16
) -> (UnsafeMutableRawPointer?, Int) {
    let trampolineSize = desiredRebindSize + 12

    // Read the original bytes up to `size` so we can decode safely
    let originalBytes = target.withMemoryRebound(to: UInt8.self, capacity: max(size, 1)) { ptr in
        Array(UnsafeBufferPointer(start: ptr, count: size))
    }

    var copied = 0
    var code: [UInt8] = []

    // Decode instruction-by-instruction, reject unsafe instructions
    while copied < desiredRebindSize {
        guard copied < originalBytes.count else { return (nil, 0) }
        guard let instLen = x86_64InstructionLength(originalBytes, at: copied) else {
            return (nil, 0)
        }

        // Ensure we don't copy past the provided function size
        if copied + instLen > size {
            return (nil, 0)
        }

        code.append(contentsOf: originalBytes[copied..<(copied + instLen)])
        copied += instLen
    }

    // Append an absolute jump back to the resume address
    let resumeAddress = UInt64(UInt(bitPattern: target) + UInt(copied))
    code.append(contentsOf: absoluteJumpBytes(to: resumeAddress))

    // Allocate trampoline page and copy code
    var address: mach_vm_address_t = 0
    mach_vm_allocate(mach_task_self_, &address, UInt64(vm_page_size), VM_FLAGS_ANYWHERE)
    mach_vm_protect(mach_task_self_, address, UInt64(vm_page_size), 0, VM_PROT_READ | VM_PROT_WRITE)

    guard let trampoline = UnsafeMutableRawPointer(bitPattern: UInt(address)) else {
        return (nil, 0)
    }

    _ = code.withUnsafeBufferPointer { buffer in
        memcpy(trampoline, buffer.baseAddress, code.count)
    }
    mach_vm_protect(mach_task_self_, mach_vm_address_t(UInt(bitPattern: trampoline)), UInt64(vm_page_size), 0, VM_PROT_READ | VM_PROT_EXECUTE)

    return (trampoline, shouldBranchAfter ? trampolineSize : code.count)
}

func absoluteJump(to pointer: UnsafeMutableRawPointer) -> [UInt8] {
    absoluteJumpBytes(to: UInt64(UInt(bitPattern: pointer)))
}

func absoluteJumpBytes(to address: UInt64) -> [UInt8] {
    var code: [UInt8] = [0x48, 0xB8]
    code.append(contentsOf: split(from: address))
    code.append(0xFF)
    code.append(0xE0)
    return code
}

func x86_64InstructionLength(_ bytes: [UInt8], at offset: Int) -> Int? {
    guard offset >= 0, offset < bytes.count else { return nil }

    var index = offset
    var rex: UInt8? = nil

    prefixLoop: while index < bytes.count {
        let byte = bytes[index]
        switch byte {
        case 0xF0, 0xF2, 0xF3, 0x2E, 0x36, 0x3E, 0x26, 0x64, 0x65, 0x66, 0x67:
            index += 1
        case 0x40...0x4F:
            rex = byte
            index += 1
        default:
            break prefixLoop
        }
    }

    guard index < bytes.count else { return nil }

    let opcode = bytes[index]
    index += 1

    switch opcode {
    case 0x55...0x5F, 0x90, 0xC3, 0xC9, 0xCC, 0xCB, 0xF4:
        return index - offset
    case 0xC2, 0xCA:
        return consume(&index, count: 2, bytes: bytes) ? index - offset : nil
    case 0x68:
        return consume(&index, count: 4, bytes: bytes) ? index - offset : nil
    case 0x6A:
        return consume(&index, count: 1, bytes: bytes) ? index - offset : nil
    case 0xB0...0xB7:
        return consume(&index, count: 1, bytes: bytes) ? index - offset : nil
    case 0xB8...0xBF:
        return consume(&index, count: (rex ?? 0) & 0x08 != 0 ? 8 : 4, bytes: bytes) ? index - offset : nil
    case 0xE8, 0xE9, 0xEB:
        return nil
    case 0x70...0x7F:
        return nil
    case 0x0F:
        guard index < bytes.count else { return nil }
        let extended = bytes[index]
        index += 1

        if (0x80...0x8F).contains(extended) {
            return nil
        }

        switch extended {
        case 0x05, 0x31, 0x34:
            return index - offset
        case 0x1F, 0xAF, 0xB6, 0xB7, 0xBE, 0xBF, 0xC1, 0xC7:
            return decodeModRMInstruction(bytes, offset: offset, index: index, opcode: opcode, extendedOpcode: extended)
        default:
            return nil
        }
    case 0x80, 0x81, 0x82, 0x83, 0x85, 0x87, 0x88, 0x89, 0x8A, 0x8B, 0x8D, 0x8F, 0x01, 0x03, 0x21, 0x23, 0x29, 0x2B, 0x31, 0x33, 0x39, 0x3B, 0x63, 0x69, 0x6B, 0xC6, 0xC7, 0xF6, 0xF7, 0xFE, 0xFF:
        return decodeModRMInstruction(bytes, offset: offset, index: index, opcode: opcode, extendedOpcode: nil)
    default:
        return nil
    }
}

func decodeModRMInstruction(
    _ bytes: [UInt8],
    offset: Int,
    index: Int,
    opcode: UInt8,
    extendedOpcode: UInt8?
) -> Int? {
    var cursor = index
    guard cursor < bytes.count else { return nil }

    let modRM = bytes[cursor]
    cursor += 1

    let mod = modRM >> 6
    let reg = (modRM >> 3) & 0x07
    let rm = modRM & 0x07

    if opcode == 0xFF, [2, 4, 5].contains(reg) {
        return nil
    }

    if mod != 3 {
        if rm == 4 {
            guard cursor < bytes.count else { return nil }
            let sib = bytes[cursor]
            cursor += 1
            let base = sib & 0x07
            if mod == 0 && base == 5 {
                guard consume(&cursor, count: 4, bytes: bytes) else { return nil }
            } else if mod == 1 {
                guard consume(&cursor, count: 1, bytes: bytes) else { return nil }
            } else if mod == 2 {
                guard consume(&cursor, count: 4, bytes: bytes) else { return nil }
            }
        } else if mod == 0 && rm == 5 {
            return nil
        } else if mod == 1 {
            guard consume(&cursor, count: 1, bytes: bytes) else { return nil }
        } else if mod == 2 {
            guard consume(&cursor, count: 4, bytes: bytes) else { return nil }
        }
    }

    switch opcode {
    case 0x80, 0x82, 0x83:
        guard consume(&cursor, count: 1, bytes: bytes) else { return nil }
    case 0x81, 0x69, 0xC7:
        guard consume(&cursor, count: 4, bytes: bytes) else { return nil }
    case 0x6B, 0xC6:
        guard consume(&cursor, count: 1, bytes: bytes) else { return nil }
    case 0xF6:
        if [0, 1].contains(reg) {
            guard consume(&cursor, count: 1, bytes: bytes) else { return nil }
        }
    case 0xF7:
        if [0, 1].contains(reg) {
            guard consume(&cursor, count: 4, bytes: bytes) else { return nil }
        }
    case 0x0F:
        guard let extendedOpcode else { return nil }
        if extendedOpcode == 0xBA || extendedOpcode == 0xC2 {
            guard consume(&cursor, count: 1, bytes: bytes) else { return nil }
        }
    default:
        break
    }

    guard cursor <= bytes.count else { return nil }
    return cursor - offset
}

func consume(_ cursor: inout Int, count: Int, bytes: [UInt8]) -> Bool {
    guard count >= 0, cursor + count <= bytes.count else { return false }
    cursor += count
    return true
}

#endif