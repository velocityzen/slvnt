import ArgumentParser
import FP
import Slvnt

struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the player's device info."
    )

    @OptionGroup var connection: ConnectionOptions

    func run() async throws {
        let info = try await connection.resolveDevice()
            .flatMapAsync { await CatalogClient().info(device: $0) }
            .get()
        print(info)
    }
}
