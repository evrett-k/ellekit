// This file is licensed under the BSD-3 Clause License
// Copyright 2022 © ElleKit Team

import Foundation

public enum ElleKitArchitecture {
    case arm64
    case x86_64
}

public protocol ElleKitBackend {
    var architecture: ElleKitArchitecture { get }

    func hook(
        _ stockTarget: UnsafeMutableRawPointer,
        _ stockReplacement: UnsafeMutableRawPointer,
        _ internalSkipChecks: Bool
    ) -> UnsafeMutableRawPointer?
}

public let activeBackend: any ElleKitBackend = {
    #if arch(x86_64)
    return X86_64Backend()
    #else
    return ARM64Backend()
    #endif
}()