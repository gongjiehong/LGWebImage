//
//  LGImageCoderError.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/9/25.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation

public enum LGImageCoderError: Error {
    case errorWith(code: ErrorCode, description: String)
    
    public enum ErrorCode: Int {
        case emptyData = 0
        case frameCountInvalid
        case imageTypeInvalid
        case pngDataLengthInvalid
        case pngFormatInvalid
        case frameDataInvalid
        case imageSourceInvalid
    }
    
    var errorInfo: (code: ErrorCode?, des: String?) {
        switch self {
        case .errorWith(code: let code, description: let desc):
            return (code, desc)
        default:
            return (nil, nil)
        }
    }
}
