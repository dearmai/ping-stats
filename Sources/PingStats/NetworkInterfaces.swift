import Foundation
import SystemConfiguration

struct LocalAddress: Identifiable, Equatable {
    let interface: String
    let displayName: String
    let address: String
    let isIPv6: Bool

    var id: String { "\(interface)|\(address)" }

    var label: String {
        displayName.isEmpty ? interface : displayName
    }

    /// No System Configuration name means a virtual/pseudo interface (feth, bridge,
    /// awdl…) rather than a NIC the user configured — worth showing, but last.
    var isNamed: Bool {
        !displayName.isEmpty && displayName != interface
    }
}

/// Enumerates every routable address on every up, non-loopback interface, so a
/// machine on Wi-Fi + Ethernet + VPN reports all of them.
@MainActor
enum LocalAddressProvider {
    private static var displayNames: [String: String] = [:]

    static func current() -> [LocalAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var results: [LocalAddress] = []
        var seen = Set<String>()

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(pointer.pointee.ifa_flags)
            guard flags & IFF_UP == IFF_UP, flags & IFF_LOOPBACK == 0 else { continue }
            guard let addr = pointer.pointee.ifa_addr else { continue }

            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard status == 0 else { continue }

            var text = String(cString: host)
            // getnameinfo appends the scope id to scoped IPv6 (fe80::1%en0).
            if let scope = text.firstIndex(of: "%") {
                text = String(text[..<scope])
            }

            let isIPv6 = family == UInt8(AF_INET6)
            guard isRoutable(text, isIPv6: isIPv6) else { continue }

            let interface = String(cString: pointer.pointee.ifa_name)
            guard seen.insert("\(interface)|\(text)").inserted else { continue }

            results.append(LocalAddress(
                interface: interface,
                displayName: displayName(for: interface),
                address: text,
                isIPv6: isIPv6
            ))
        }

        // Named NICs before pseudo-interfaces, IPv4 before IPv6; kernel order breaks ties.
        return results.enumerated()
            .sorted { lhs, rhs in
                let lhsKey = (lhs.element.isNamed ? 0 : 1, lhs.element.isIPv6 ? 1 : 0, lhs.offset)
                let rhsKey = (rhs.element.isNamed ? 0 : 1, rhs.element.isIPv6 ? 1 : 0, rhs.offset)
                return lhsKey < rhsKey
            }
            .map(\.element)
    }

    private static func isRoutable(_ address: String, isIPv6: Bool) -> Bool {
        if isIPv6 {
            let lowercased = address.lowercased()
            return !lowercased.hasPrefix("fe80") && lowercased != "::1"
        }
        return !address.hasPrefix("169.254.") && address != "0.0.0.0"
    }

    /// Maps a BSD name (`en0`) to the name the user sees in Network settings ("Wi-Fi").
    /// Misses are cached as the BSD name so pseudo-interfaces (utun, awdl) do not
    /// re-scan every refresh; a newly attached adapter is an unseen name and rescans.
    private static func displayName(for bsdName: String) -> String {
        if let cached = displayNames[bsdName] { return cached }
        reloadDisplayNames()
        let resolved = displayNames[bsdName] ?? bsdName
        displayNames[bsdName] = resolved
        return resolved
    }

    private static func reloadDisplayNames() {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return }
        for interface in interfaces {
            guard
                let bsdName = SCNetworkInterfaceGetBSDName(interface) as String?,
                let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            else {
                continue
            }
            displayNames[bsdName] = name
        }
    }
}
