import AppKit

// usage: make-icon <out.iconset dir>   (draws an original cat-face app icon at every size macOS needs)
func draw(_ s: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: s, height: s), flipped: false) { r in
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        let orange = NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.25, alpha: 1)
        let dark = NSColor(calibratedRed: 0.80, green: 0.42, blue: 0.12, alpha: 1)
        let pink = NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.72, alpha: 1)

        let bg = NSBezierPath(roundedRect: r.insetBy(dx: s * 0.05, dy: s * 0.05), xRadius: s * 0.22, yRadius: s * 0.22)
        NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.27, blue: 0.55, alpha: 1),
                            NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.22, alpha: 1)])!.draw(in: bg, angle: -90)

        for sign: CGFloat in [-1, 1] {   // ears
            let ear = NSBezierPath()
            ear.move(to: p(0.5 + sign * 0.30, 0.46)); ear.line(to: p(0.5 + sign * 0.31, 0.80)); ear.line(to: p(0.5 + sign * 0.13, 0.64)); ear.close()
            orange.setFill(); ear.fill()
            let inner = NSBezierPath()
            inner.move(to: p(0.5 + sign * 0.27, 0.54)); inner.line(to: p(0.5 + sign * 0.28, 0.72)); inner.line(to: p(0.5 + sign * 0.17, 0.63)); inner.close()
            pink.setFill(); inner.fill()
        }
        let face = NSBezierPath(ovalIn: CGRect(x: s * 0.17, y: s * 0.17, width: s * 0.66, height: s * 0.54))   // wide, fat face
        orange.setFill(); face.fill()
        dark.setStroke()
        for i in 0..<3 {   // forehead stripes
            let st = NSBezierPath(); st.lineWidth = s * 0.022; st.lineCapStyle = .round
            let x = 0.5 + CGFloat(i - 1) * 0.07
            st.move(to: p(x, 0.71)); st.line(to: p(x, 0.62)); st.stroke()
        }
        for sign: CGFloat in [-1, 1] {   // sleepy eyes
            let eye = NSBezierPath(); eye.lineWidth = s * 0.03; eye.lineCapStyle = .round
            eye.move(to: p(0.5 + sign * 0.07, 0.50)); eye.curve(to: p(0.5 + sign * 0.22, 0.50),
                                                              controlPoint1: p(0.5 + sign * 0.11, 0.455), controlPoint2: p(0.5 + sign * 0.18, 0.455))
            NSColor(calibratedWhite: 0.15, alpha: 1).setStroke(); eye.stroke()
        }
        let nose = NSBezierPath(); nose.move(to: p(0.46, 0.41)); nose.line(to: p(0.54, 0.41)); nose.line(to: p(0.5, 0.365)); nose.close()
        pink.darker().setFill(); nose.fill()
        let mouth = NSBezierPath(); mouth.lineWidth = s * 0.016; mouth.lineCapStyle = .round
        mouth.move(to: p(0.5, 0.365)); mouth.line(to: p(0.5, 0.33))
        mouth.move(to: p(0.5, 0.33)); mouth.curve(to: p(0.42, 0.32), controlPoint1: p(0.48, 0.30), controlPoint2: p(0.44, 0.29))
        mouth.move(to: p(0.5, 0.33)); mouth.curve(to: p(0.58, 0.32), controlPoint1: p(0.52, 0.30), controlPoint2: p(0.56, 0.29))
        NSColor(calibratedWhite: 0.2, alpha: 1).setStroke(); mouth.stroke()
        for sign: CGFloat in [-1, 1] {   // whiskers
            for dy: CGFloat in [-0.02, 0.025] {
                let w = NSBezierPath(); w.lineWidth = s * 0.012; w.lineCapStyle = .round
                w.move(to: p(0.5 + sign * 0.16, 0.38 + dy)); w.line(to: p(0.5 + sign * 0.36, 0.40 + dy * 2.5)); w.stroke()
            }
        }
        return true
    }
}

extension NSColor { func darker() -> NSColor { blended(withFraction: 0.25, of: .black) ?? self } }

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let img = draw(CGFloat(px))
        let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
        rep.size = NSSize(width: px, height: px)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}
