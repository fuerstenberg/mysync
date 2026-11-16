import XCTest
@testable import MySyncCore

final class NetworkMatcherTests: XCTestCase {
    func iface(_ ip: String, _ mask: String = "255.255.255.0") -> IPv4Interface {
        IPv4Interface(name: "en0", address: ip, netmask: mask)!
    }

    func testIPv4Parsing() {
        XCTAssertEqual(IPv4.parse("192.168.1.10"), 0xC0A8010A)
        XCTAssertNil(IPv4.parse("192.168.1"))
        XCTAssertNil(IPv4.parse("192.168.1.256"))
        XCTAssertNil(IPv4.parse("a.b.c.d"))
        XCTAssertEqual(IPv4.format(0xC0A8010A), "192.168.1.10")
    }

    func testCIDRParsing() {
        XCTAssertEqual(CIDR("192.168.1.77/24")?.network, IPv4.parse("192.168.1.0"))
        XCTAssertEqual(CIDR("10.0.0.5")?.prefixLength, 32)
        XCTAssertNil(CIDR("10.0.0.0/33"))
        XCTAssertNil(CIDR("kaputt/24"))
        XCTAssertNil(CIDR("10.0.0.0/24/1"))
    }

    func testCIDRContains() {
        let c24 = CIDR("192.168.1.0/24")!
        XCTAssertTrue(c24.contains(IPv4.parse("192.168.1.200")!))
        XCTAssertFalse(c24.contains(IPv4.parse("192.168.2.1")!))

        let c16 = CIDR("10.20.0.0/16")!
        XCTAssertTrue(c16.contains(IPv4.parse("10.20.99.1")!))
        XCTAssertFalse(c16.contains(IPv4.parse("10.21.0.1")!))

        let c32 = CIDR("10.0.0.5/32")!
        XCTAssertTrue(c32.contains(IPv4.parse("10.0.0.5")!))
        XCTAssertFalse(c32.contains(IPv4.parse("10.0.0.6")!))

        XCTAssertTrue(CIDR("0.0.0.0/0")!.contains(IPv4.parse("8.8.8.8")!))
    }

    func testInterfaceCIDR() {
        XCTAssertEqual(iface("192.168.178.34").cidr, "192.168.178.0/24")
        XCTAssertEqual(iface("10.1.2.3", "255.255.0.0").cidr, "10.1.0.0/16")
    }

    func testNoRulesMeansAlwaysExpected() {
        let result = NetworkMatcher.match(computer: makeComputer(), snapshot: NetworkSnapshot())
        XCTAssertEqual(result, .noRulesConfigured)
        XCTAssertTrue(result.expectsReachable)
    }

    func testSSIDMatch() {
        let computer = makeComputer(ssids: ["Zuhause", "Zuhause-5G"])
        XCTAssertEqual(NetworkMatcher.match(computer: computer, snapshot: NetworkSnapshot(ssid: "Zuhause-5G")), .inNetwork)
        XCTAssertEqual(NetworkMatcher.match(computer: computer, snapshot: NetworkSnapshot(ssid: "Café")), .notInNetwork)
        XCTAssertFalse(NetworkMatcher.Result.notInNetwork.expectsReachable)
    }

    func testSubnetFallbackWithoutSSID() {
        let computer = makeComputer(ssids: ["Zuhause"], subnets: ["192.168.1.0/24"])
        // Per LAN-Kabel: keine SSID, aber passendes Subnetz.
        let snap = NetworkSnapshot(ssid: nil, interfaces: [iface("192.168.1.42")])
        XCTAssertEqual(NetworkMatcher.match(computer: computer, snapshot: snap), .inNetwork)
    }

    func testForeignNetwork() {
        let computer = makeComputer(ssids: ["Zuhause"], subnets: ["192.168.1.0/24"])
        let snap = NetworkSnapshot(ssid: "Hotel", interfaces: [iface("172.16.5.9")])
        XCTAssertEqual(NetworkMatcher.match(computer: computer, snapshot: snap), .notInNetwork)
    }

    func testInvalidAndBlankRulesAreIgnored() {
        let computer = makeComputer(ssids: ["  "], subnets: ["quatsch"])
        XCTAssertEqual(NetworkMatcher.match(computer: computer, snapshot: NetworkSnapshot()), .noRulesConfigured)
    }

    func testSSIDWhitespaceTrimmed() {
        let computer = makeComputer(ssids: [" Zuhause "])
        XCTAssertEqual(NetworkMatcher.match(computer: computer, snapshot: NetworkSnapshot(ssid: "Zuhause")), .inNetwork)
    }

    func testSystemInterfacesDoNotCrash() {
        // Läuft gegen das echte System: Loopback darf nie enthalten sein.
        let interfaces = SystemNetworkInfoProvider.ipv4Interfaces()
        XCTAssertFalse(interfaces.contains { IPv4.format($0.address) == "127.0.0.1" })
    }
}
