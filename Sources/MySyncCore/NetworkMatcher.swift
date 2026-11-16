import Foundation

/// Momentaufnahme des Netzwerks, in dem sich der Mac gerade befindet.
public struct NetworkSnapshot: Equatable, Sendable {
    /// Aktueller WLAN-Name, falls bekannt (braucht unter macOS die Ortungsfreigabe).
    public var ssid: String?
    /// Eigene IPv4-Adressen samt Netzmaske.
    public var interfaces: [IPv4Interface]

    public init(ssid: String? = nil, interfaces: [IPv4Interface] = []) {
        self.ssid = ssid
        self.interfaces = interfaces
    }
}

public struct IPv4Interface: Equatable, Sendable {
    public var name: String
    public var address: UInt32
    public var netmask: UInt32

    public init(name: String, address: UInt32, netmask: UInt32) {
        self.name = name
        self.address = address
        self.netmask = netmask
    }

    public init?(name: String, address: String, netmask: String) {
        guard let a = IPv4.parse(address), let m = IPv4.parse(netmask) else { return nil }
        self.init(name: name, address: a, netmask: m)
    }

    /// Das Subnetz dieser Schnittstelle in CIDR-Schreibweise, z. B. „192.168.1.0/24“.
    public var cidr: String {
        let prefix = netmask.nonzeroBitCount
        return "\(IPv4.format(address & netmask))/\(prefix)"
    }
}

public enum IPv4 {
    public static func parse(_ s: String) -> UInt32? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else { return nil }
            value = (value << 8) | UInt32(octet)
        }
        return value
    }

    public static func format(_ v: UInt32) -> String {
        "\(v >> 24 & 0xFF).\(v >> 16 & 0xFF).\(v >> 8 & 0xFF).\(v & 0xFF)"
    }
}

/// Ein Subnetz wie „192.168.1.0/24“.
public struct CIDR: Equatable, Sendable {
    public var network: UInt32
    public var prefixLength: Int

    public init?(_ string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: "/")
        guard let first = parts.first, let address = IPv4.parse(String(first)) else { return nil }
        let prefix: Int
        if parts.count == 1 {
            prefix = 32
        } else if parts.count == 2, let p = Int(parts[1]), (0...32).contains(p) {
            prefix = p
        } else {
            return nil
        }
        self.prefixLength = prefix
        self.network = address & CIDR.mask(prefix)
    }

    public static func mask(_ prefix: Int) -> UInt32 {
        prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix)
    }

    public func contains(_ address: UInt32) -> Bool {
        address & CIDR.mask(prefixLength) == network
    }
}

/// Entscheidet, ob der Mac im Netzwerk eines Computers ist.
public enum NetworkMatcher {
    public enum Result: Equatable, Sendable {
        /// Kein WLAN-Name und kein Subnetz hinterlegt → wir nehmen an, dass er immer erreichbar sein sollte.
        case noRulesConfigured
        case inNetwork
        case notInNetwork

        /// Soll ein Ausfall als Fehler gelten?
        public var expectsReachable: Bool { self != .notInNetwork }
    }

    public static func match(computer: Computer, snapshot: NetworkSnapshot) -> Result {
        let ssids = computer.ssids
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let subnets = computer.subnets.compactMap(CIDR.init)

        if ssids.isEmpty && subnets.isEmpty {
            return .noRulesConfigured
        }
        if let current = snapshot.ssid, ssids.contains(current) {
            return .inNetwork
        }
        for iface in snapshot.interfaces where subnets.contains(where: { $0.contains(iface.address) }) {
            return .inNetwork
        }
        return .notInNetwork
    }
}
