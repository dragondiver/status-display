import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "version":
    print("status-display 1.0")
    exit(0)
case "display-test":
    exit(CLI.displayTest())
case "preview":
    exit(CLI.preview(arguments.dropFirst().first))
case "hook":
    exit(CLI.hook(arguments.dropFirst().first))
default:
    // Nur beim eigentlichen App-Start prüfen (status-display#27), nicht bei den Unterbefehlen
    // oben – die sollen parallel zu einer laufenden App funktionieren.
    CLI.enforceSingleInstance()
    StatusDisplayApp.main()
}
