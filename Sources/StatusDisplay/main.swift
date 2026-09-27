import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "version":
    print("status-display 1.0")
    exit(0)
default:
    StatusDisplayApp.main()
}
