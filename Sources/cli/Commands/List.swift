import ArgumentParser
import FP
import Slvnt

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List releases on the player."
    )

    @OptionGroup var connection: ConnectionOptions

    @Argument(help: "Optional search filter.")
    var query: String?

    func run() async throws {
        let releases = try await connection.resolveSession()
            .flatMapAsync { await CatalogClient().releases(session: $0, search: query) }
            .get()
        guard !releases.isEmpty else {
            print("No releases\(query.map { " matching \"\($0)\"" } ?? "").")
            return
        }
        for release in releases {
            print(release)
        }
        print("\n\(releases.count) release\(releases.count == 1 ? "" : "s").")
    }
}
