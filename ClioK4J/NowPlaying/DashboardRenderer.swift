import UIKit
import CoreGraphics

/// Dessine un tableau de bord 1024×1024 à partir des données live.
/// L'image sert de "pochette" sur l'écran Lecture en cours de CarPlay.
enum DashboardRenderer {

    static func render(live: LiveData, trip: (km: Double, litres: Double, seconds: Int), fuelName: String) -> UIImage {
        let size = CGSize(width: 1024, height: 1024)
        let r = UIGraphicsImageRenderer(size: size)
        return r.image { ctx in
            let c = ctx.cgContext

            // Fond nuit
            c.setFillColor(UIColor(red: 0.043, green: 0.051, blue: 0.063, alpha: 1).cgColor)
            c.fill(CGRect(origin: .zero, size: size))

            // Hero conso instantanée au centre
            let vit = live.vit ?? 0
            let l100 = vit > 5 ? live.lh / vit * 100 : nil
            let heroValue: String
            let heroUnit: String
            if let l = l100 {
                heroValue = String(format: "%.1f", min(l, 99.9))
                heroUnit = "L/100 KM"
            } else {
                heroValue = String(format: "%.2f", live.lh)
                heroUnit = "L/H À L'ARRÊT"
            }

            drawCentered(heroValue, at: CGPoint(x: 512, y: 320),
                         size: 280, weight: .bold,
                         color: UIColor(red: 1, green: 0.42, blue: 0.17, alpha: 1), monospace: true)
            drawCentered(heroUnit, at: CGPoint(x: 512, y: 500),
                         size: 42, weight: .semibold,
                         color: UIColor(red: 0.769, green: 0.475, blue: 0.306, alpha: 1))

            // Jauge de régime en arc
            drawRpmArc(c, rpm: live.rpm ?? 0, center: CGPoint(x: 512, y: 300), radius: 420)

            // 4 cases : conso moy, vitesse, eau, batterie
            let moy: String = {
                guard trip.km > 0.3 else { return "--.-" }
                return String(format: "%.1f", trip.litres / trip.km * 100)
            }()
            let tiles: [(String, String, UIColor)] = [
                ("MOYENNE TRAJET", "\(moy) L/100", .white),
                ("VITESSE",        "\(Int(vit)) km/h", .white),
                ("EAU",            fmt(live.eau, 0, "--") + " °C",
                 (live.eau ?? 0) > 105 ? red : (live.eau ?? 0) > 98 ? warn : .white),
                ("BATTERIE",       fmt(live.bat, 1, "--") + " V",
                 (live.bat != nil && (live.bat! < 12.2 || live.bat! > 14.8)) ? warn : .white),
            ]
            let tileW: CGFloat = 460; let tileH: CGFloat = 170
            let positions: [CGPoint] = [
                CGPoint(x: 42, y: 620),
                CGPoint(x: 522, y: 620),
                CGPoint(x: 42, y: 810),
                CGPoint(x: 522, y: 810),
            ]
            for (i, (label, value, color)) in tiles.enumerated() {
                drawTile(c, rect: CGRect(origin: positions[i], size: CGSize(width: tileW, height: tileH)),
                         label: label, value: value, color: color)
            }

            // En-tête : marque + carburant
            drawText("CLIO 2 · K4J  ·  \(fuelName.uppercased())",
                     at: CGPoint(x: 512, y: 60), align: .center,
                     size: 44, weight: .semibold,
                     color: UIColor(red: 0.913, green: 0.902, blue: 0.882, alpha: 1), tracking: 2.0)

            // Durée + distance en pied
            let d = trip.seconds
            let dur = "\(d / 60):\(String(format: "%02d", d % 60))"
            drawText(String(format: "TRAJET  %@  ·  %.1f KM  ·  %.2f L",
                            dur, trip.km, trip.litres),
                     at: CGPoint(x: 512, y: 990), align: .center,
                     size: 30, weight: .medium,
                     color: UIColor(red: 0.541, green: 0.561, blue: 0.592, alpha: 1), tracking: 1.5)
        }
    }

    // MARK: - Dessin

