import ArgumentParser
import FP
import Slvnt

struct Discover: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Find a Sleevenote player on the local network."
    )

    @Option(name: .long, help: "Seconds to wait for a reply.")
    var timeout: Int = 5

    func run() async throws {
        let device = try await DiscoveryService().discover(timeout: .seconds(timeout)).get()
        print("Found \(device)")
        print("\nRun `slvnt pair` to connect.")
    }
}
