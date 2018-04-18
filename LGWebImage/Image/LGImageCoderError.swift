//
//  LGImageCoderError.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/9/25.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation

public enum LGImageCoderError: Error {
    case imageDataIsEmpty
    case frameCountInvalid
    case imageTypeInvalid
    case pngDataLengthInvalid
    case pngFormatInvalid
    case frameImageInputInvalid
    case frameDataInvalid
    case frameDataPathInvalid
    case imageSourceInvalid
    case imageTypeNotSupport(type: LGImageType)
}


extension LGImageCoderError: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .imageDataIsEmpty:
            return "The data to be decoded is empty"
        case .frameCountInvalid:
            return "Image framecount is incorrect"
        case .imageTypeInvalid:
            return "Unable to read picture format"
        case .pngDataLengthInvalid:
            return "The length of the encoded data is not enough"
        case .pngFormatInvalid:
            return "Data is not in png format"
        case .frameImageInputInvalid:
            return "Frame image input invalid"
        case .frameDataInvalid:
            return "Frame image data invalid"
        case .frameDataPathInvalid:
            return "Frame image input file path invalid"
        case .imageSourceInvalid:
            return "Original UIImage is invalid"
        case .imageTypeNotSupport(let type):
            let typeString = LGImageTypeToUIType(type: type) ?? "unkonwn" as CFString
            return "Image format is not supported within this framework \(typeString)"
        }
    }
    
    public var debugDescription: String {
        return self.description
    }
}
