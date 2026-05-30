// This file is licensed under the BSD-3 Clause License
// Copyright 2022 © ElleKit Team

import Foundation

public struct Trampoline {
    var base: UnsafeMutableRawPointer
    var target: UnsafeMutableRawPointer
    var trampolineCode: [UInt8] = []
    
    public var trampoline: UnsafeMutableRawPointer = UnsafeMutableRawPointer(bitPattern: -2)!
    public var orig: UnsafeMutableRawPointer? = nil
    
    public init?(base: UnsafeMutableRawPointer, target: UnsafeMutableRawPointer) {
        
        #if DEBUG
        #else
        return nil;
        #endif
        
        var info = Dl_info()
        dladdr(base, &info)
        
        if #available(iOS 9999.0, macOS 11.0, *) {
            if info.dli_fname != nil && _dyld_shared_cache_contains_path(info.dli_fname) {
                print("in dyld cache")
            } else {
                return nil
            }
        } else {
            return nil
        }
        
        stopAllThreads()
        
        defer { resumeAllThreads() }
        
        self.base = base
        self.target = target
        guard let location = self.findLocation() else {
            return nil;
        }
        self.trampoline = location
        
        self.orig = findOrig()
        
        guard let code = self.buildTrampoline() else {
            return nil
        }
        self.trampolineCode = code
        self.writeTrampoline()
        self.buildHook()
    }
    
    public func findOrig() -> UnsafeMutableRawPointer? {
        
        let size = findFunctionSize(self.base)
        
        let (orig, _) = getOriginal(
            self.base,
            size,
            desiredRebindSize: 1*4,
            shouldBranchAfter: size != 4
        )
        
        return orig
    }
    
    public func buildTrampoline() -> [UInt8]? {
        let safeReg = findSafeRegister(self.base, isns: 8)
        let (orig, _) = getOriginal(
            self.trampoline,
            9,
            desiredRebindSize: 8 * 4,
            shouldBranchAfter: true,
            jmpReg: Register.x(safeReg)
        )
        
        guard let orig else {
            print("[-] trampoline: couldn't get orig for victim function")
            return nil
        }
        
        print(self.trampoline)
        hooks[self.trampoline] = orig
        
        let origJump: [UInt8] = [0x50, 0x00, 0x00, 0x58] +
        br(.x16).bytes() +
        split(from: UInt64(UInt(bitPattern: orig)))
        
        let targetJump = [0x50, 0x00, 0x00, 0x58] +
        br(.x16).bytes() +
        split(from: UInt64(UInt(bitPattern: target)))
        
        return origJump + targetJump
    }
    
    public func writeTrampoline() {
        patchFunction(self.trampoline, {
            return self.trampolineCode
        })
    }
    
    public func buildHook() {
        hooks.removeValue(forKey: self.base)
        let _: UnsafeMutableRawPointer? = hook(self.base, self.trampoline.advanced(by: 16), true)
    }
}

extension Trampoline {
    public func findLocation() -> UnsafeMutableRawPointer? {
        for isnIdx in 0..<(128_000_000/4) {
            let isnptr = self.base.advanced(by: 256).advanced(by: isnIdx * 4).assumingMemoryBound(to: UInt32.self)
            let isn = isnptr.pointee
                                    
            if isn == 0xD503237F {
                print("[+] trampoline: found pacibsp", isnptr)

                let size = findFunctionSize(UnsafeMutableRawPointer(mutating: isnptr.advanced(by: 4)), max: 15) ?? 16

                if size > 8 {
                    print("[+] trampoline: found trampoline victim", isnptr)
                    return UnsafeMutableRawPointer(isnptr)
                }
            }
        }
        return nil
    }
}