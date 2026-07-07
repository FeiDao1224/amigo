#!/usr/bin/env swift
// 通用像素化器（任意图 → 像素风 PNG，自适应 posterize 调色板，非鱼专属）
// 用法: swift tools/pixelize.swift 输入.png 输出.png [块高rows=88] [每通道色阶levels=5] [放大scale=3] [去白底flood=0]
import AppKit
import CoreGraphics

let a = CommandLine.arguments
guard a.count >= 3 else { print("usage: swift pixelize.swift in.png out.png [rows] [levels] [scale] [flood]"); exit(1) }
let inPath = a[1], outPath = a[2]
let rows   = a.count > 3 ? (Int(a[3]) ?? 88) : 88
let levels = a.count > 4 ? (Int(a[4]) ?? 5)  : 5
let scale  = a.count > 5 ? (Int(a[5]) ?? 3)  : 3
let flood  = a.count > 6 ? (a[6] == "1")     : false

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func ctx(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

guard let img = NSImage(contentsOfFile: inPath),
      let src = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("load fail"); exit(1) }

// 1) 缩小到低分辨率（区域平均，得到干净的像素块）
let lowH = rows
let lowW = max(1, Int((Double(src.width) * Double(rows) / Double(src.height)).rounded()))
let low = ctx(lowW, lowH)
low.interpolationQuality = .medium
low.clear(CGRect(x: 0, y: 0, width: lowW, height: lowH))
low.draw(src, in: CGRect(x: 0, y: 0, width: lowW, height: lowH))

guard let buf = low.data else { print("ctx fail"); exit(1) }
let px = buf.bindMemory(to: UInt8.self, capacity: lowW * lowH * 4)
let step = Double(levels - 1)
func post(_ v: Double) -> UInt8 { UInt8((( (v / 255.0 * step).rounded() ) / step * 255.0).rounded()) }

// 2) 可选：从四边 flood-fill 去白底（用户传白底图时）
if flood {
    var seen = [Bool](repeating: false, count: lowW * lowH)
    var q = [(Int, Int)]()
    func isBg(_ x: Int, _ y: Int) -> Bool {
        let i = (y * lowW + x) * 4
        let al = px[i+3]; if al == 0 { return true }
        let r = px[i], g = px[i+1], b = px[i+2]
        return r > 210 && g > 210 && b > 210
    }
    for x in 0..<lowW { q.append((x,0)); q.append((x,lowH-1)) }
    for y in 0..<lowH { q.append((0,y)); q.append((lowW-1,y)) }
    while let (x,y) = q.popLast() {
        if x < 0 || y < 0 || x >= lowW || y >= lowH { continue }
        let idx = y*lowW + x; if seen[idx] { continue }; seen[idx] = true
        if !isBg(x,y) { continue }
        let i = idx*4; px[i]=0; px[i+1]=0; px[i+2]=0; px[i+3]=0
        q.append((x+1,y)); q.append((x-1,y)); q.append((x,y+1)); q.append((x,y-1))
    }
}

// 3) 硬化 alpha + 自适应 posterize（还原真色再量化，边缘干脆）
for i in stride(from: 0, to: lowW*lowH*4, by: 4) {
    let al = px[i+3]
    if al < 128 { px[i]=0; px[i+1]=0; px[i+2]=0; px[i+3]=0; continue }
    let inv = 255.0 / Double(al)   // 反预乘还原真色
    px[i]   = post(min(255, Double(px[i])   * inv))
    px[i+1] = post(min(255, Double(px[i+1]) * inv))
    px[i+2] = post(min(255, Double(px[i+2]) * inv))
    px[i+3] = 255
}

// 4) 最近邻放大 → 硬边像素块烤进 PNG
guard let lowImg = low.makeImage() else { print("low img fail"); exit(1) }
let outW = lowW*scale, outH = lowH*scale
let out = ctx(outW, outH)
out.interpolationQuality = .none
out.draw(lowImg, in: CGRect(x: 0, y: 0, width: outW, height: outH))
guard let outImg = out.makeImage() else { print("out img fail"); exit(1) }

let rep = NSBitmapImageRep(cgImage: outImg)
guard let data = rep.representation(using: .png, properties: [:]) else { print("png fail"); exit(1) }
try! data.write(to: URL(fileURLWithPath: outPath))
print("ok \(lowW)x\(lowH) → \(outW)x\(outH)  levels=\(levels)  flood=\(flood)")
