import ArgumentParser
import FP
import Slvnt

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show storage and battery."
    )

    @OptionGroup var connection: ConnectionOptions

    func run() async throws {
        let client = CatalogClient()

        let (device, storage, battery) = try await connection.resolveSession()
            .bindAsync { await client.storage(session: $0) }
            .bindAsync { session, _ in await client.battery(session: session) }
            .map { ($0.device, $1, $2) }
            .get()

        print("Device:  \(device)")
        print("Storage: \(storage)")
        print("Battery: \(battery)")
    }
}
