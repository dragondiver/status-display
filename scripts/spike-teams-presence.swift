#!/usr/bin/env swift
// SPIKE — Wegwerfcode. Nicht mergen.
//
// Prüft ob der MB-Tenant Device-Code-Flow + Presence.ReadWrite erlaubt.
// Ergebnis: "✓ Präsenz gesetzt" → Ansatz B' funktioniert.
//           Fehlermeldung mit "conditional_access" o.ä. → Keychain-Route nehmen.
//
// Aufruf: swift scripts/spike-teams-presence.swift

import Foundation

// Azure CLI — Microsoft-eigener Client, in jedem Azure-AD-Tenant vorregistriert.
let clientID = "04b07795-8ddb-461a-bbee-02f9e1bf7b46"
let scope    = "Presence.ReadWrite offline_access"
let tenant   = "common"

// MARK: - Device Code Flow

func requestDeviceCode() throws -> (deviceCode: String, userCode: String, verificationUri: String, interval: Int) {
    let body = "client_id=\(clientID)&scope=\(scope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)"
    let data = try post("https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/devicecode", body: body)
    let json = try parseJSON(data)
    if let err = json["error"] as? String {
        throw fail("\(err): \(json["error_description"] ?? "")")
    }
    return (
        deviceCode:      json["device_code"]      as! String,
        userCode:        json["user_code"]         as! String,
        verificationUri: json["verification_uri"]  as! String,
        interval:       (json["interval"] as? Int) ?? 5
    )
}

func pollForToken(deviceCode: String, interval: Int) throws -> String {
    let body = "grant_type=urn:ietf:params:oauth:grant-type:device_code&client_id=\(clientID)&device_code=\(deviceCode)"
    while true {
        Thread.sleep(forTimeInterval: Double(interval))
        let data = try post("https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/token", body: body)
        let json = try parseJSON(data)
        if let token = json["access_token"] as? String { return token }
        let err = json["error"] as? String ?? ""
        if err == "authorization_pending" { continue }
        throw fail("\(err): \(json["error_description"] ?? "")")
    }
}

// MARK: - Graph API

func setPresence(token: String) throws {
    var req = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me/presence/setUserPreferredPresence")!)
    req.httpMethod = "POST"
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
    req.httpBody = try! JSONSerialization.data(withJSONObject: [
        "availability":      "Busy",
        "activity":          "InAMeeting",
        "expirationDuration": "PT1H"
    ])
    let (data, response) = try syncRequest(req)
    let status = (response as! HTTPURLResponse).statusCode
    if status == 200 || status == 204 {
        print("✓ Präsenz gesetzt → Teams sollte jetzt \"Busy / In a meeting\" zeigen.")
        print("  Bitte in Teams nachschauen und dann Ctrl+C.")
    } else {
        print("✗ Graph-Fehler \(status):")
        print(String(data: data, encoding: .utf8) ?? "(leer)")
    }
}

// MARK: - Helpers

func post(_ urlString: String, body: String) throws -> Data {
    var req = URLRequest(url: URL(string: urlString)!)
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.httpBody = body.data(using: .utf8)
    let (data, _) = try syncRequest(req)
    return data
}

func parseJSON(_ data: Data) throws -> [String: Any] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw fail("Ungültiges JSON: \(String(data: data, encoding: .utf8) ?? "?")")
    }
    return json
}

func syncRequest(_ req: URLRequest) throws -> (Data, URLResponse) {
    var result: Result<(Data, URLResponse), Error>?
    let sema = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { data, response, error in
        result = error.map { .failure($0) } ?? .success((data!, response!))
        sema.signal()
    }.resume()
    sema.wait()
    return try result!.get()
}

func fail(_ msg: Any) -> NSError {
    NSError(domain: "spike", code: 0, userInfo: [NSLocalizedDescriptionKey: "\(msg)"])
}

// MARK: - Main

do {
    print("Schritt 1: Device Code anfordern …")
    let dc = try requestDeviceCode()
    print("")
    print("→ Browser öffnen:  \(dc.verificationUri)")
    print("→ Code eingeben:   \(dc.userCode)")
    print("")
    print("Warte auf Login … (Ctrl+C zum Abbrechen)")
    print("")
    let token = try pollForToken(deviceCode: dc.deviceCode, interval: dc.interval)
    print("✓ Token erhalten")
    print("")
    try setPresence(token: token)
} catch {
    print("✗ \(error.localizedDescription)")
}