    private static let orange = UIColor(red: 1, green: 0.42, blue: 0.17, alpha: 1)
    private static let warn = UIColor(red: 0.949, green: 0.702, blue: 0.239, alpha: 1)
    private static let red  = UIColor(red: 0.937, green: 0.325, blue: 0.314, alpha: 1)
    private static let panel = UIColor(red: 0.078, green: 0.090, blue: 0.110, alpha: 1)
    private static let line  = UIColor(red: 0.145, green: 0.165, blue: 0.192, alpha: 1)

    private static func drawRpmArc(_ c: CGContext, rpm: Double, center: CGPoint, radius: CGFloat) {
        let start = CGFloat.pi * 0.75
        let end   = CGFloat.pi * 0.25 + 2 * .pi
        let pr = min(1, CGFloat(rpm / 6500))
        // Fond
        c.setStrokeColor(line.cgColor)
        c.setLineWidth(28)
        c.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        c.strokePath()
        // Rempli
        let cur = start + (end - start) * pr
        c.setStrokeColor((rpm > K4J.redline ? red : orange).cgColor)
        c.setLineCap(.round)
        c.addArc(center: center, radius: radius, startAngle: start, endAngle: cur, clockwise: false)
        c.strokePath()
        c.setLineCap(.butt)
        // Graduations
        for g in stride(from: 0, through: 7000, by: 1000) {
            let frac = CGFloat(g) / 6500
            let ang = start + (end - start) * frac
            let x0 = center.x + cos(ang) * (radius - 44)
            let y0 = center.y + sin(ang) * (radius - 44)
            let x1 = center.x + cos(ang) * (radius - 14)
            let y1 = center.y + sin(ang) * (radius - 14)
            c.setStrokeColor((g >= 6000 ? red : UIColor(white: 0.6, alpha: 1)).cgColor)
            c.setLineWidth(3)
            c.beginPath()
            c.move(to: CGPoint(x: x0, y: y0))
            c.addLine(to: CGPoint(x: x1, y: y1))
            c.strokePath()
        }
        // Valeur régime
        drawText("\(Int(rpm)) tr/min",
                 at: CGPoint(x: center.x, y: center.y + radius + 20),
                 align: .center, size: 30, weight: .semibold, color: .lightGray, tracking: 1.0)
    }

    private static func drawTile(_ c: CGContext, rect: CGRect, label: String, value: String, color: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 18)
        c.setFillColor(panel.cgColor)
        c.addPath(path.cgPath); c.fillPath()
        c.setStrokeColor(line.cgColor); c.setLineWidth(2)
        c.addPath(path.cgPath); c.strokePath()
        drawText(label, at: CGPoint(x: rect.minX + 24, y: rect.minY + 26),
                 align: .left, size: 26, weight: .semibold,
                 color: UIColor(white: 0.55, alpha: 1), tracking: 2.0)
        drawText(value, at: CGPoint(x: rect.minX + 24, y: rect.minY + 70),
                 align: .left, size: 64, weight: .bold, color: color, tracking: 0, monospace: true)
    }

    private static func drawText(_ s: String, at p: CGPoint, align: NSTextAlignment,
                                 size: CGFloat, weight: UIFont.Weight, color: UIColor,
                                 tracking: Double = 0, monospace: Bool = false) {
        let font: UIFont = monospace
            ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : UIFont.systemFont(ofSize: size, weight: weight)
        let para = NSMutableParagraphStyle(); para.alignment = align
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: para,
            .kern: tracking,
        ]
        let ns = NSAttributedString(string: s, attributes: attrs)
        let bounds = ns.boundingRect(with: CGSize(width: 1024, height: 300),
                                     options: .usesLineFragmentOrigin, context: nil)
        let origin: CGPoint
        switch align {
        case .center: origin = CGPoint(x: p.x - bounds.width / 2, y: p.y)
        case .right:  origin = CGPoint(x: p.x - bounds.width, y: p.y)
        default:      origin = p
        }
        ns.draw(at: origin)
    }

    private static func drawCentered(_ s: String, at p: CGPoint,
                                     size: CGFloat, weight: UIFont.Weight, color: UIColor, monospace: Bool = false) {
        drawText(s, at: p, align: .center, size: size, weight: weight, color: color, tracking: 0, monospace: monospace)
    }

    private static func fmt(_ v: Double?, _ d: Int, _ def: String) -> String {
        guard let v = v else { return def }
        return String(format: "%.\(d)f", v)
    }
}
