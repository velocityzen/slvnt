import ArgumentParser
import FP
import Slvnt

struct Pair: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Pair with a player and save the session for later commands."
    )

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .long, help: "Seconds to wait for discovery.")
    var timeout: Int = 30

    func run() async throws {
        let discovery = DiscoveryService()
        let device = try await resolveDevice(using: discovery)

        print("Requesting a transfer code — check the player's screen…")
        try await discovery.requestTransferCode(host: device.ip).get()

        let entered =
            connection.code ?? Console.prompt("Enter the 4-digit code shown on the device: ")
        let code = try TransferCode.validate(entered).get()

        let session = Session(device: device, code: code)
        // The player has no login endpoint; a successful catalog call validates the code.
        _ = try await CatalogClient().releases(session: session).get()
        try connection.store.save(session).get()

        print("Paired with \(device.name). Session saved to \(connection.store.path)")
        print("Note: the transfer code is stored there in plaintext — treat it as a secret.")
    }

    private func resolveDevice(using discovery: DiscoveryService) async throws -> Device {
        if connection.host != nil {
            return try connection.resolveDevice().get()
        }
        print("Searching for a Sleevenote player (make sure you're on the same Wi-Fi)…")
        let device = try await discovery.discover(timeout: .seconds(min(timeout, 120))).get()
        print("Found \(device.name) at \(device.ip).")
        return device
    }
}
