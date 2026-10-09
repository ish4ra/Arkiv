import Foundation
import Darwin

@main
struct VerifyFinderAuthentication {
    static func main() {
        var token = audit_token_t()
        var count = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &token) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { fatalError("Cannot obtain diagnostic task audit token") }
        let data = withUnsafeBytes(of: token) { Data($0) }
        let ownCode = URL(fileURLWithPath: CommandLine.arguments[0])
        let extensionCode = URL(fileURLWithPath: CommandLine.arguments[1])
        guard FinderEventAuthenticator.matchesCode(data, at: ownCode),
              !FinderEventAuthenticator.matchesCode(data, at: extensionCode),
              !FinderEventAuthenticator.matchesCode(Data(repeating: 0, count: 32), at: ownCode) else {
            fatalError("Exact-code audit-token authentication regression")
        }
        print("Verified genuine audit token, exact ad-hoc code identity, unrelated sender rejection, and invalid token rejection")
    }
}
