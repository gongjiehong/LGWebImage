//
//  LGAPNGEocoder.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/9/29.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation


public typealias LGPNGAlphaType = Int

public let LGPNGAlphaTypePaleete: LGPNGAlphaType = 1<<0
public let LGPNGAlphaTypeColor: LGPNGAlphaType = 1<<1
public let LGPNGAlphaTypeAlpha: LGPNGAlphaType = 1<<2


public enum LGPNGDispose: Int {
    case none = 0
    case background = 1
    case previous = 2
}

public enum LGPNGBlend: Int {
    case source = 0
    case over = 1
}

public struct LGPNGChunkIHDR {
    var width: UInt32 = 0
    var height: UInt32 = 0
    var bitDepth: UInt8 = 0
    var colorType: UInt8 = 0
    var compressionMethod: UInt8 = 0
    var filterMethod: UInt8 = 0
    var interlaceMethod: UInt8 = 0
    
    public init() {
    }
    
    public init(data: [UInt8]) {
        assert(data.count >= 13, "数据长度不够")
        UnsafePointer([data[0], data[1], data[2], data[3]]).withMemoryRebound(to: UInt32.self, capacity: 1) {
            self.width = $0.pointee
        }
        UnsafePointer([data[4], data[5], data[6], data[7]]).withMemoryRebound(to: UInt32.self, capacity: 1) {
            self.height = $0.pointee
        }
        self.bitDepth = data[8]
        self.colorType = data[9]
        self.compressionMethod = data[10]
        self.filterMethod = data[11]
        self.interlaceMethod = data[12]
    }

    public var data: [UInt8] {
        var result = [UInt8](repeating: 0, count: 13)
        result[0] = UInt8(self.width >> 0 & 0x00ff)
        result[1] = UInt8(self.width >> 8 & 0x00ff)
        result[2] = UInt8(self.width >> 16 & 0x00ff)
        result[3] = UInt8(self.width >> 24 & 0x00ff)
        
        result[4] = UInt8(self.height >> 32 & 0x00ff)
        result[5] = UInt8(self.height >> 40 & 0x00ff)
        result[6] = UInt8(self.height >> 48 & 0x00ff)
        result[7] = UInt8(self.height >> 56 & 0x00ff)

        result[8] = self.bitDepth
        result[9] = self.colorType
        result[10] = self.compressionMethod
        result[11] = self.filterMethod
        result[12] = self.interlaceMethod
        
        return result
    }
}

public func LGUint8ArrayToUInt32(data: [UInt8], startIndex: Int) -> UInt32 {
    assert(data.count >= startIndex + 4, "数据长度不够")
    let bytes = [data[startIndex], data[startIndex + 1], data[startIndex + 2], data[startIndex + 3]]
    let pointer = UnsafePointer(bytes)
    var result: UInt32 = 0
    pointer.withMemoryRebound(to: UInt32.self, capacity: 1) {
        result = $0.pointee
    }
    return result
}

public func LGUInt32ToUint8(value: UInt32, index: Int) -> UInt8 {
    return UInt8(swapEndianUInt32(value: value) >> (UInt32(index) * 8) & 0x00ff)
}

public func LGUint8ArrayToUInt16(data: [UInt8], startIndex: Int) -> UInt16 {
    assert(data.count >= startIndex + 2, "数据长度不够")
    let bytes = [data[startIndex], data[startIndex + 1]]
    let pointer = UnsafePointer(bytes)
    var result: UInt16 = 0
    pointer.withMemoryRebound(to: UInt16.self, capacity: 1) {
        result = $0.pointee
    }
    return result
}

public struct LGPNGChunkfcTL {
    var xOffset: UInt32 = 0
    var yOffset: UInt32 = 0
    var width: UInt32 = 0
    var height: UInt32 = 0
    var sequenceNumber: UInt32 = 0
    
    var delayNum: UInt16 = 0
    var delayDen: UInt16 = 0
    
    var dispose: LGPNGDispose = LGPNGDispose.none
    var blend: LGPNGBlend = LGPNGBlend.source
    
    public init() {
        
    }
    
    public init(data: [UInt8]) {
        self.sequenceNumber = swapEndianUInt32(value: LGUint8ArrayToUInt32(data: data, startIndex: 0))
        self.width = swapEndianUInt32(value: LGUint8ArrayToUInt32(data: data, startIndex: 4))
        self.height = swapEndianUInt32(value: LGUint8ArrayToUInt32(data: data, startIndex: 8))
        self.xOffset = swapEndianUInt32(value: LGUint8ArrayToUInt32(data: data, startIndex: 12))
        self.yOffset = swapEndianUInt32(value: LGUint8ArrayToUInt32(data: data, startIndex: 16))
        self.delayNum = swapEndianUInt16(value: LGUint8ArrayToUInt16(data: data, startIndex: 20))
        self.delayDen = swapEndianUInt16(value: LGUint8ArrayToUInt16(data: data, startIndex: 22))
        self.dispose = LGPNGDispose(rawValue: Int(data[24])) ?? LGPNGDispose.none
        self.blend = LGPNGBlend(rawValue: Int(data[25])) ?? LGPNGBlend.source
    }
    
