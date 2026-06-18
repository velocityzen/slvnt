import ArgumentParser
import FP
import Slvnt

struct Disconnect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "End the session and clear the saved code."
    )

    @OptionGroup var connection: ConnectionOptions

    @Flag(name: .long, help: "Only clear the local session; don't notify the device.")
    var localOnly = false

    func run() async throws {
        let store = connection.store
        guard let session = try store.load().get() else {
            print("No saved session.")
            return
        }
        if !localOnly {
            // Best-effort: the device may already be gone; clearing locally still matters.
            _ = await CatalogClient().disconnect(session: session)
        }
        try store.clear().get()
        print("Disconnected and cleared the saved session.")
    }
}
