#!/usr/bin/env swift
// Erzeugt Resources/AppIcon.icns aus dem in Issue #32 festgelegten Motiv
// (Entwurf B: Statuspunkt mit Wartepunkt) mit CoreGraphics.
//
// Aufruf: swift scripts/make-icon.swift
//
// Zeichnet alle Größen eines macOS-.iconset (16/32/128/256/512, je @1x/@2x)
// in ein temporäres .iconset-Verzeichnis und ruft `iconutil -c icns` auf,
// um Resources/AppIcon.icns zu erzeugen. Nur Apple-Frameworks (CoreGraphics,
// ImageIO, Foundation) — kein Paketmanager nötig.
//
// Motiv (180er Referenz-Raster aus dem Issue):
//   <svg viewBox="0 0 180 180">
//     <rect width="180" height="180" rx="40" fill="#f4f4f7"/>
//     <circle cx="90" cy="92" r="52" fill="none" stroke="#dcdce3" stroke-width="10"/>
//     <path d="M90 40 A52 52 0 1 1 42 110" fill="none" stroke="#b3263e" stroke-width="10" stroke-linecap="round"/>
//     <circle cx="90" cy="92" r="28" fill="#b3263e"/>
//     <circle cx="134" cy="48" r="16" fill="#f0b43c" stroke="#f4f4f7" stroke-width="6"/>
//   </svg>
//
// macOS-Icon-Raster: Anders als bei der 180er-Vorlage (randloses Quadrat)
// sitzt der Inhalt bei macOS-App-Icons mit Rand auf der vollen Fläche
// (Apple-Konvention: Inhalt ca. 824x824 von 1024, zentriert, Eckradius
// ca. 185 bei 1024 statt rx=40 bei 180). Wir zeichnen daher auf einem
// 1024er Referenzraster, skalieren das 180er-Motiv auf 824x824 und
// zentrieren es mit ca. 100pt Rand auf jeder Seite. Die Fläche außerhalb
// des abgerundeten Quadrats bleibt transparent (nicht bis zum Rand
// deckend gefüllt) — sonst wirkt das Icon im Dock größer als seine
// Nachbarn.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Farben (aus dem Issue)

let colorBackground = CGColor(red: 0xf4 / 255, green: 0xf4 / 255, blue: 0xf7 / 255, alpha: 1)
let colorRing = CGColor(red: 0xdc / 255, green: 0xdc / 255, blue: 0xe3 / 255, alpha: 1)
let colorRed = CGColor(red: 0xb3 / 255, green: 0x26 / 255, blue: 0x3e / 255, alpha: 1)
let colorAmber = CGColor(red: 0xf0 / 255, green: 0xb4 / 255, blue: 0x3c / 255, alpha: 1)

// MARK: - Geometrie

// Referenzraster fuer das volle macOS-Icon (Apple-Konvention).
let fullCanvas: CGFloat = 1024
// Inhalt liegt zentriert mit Rand (~824x824 von 1024, wie bei Apple-Icons).
let contentSize: CGFloat = 824
let contentInset = (fullCanvas - contentSize) / 2
// Eckradius des abgerundeten Quadrats bei voller 1024er Flaeche.
let fullCornerRadius: CGFloat = 185

// Vorlage ist im 180er Raster definiert; Skalierungsfaktor auf den
// 824x824 grossen Inhaltsbereich.
let templateSize: CGFloat = 180
let scale = contentSize / templateSize

