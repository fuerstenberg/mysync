import Foundation
import CoreWLAN
import Network

public protocol NetworkInfoProviding: Sendable {
    func snapshot() -> NetworkSnapshot
}

/// Liest WLAN-Name und IPv4-Schnittstellen des Systems.
public struct SystemNetworkInfoProvider: NetworkInfoProviding {
    public init() {}

    public func snapshot() -> NetworkSnapshot {
        NetworkSnapshot(ssid: Self.currentSSID(), interfaces: Self.ipv4Interfaces())
    }

    /// Ohne Ortungsfreigabe liefert macOS hier `nil`.
    public static func currentSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    public static func ipv4Interfaces() -> [IPv4Interface] {
        var result: [IPv4Interface] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = ptr.pointee
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  let mask = entry.ifa_netmask else { continue }

            let address = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            result.append(IPv4Interface(name: String(cString: entry.ifa_name), address: address, netmask: netmask))
        }
        return result
    }
}

public protocol ReachabilityChecking: Sendable {
    func isReachable(host: String, port: Int, timeout: TimeInterval) async -> Bool
}

/// Prüft per TCP-Verbindungsaufbau, ob der SSH-Port erreichbar ist.
public struct TCPReachability: ReachabilityChecking {
    public init() {}

    public func isReachable(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)), !host.isEmpty else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let once = ResumeOnce()

        return await withCheckedContinuation { continuation in
            @Sendable func finish(_ value: Bool) {
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled: finish(false)
                case .waiting: finish(false)
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
