// This file is licensed under the BSD-3 Clause License
// Copyright 2022 © ElleKit Team

import Foundation

#if SWIFT_PACKAGE
import ellekitc
#endif

func split(from uint64: UInt64) -> [UInt8] {
    var result = [UInt8]()
    
    for i in 0..<8 {
        let byte = UInt8((uint64 >> (i * 8)) & 0xFF)
        result.append(byte)
    }
    
    return result
}

@discardableResult @_optimize(speed)
func rawHook(address: UnsafeMutableRawPointer, code: UnsafePointer<UInt8>?, size: mach_vm_size_t) -> Int {
    
    //NSLog("[hookinfo] patching \(String(describing: address)) with \(code == nil ? "nothing!" : Array(UnsafeBufferPointer(start: code, count: Int(size))).map {String(format: "%02X", $0)}.joined())")
    
    let enforceThreadSafety = enforceThreadSafety
    if enforceThreadSafety {
        stopAllThreads()
    }
    defer {
        if enforceThreadSafety {
            resumeAllThreads()
        }
    }

    return Int(EKHookMemoryRaw(address, code, Int(size)))
}