    public var data: [UInt8] {
        var result = [UInt8](repeating: 0, count: 26)
        
        for index in 0...3 {
            result[index] = LGUInt32ToUint8(value: self.sequenceNumber, index: index % 4)
        }
        
        for index in 4...7 {
            result[index] = LGUInt32ToUint8(value: self.width, index: index % 4)
        }
        
        for index in 8...11 {
            result[index] = LGUInt32ToUint8(value: self.height, index: index % 4)
        }
        
        for index in 12...15 {
            result[index] = LGUInt32ToUint8(value: self.xOffset, index: index % 4)
        }
        
        for index in 16...19 {
            result[index] = LGUInt32ToUint8(value: self.yOffset, index: index % 4)
        }
        
        for index in 20...21 {
            result[index] = LGUInt32ToUint8(value: self.yOffset, index: index % 2)
        }
        
        for index in 22...23 {
            result[index] = LGUInt32ToUint8(value: self.yOffset, index: index % 2)
        }
        
        result[24] = UInt8(self.dispose.rawValue)
        
        result[25] = UInt8(self.blend.rawValue)
        
        return result
    }
}

public struct LGPNGChunkInfo {
    var offset: UInt32 = 0
    var fourcc: UInt32 = 0
    var length: UInt32 = 0
    var crc32: UInt32 = 0
    
    public init() {
        
    }
}

public struct LGPNGFrameInfo {
    var chunkIndex: UInt32 = 0
    var chunkNum: UInt32 = 0
    var chunkSize: UInt32 = 0
    var frameControl: LGPNGChunkfcTL = LGPNGChunkfcTL()
    
    public init() {
        
    }
}

public struct LGPNGInfo {
    public var header: LGPNGChunkIHDR?
    public var chunks: [LGPNGChunkInfo] = [LGPNGChunkInfo]()
    public var apngFrames: [LGPNGFrameInfo] = [LGPNGFrameInfo]()
    
    public var apngLoopNum: UInt32 = 0
    public var apngSharedChunkIndexs: [UInt32] = [UInt32]()
    public var apngSharedChunkSize: UInt32 = 0
    public var apngSharedInsertIndex: UInt32 = 0
    public var apngFirstFrameIsCover: Bool = false
    
    public init(data: [UInt8], length: Int) throws {
        if length < 32 {
            throw LGImageCoderError.pngDataLengthInvalid
        }
        
        var magicNum = LGUint8ArrayToUInt32(data: data, startIndex: 0)
        if magicNum != _four_cc(c1: 0x89, c2: 0x50, c3: 0x4E, c4: 0x47) {
            throw LGImageCoderError.pngFormatInvalid
        }
        magicNum = LGUint8ArrayToUInt32(data: data, startIndex: 4)
        if magicNum != _four_cc(c1: 0x0D, c2: 0x0A, c3: 0x1A, c4: 0x0A) {
            throw LGImageCoderError.pngFormatInvalid
        }
        let chunkReallocNum: UInt32 = 16
        var chunks = LGPNGChunkInfo()
        var offset: UInt32 = 8
        var chunkNum: UInt32 = 0
        var chunkCapcity: UInt32 = 16
        var apngLoopNum: UInt32 = 0
        
        var apngSequenceIndex: Int32 = -1
        var apngFrameIndex: Int32 = 0
        var apngFrameNumber: Int32 = -1
        
        var apngChunkError = false
        
        
//        repeat {
//            if chunkNum >= chunkCapcity {
//                chunkCapcity += chunkReallocNum
//            }
//            var chunk = LGPNGChunkInfo()
//            var chunkData = data[Int(offset)..<data.count]
//            chunk.offset = offset
//            chunk.length =
//        } while (offset + 12 <= length)
//        
//        
    }
    
    public init() {
        
    }
}

fileprivate func swapEndianUInt16(value: UInt16) -> UInt16 {
    return ((value & 0x00FF) << 8) | ((value & 0xFF00) >> 8)
}

fileprivate func swapEndianUInt32(value: UInt32) -> UInt32 {
    return ((value & 0x000000FF) << 24) |
        ((value & 0x0000FF00) <<  8) |
        ((value & 0x00FF0000) >>  8) |
        ((value & 0xFF000000) >> 24)
}






