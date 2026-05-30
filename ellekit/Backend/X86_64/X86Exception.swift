// x86_64 exception handler for redirecting breakpoint exceptions to hooks
import Foundation
import Darwin

#if SWIFT_PACKAGE
import ellekitc
#endif

#if arch(x86_64)

let X86_THREAD_STATE64_COUNT = MemoryLayout<x86_thread_state64_t>.size / MemoryLayout<UInt32>.size

public final class X86ExceptionHandler {
    let port: mach_port_t
    var thread: DispatchQueue? = nil

    public init() {
        var targetPort = mach_port_t()

        if mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &targetPort) != KERN_SUCCESS {
            print("[-] ellekit: process can't allocate port")
        }

        if mach_port_insert_right(mach_task_self_, targetPort, targetPort, mach_msg_type_name_t(MACH_MSG_TYPE_MAKE_SEND)) != KERN_SUCCESS {
            print("[-] ellekit: process can't insert right")
        }

        if task_set_exception_ports(
            mach_task_self_,
            exception_mask_t(EXC_MASK_BREAKPOINT),
            targetPort,
            EXCEPTION_DEFAULT,
            x86_THREAD_STATE64
        ) != KERN_SUCCESS {
            print("[-] ellekit: can't set exception ports for x86_64")
        }

        self.port = targetPort
        startPortLoop()
    }

    public func startPortLoop() {
        print("[+] ellekit: starting x86_64 exception handler")
        self.thread = DispatchQueue(label: "ellekit_x86_exc_port", attributes: .concurrent)
        self.thread?.async { [weak self] in
            Self.portLoop(self)
        }
    }

    static func portLoop(_ `self`: X86ExceptionHandler?) {
        guard let `self` else {
            print("ellekit: x86 exception handler deallocated.")
            return
        }

        let msg_header = UnsafeMutablePointer<mach_msg_header_t>.allocate(capacity: Int(vm_page_size))
        defer { msg_header.deallocate() }

        let krt1 = mach_msg(
            msg_header,
            MACH_RCV_MSG | MACH_RCV_LARGE | Int32(MACH_MSG_TIMEOUT_NONE),
            0,
            mach_msg_size_t(vm_page_size),
            self.port,
            0,
            0
        )

        guard krt1 == KERN_SUCCESS else {
            return
        }

        let req = UnsafeMutableRawPointer(msg_header)
            .makeReadable()
            .withMemoryRebound(to: exception_raise_request.self, capacity: Int(vm_page_size)) { $0.pointee }

        let thread_port = req.thread.name

        if thread_port == mach_thread_self() {
            fatalError("Exception handler stack overflow blocked")
        }

        defer {
            var reply = exception_raise_reply()
            reply.Head.msgh_bits = req.Head.msgh_bits & UInt32(MACH_MSGH_BITS_REMOTE_MASK)
            reply.Head.msgh_size = mach_msg_size_t(MemoryLayout.size(ofValue: reply))
            reply.Head.msgh_remote_port = req.Head.msgh_remote_port
            reply.Head.msgh_local_port = mach_port_t(MACH_PORT_NULL)
            reply.Head.msgh_id = req.Head.msgh_id + 0x64

            reply.NDR = req.NDR
            reply.RetCode = KERN_SUCCESS

            mach_msg (
                &reply.Head,
                1,
                reply.Head.msgh_size,
                0,
                mach_port_name_t(MACH_PORT_NULL),
                MACH_MSG_TIMEOUT_NONE,
                mach_port_name_t(MACH_PORT_NULL)
            )

            Self.portLoop(self)
        }

        var state = x86_thread_state64_t()
        var stateCnt = mach_msg_type_number_t(X86_THREAD_STATE64_COUNT)

        let krt2 = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: UInt32.self, capacity: MemoryLayout<x86_thread_state64_t>.size) {
                thread_get_state(thread_port, x86_THREAD_STATE64, $0, &stateCnt)
            }
        }

        guard krt2 == KERN_SUCCESS else {
            print("[-] couldn't get state for thread (x86)")
            return
        }

        guard let formerPtr = UnsafeMutableRawPointer(bitPattern: UInt(state.__rip)) else {
            print("[-] couldn't get ptr from rip reg")
            return
        }

        if let newPtr = hooks[formerPtr] {
            state.__rip = UInt64(UInt(bitPattern: newPtr))

            let krt_set = withUnsafeMutablePointer(to: &state, {
                $0.withMemoryRebound(to: UInt32.self, capacity: MemoryLayout<x86_thread_state64_t>.size, {
                    thread_set_state(thread_port, x86_THREAD_STATE64, $0, mach_msg_type_number_t(X86_THREAD_STATE64_COUNT))
                })
            })

            guard krt_set == KERN_SUCCESS else {
                print("[-] couldn't set state for thread (x86)")
                return
            }

            thread_resume(thread_port)
        } else {
            exit(1)
        }
    }
}

#endif
