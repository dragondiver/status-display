import Foundation

/// Reine Entscheidungsfunktion für status-display#27: darf diese Instanz `endpoint.json`
/// entfernen? Nur wenn der Inhalt nachweislich von ihr selbst stammt (gleiche PID). Eine Datei
/// ohne PID (von einer Version vor #27 geschrieben) oder mit einer fremden PID gehört nicht
/// beweisbar dieser Instanz und bleibt unangetastet – sonst kann eine zweite, z. B. wegen
/// belegtem Port gescheiterte Instanz die Datei der erfolgreich laufenden löschen.
public enum EndpointOwnership {
    public static func mayRemove(endpoint: Endpoint?, ownPid: Int32) -> Bool {
        guard let pid = endpoint?.pid else { return false }
        return pid == ownPid
    }
}

/// Reine Entscheidungsfunktion für status-display#27: soll sich diese Instanz beenden, weil unter
/// derselben Bundle-ID schon eine andere läuft? `runningPids` sind alle PIDs, die
/// `NSRunningApplication.runningApplications(withBundleIdentifier:)` für die eigene Bundle-ID
/// meldet (das kann die eigene PID mit einschließen, je nach Aufrufzeitpunkt) – `ownPid` wird
/// herausgefiltert. Eine aus dem Build-Ordner gestartete Kopie hat dieselbe Bundle-ID und zählt
/// absichtlich als „schon eine Instanz“.
public enum SingleInstance {
    public static func shouldQuit(runningPids: [Int32], ownPid: Int32) -> Bool {
        runningPids.contains { $0 != ownPid }
    }
}