func drawIcon(in ctx: CGContext, pixels: CGFloat) {
    // pixels x pixels Canvas, Motiv wird ueber fullCanvas (1024) skaliert.
    let pixelScale = pixels / fullCanvas
    ctx.saveGState()
    ctx.scaleBy(x: pixelScale, y: pixelScale)

    // Hintergrund: abgerundetes Quadrat, zentriert mit Apple-typischem Rand.
    // Ausserhalb des Quadrats bleibt die Flaeche transparent (Dock setzt
    // sonst ein zu grosses Icon gegenueber den Nachbar-Icons).
    let bgRect = CGRect(x: contentInset, y: contentInset, width: contentSize, height: contentSize)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: fullCornerRadius, cornerHeight: fullCornerRadius, transform: nil)
    ctx.addPath(bgPath)
    ctx.setFillColor(colorBackground)
    ctx.fillPath()

    // Ab hier im 180er Vorlagen-Koordinatensystem zeichnen, auf den
    // zentrierten Inhaltsbereich skaliert. CoreGraphics hat den
    // Ursprung unten links, SVG oben links -> Y-Achse spiegeln.
    ctx.translateBy(x: contentInset, y: contentInset)
    ctx.translateBy(x: 0, y: contentSize)
    ctx.scaleBy(x: scale, y: -scale)

    // Grauer Ring.
    let ringCenter = CGPoint(x: 90, y: 92)
    let ringRadius: CGFloat = 52
    ctx.addArc(center: ringCenter, radius: ringRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.setStrokeColor(colorRing)
    ctx.setLineWidth(10)
    ctx.setLineCap(.round)
    ctx.strokePath()

    // Roter Bogen ueber ~3/4 des Rings: SVG-Pfad
    // "M90 40 A52 52 0 1 1 42 110" - Start bei (90,40) [12-Uhr-Position,
    // 90 Grad oberhalb Mittelpunkt], grosser Bogen (large-arc-flag=1) im
    // Uhrzeigersinn (sweep-flag=1 in SVG-Koordinaten) bis (42,110).
    // In SVG-Winkeln (0 Grad = rechts, im Uhrzeigersinn positiv):
    // Startpunkt (90,40) relativ zu Mittelpunkt (90,92): (0,-52) -> -90 Grad (oben).
    // Endpunkt (42,110) relativ zu Mittelpunkt: (-48,18) -> ~180+20.6 = 200.6 Grad.
    // Sweep im Uhrzeigersinn von -90 Grad ueber 0/90/180 bis 200.6 Grad = 290.6 Grad Bogenlaenge (~3/4 Kreis).
    // In CoreGraphics-Koordinaten (Y bereits gespiegelt, mathematisch
    // positiver Winkel = Gegenuhrzeigersinn in Bildschirmdarstellung,
    // entspricht nach der Y-Spiegelung wieder dem SVG-Uhrzeigersinn).
    let startAngle = -CGFloat.pi / 2
    let sweep = 290.6 * CGFloat.pi / 180
    let endAngle = startAngle + sweep
    ctx.addArc(center: ringCenter, radius: ringRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
    ctx.setStrokeColor(colorRed)
    ctx.setLineWidth(10)
    ctx.setLineCap(.round)
    ctx.strokePath()

    // Rote gefuellte Mitte.
    ctx.addArc(center: ringCenter, radius: 28, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.setFillColor(colorRed)
    ctx.fillPath()

    // Oranger "wartet"-Punkt oben rechts, mit hellem Rand.
    let dotCenter = CGPoint(x: 134, y: 48)
    let dotRadius: CGFloat = 16
    ctx.addArc(center: dotCenter, radius: dotRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.setFillColor(colorAmber)
    ctx.fillPath()
    ctx.addArc(center: dotCenter, radius: dotRadius - 3, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.setStrokeColor(colorBackground)
    ctx.setLineWidth(6)
    ctx.strokePath()

    ctx.restoreGState()
}

func makePNG(pixels: Int, to url: URL) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("CGContext konnte nicht erzeugt werden (\(pixels)px)")
    }
    drawIcon(in: ctx, pixels: CGFloat(pixels))
    guard let image = ctx.makeImage() else {
        fatalError("CGImage konnte nicht erzeugt werden (\(pixels)px)")
    }
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("PNG-Destination konnte nicht erzeugt werden: \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        fatalError("PNG konnte nicht geschrieben werden: \(url.path)")
    }
}

// MARK: - Hauptprogramm

let fileManager = FileManager.default
let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repoRoot = scriptDir.deletingLastPathComponent()
let iconsetDir = repoRoot.appendingPathComponent("build/AppIcon.iconset")
let icnsPath = repoRoot.appendingPathComponent("Resources/AppIcon.icns")

try? fileManager.removeItem(at: iconsetDir)
try fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// (Dateiname im .iconset, Pixelgroesse)
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, pixels) in sizes {
    let url = iconsetDir.appendingPathComponent(name)
    makePNG(pixels: pixels, to: url)
    print("geschrieben: \(name) (\(pixels)x\(pixels))")
}

// iconutil erzeugt Resources/AppIcon.icns aus dem .iconset.
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsPath.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fatalError("iconutil fehlgeschlagen mit Status \(process.terminationStatus)")
}

print("Resources/AppIcon.icns erzeugt.")
