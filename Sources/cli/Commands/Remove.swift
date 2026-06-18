import ArgumentParser
import FP
import Slvnt

struct Remove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove a release from the player."
    )

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .long, help: "Release id to remove.")
    var id: String?

    @Option(name: .long, help: "Artist (use together with --release).")
    var artist: String?

    @Option(name: .customLong("release"), help: "Release title (use together with --artist).")
    var releaseTitle: String?

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var force = false

    func validate() throws {
        if id == nil, artist == nil || releaseTitle == nil {
            throw ValidationError("Provide --id, or both --artist and --release.")
        }
    }

    func run() async throws {
        let session = try connection.resolveSession().get()
        let selector: ReleaseSelector =
            if let id { .id(id) } else { .artistRelease(artist: artist!, release: releaseTitle!) }

        if !force {
            let what = id.map { "release \($0)" } ?? "\(artist!) — \(releaseTitle!)"
            let answer = Console.prompt("Remove \(what)? [y/N]: ").lowercased()
            guard answer == "y" || answer == "yes" else {
                print("Cancelled.")
                return
            }
        }

        try await CatalogClient().remove(session: session, selector: selector).get()
        print("Removed.")
    }
}
