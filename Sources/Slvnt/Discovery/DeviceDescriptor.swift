import Foundation

/// Decodes a discovery datagram (current or legacy schema) into a `Device`.
public enum DeviceDescriptor {
    public static func parse(_ data: Data) -> Result<Device, SlvntError> {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.invalidDescriptor("response was not a JSON object"))
        }
        return parse(object)
    }

    static func parse(_ object: [String: Any]) -> Result<Device, SlvntError> {
        if object["http_port"] != nil || object["device"] != nil || object["hostname"] != nil {
            return parseCurrent(object)
        }
        if object["ip"] != nil, object["port"] != nil {
            return parseLegacy(object)
        }
        return .failure(.invalidDescriptor("unrecognized descriptor shape"))
    }

    private static func parseCurrent(_ object: [String: Any]) -> Result<Device, SlvntError> {
        guard let ip = string(object["ip"]), !ip.isEmpty else {
            return .failure(.invalidDescriptor("missing ip"))
        }
        let httpPort = int(object["http_port"]) ?? 8080
        let name = string(object["hostname"]) ?? string(object["device"]) ?? "Sleevenote"
        return .success(
            Device(
                name: friendly(name),
                ip: ip,
                httpPort: httpPort,
                ftpPort: int(object["ftp_port"]) ?? 2121,
                useHTTPS: httpPort == 8443
            ))
    }

    private static func parseLegacy(_ object: [String: Any]) -> Result<Device, SlvntError> {
        guard let ip = string(object["ip"]), !ip.isEmpty, let port = int(object["port"]) else {
            return .failure(.invalidDescriptor("missing ip/port"))
        }
        return .success(
            Device(
                name: friendly(string(object["device"]) ?? "Sleevenote"),
                ip: ip,
                httpPort: port,
                ftpPort: int(object["ftp_port"]) ?? 2121,
                useHTTPS: bool(object["ssl"]) ?? (port == 8443)
            ))
    }

    // MARK: - Lenient value extraction (JSONSerialization yields NSNumber/NSString)

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return Bool(string) }
        return nil
    }

    /// The first dot-separated label of an mDNS-style name (`Sleevenote.local` → `Sleevenote`).
    private static func friendly(_ name: String) -> String {
        String(name.split(separator: ".").first ?? Substring(name))
    }
}
