import ArgumentParser

@main
struct Slvnt: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "slvnt",
        abstract: "Manage music on a Sleevenote hardware player.",
        version: "0.1.0",
        subcommands: [
            Discover.self,
            Pair.self,
            Info.self,
            List.self,
            Status.self,
            Remove.self,
            Upload.self,
            Disconnect.self,
        ]
    )
}
