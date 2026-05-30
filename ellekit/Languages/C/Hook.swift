
// This file is licensed under the BSD-3 Clause License
// Copyright 2022 © ElleKit Team

import Foundation

#if SWIFT_PACKAGE
import ellekitc
#endif

public func patchFunction(_ function: UnsafeMutableRawPointer, @InstructionBuilder _ instructions: () -> [UInt8]) {

    let code = instructions()

    let size = mach_vm_size_t(MemoryLayout.size(ofValue: code) * code.count) / 8

    code.withUnsafeBufferPointer { buf in
        let result = rawHook(address: function.makeReadable(), code: buf.baseAddress, size: size)
        #if DEBUG
        print(result)
        #else
        _ = result
        #endif
    }
}

@_cdecl("EKHookFunction")
public func hook(_ stockTarget: UnsafeMutableRawPointer, _ stockReplacement: UnsafeMutableRawPointer, _ internalSkipChecks: Bool = false) -> UnsafeMutableRawPointer? {
    activeBackend.hook(stockTarget, stockReplacement, internalSkipChecks)
}
