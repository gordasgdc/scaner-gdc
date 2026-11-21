// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import Darwin

/// What URLs the app is willing to contact. https only, no credentials in the URL, no local/private destinations.
public enum URLPolicy {
    public enum Rejection: Error, Equatable, CustomStringConvertible {
        case notHTTPS, noHost, hasCredentials, badPort, tooLong, localHost, privateAddress, notAURL
        public var description: String {
            switch self {
            case .notHTTPS: "Only https:// addresses are accepted."
            case .noHost: "The address has no host."
            case .hasCredentials: "Addresses with a user name or password are not accepted."
            case .badPort: "Only the default https port is accepted."
            case .tooLong: "The address is too long."
            case .localHost: "Local or single-label hosts are not accepted."
            case .privateAddress: "Private, loopback or link-local addresses are not accepted."
            case .notAURL: "This is not a valid address."
            }
        }
    }

    public static let maxLength = 2048

    /// Syntactic + literal-address check (no network).
    public static func validate(_ url: URL) -> Result<URL, Rejection> {
        let s = url.absoluteString
        if s.count > maxLength { return .failure(.tooLong) }
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return .failure(.notAURL) }
        guard c.scheme?.lowercased() == "https" else { return .failure(.notHTTPS) }
        if c.user != nil || c.password != nil { return .failure(.hasCredentials) }
        if let p = c.port, p != 443 { return .failure(.badPort) }
        guard let host = c.host?.lowercased(), !host.isEmpty else { return .failure(.noHost) }
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if let blocked = literalAddressBlocked(bare) { return blocked ? .failure(.privateAddress) : .success(url) }
        if !bare.contains(".") || bare == "localhost" || bare.hasSuffix(".localhost") || bare.hasSuffix(".local")
            || bare.hasSuffix(".internal") || bare.hasSuffix(".lan") || bare.hasSuffix(".home") || bare.hasSuffix(".corp") { return .failure(.localHost) }
        return .success(url)
    }

    public static func parse(_ text: String) -> Result<URL, Rejection> {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let u = URL(string: t) else { return .failure(.notAURL) }
        return validate(u)
    }

    /// nil = not an IP literal; true = blocked literal; false = public literal.
    static func literalAddressBlocked(_ host: String) -> Bool? {
        var a4 = in_addr(); var a6 = in6_addr()
        if inet_pton(AF_INET, host, &a4) == 1 { return isBlocked(v4: UInt32(bigEndian: a4.s_addr)) }
        if inet_pton(AF_INET6, host, &a6) == 1 { return isBlocked(v6: a6) }
        return nil
    }

    static func isBlocked(v4 a: UInt32) -> Bool {
        let b0 = a >> 24, b1 = (a >> 16) & 0xFF
        if b0 == 0 || b0 == 10 || b0 == 127 || b0 >= 224 { return true }          // this-net, private, loopback, multicast/reserved
        if b0 == 169 && b1 == 254 { return true }                                  // link-local (incl. cloud metadata)
        if b0 == 172 && (16...31).contains(b1) { return true }
        if b0 == 192 && b1 == 168 { return true }
        if b0 == 100 && (64...127).contains(b1) { return true }                    // CGNAT
        if b0 == 192 && b1 == 0 && ((a >> 8) & 0xFF) == 0 { return true }
        return false
    }

    static func isBlocked(v6 a: in6_addr) -> Bool {
        let b = withUnsafeBytes(of: a) { Array($0) }
        if b.allSatisfy({ $0 == 0 }) { return true }                                // ::
        if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return true }          // ::1
        if b[0] == 0xFE && (b[1] & 0xC0) == 0x80 { return true }                    // fe80::/10
        if (b[0] & 0xFE) == 0xFC { return true }                                    // fc00::/7
        if b[0] == 0xFF { return true }                                             // multicast
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF {    // ::ffff:a.b.c.d
            return isBlocked(v4: UInt32(b[12]) << 24 | UInt32(b[13]) << 16 | UInt32(b[14]) << 8 | UInt32(b[15])) }
        return false
    }

    /// Resolves the host and rejects it when ANY resolved address is private (guards DNS names pointing inside the network).
    public static func resolvedAddressesAllowed(host: String) -> Bool {
        var hints = addrinfo(); hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return false }
        defer { freeaddrinfo(res) }
        var p: UnsafeMutablePointer<addrinfo>? = first
        while let ai = p {
            if ai.pointee.ai_family == AF_INET {
                let s = ai.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
                if isBlocked(v4: UInt32(bigEndian: s)) { return false }
            } else if ai.pointee.ai_family == AF_INET6 {
                let s = ai.pointee.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                if isBlocked(v6: s) { return false }
            }
            p = ai.pointee.ai_next
        }
        return true
    }
}
