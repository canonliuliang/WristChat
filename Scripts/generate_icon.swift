// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
// Two offset conversation contours: an open question and a returning answer.
// Broad strokes survive the watch launcher scale; all artwork stays inside the circular safe area.
context.setLineWidth(68)
context.setLineCap(.round)
context.setLineJoin(.round)
context.setStrokeColor(CGColor(red: 0, green: 0.831, blue: 0.737, alpha: 1))
context.move(to: CGPoint(x: 628, y: 742))
context.addLine(to: CGPoint(x: 386, y: 742))
context.addCurve(to: CGPoint(x: 252, y: 602), control1: CGPoint(x: 302, y: 742), control2: CGPoint(x: 252, y: 688))
context.addLine(to: CGPoint(x: 252, y: 354))
context.addLine(to: CGPoint(x: 360, y: 420))
context.addLine(to: CGPoint(x: 556, y: 420))
context.strokePath()
context.setStrokeColor(CGColor(red: 0.94, green: 0.98, blue: 0.96, alpha: 1))
context.move(to: CGPoint(x: 396, y: 282))
context.addLine(to: CGPoint(x: 638, y: 282))
context.addCurve(to: CGPoint(x: 772, y: 422), control1: CGPoint(x: 722, y: 282), control2: CGPoint(x: 772, y: 336))
context.addLine(to: CGPoint(x: 772, y: 670))
context.addLine(to: CGPoint(x: 664, y: 604))
context.addLine(to: CGPoint(x: 468, y: 604))
context.strokePath()
let image = context.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not save icon") }
print("Saved app icon")
