//
//  LGEorror.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/9/7.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation

public enum LGCacheError: Error {
    case errorWith(code: ErrorCode, description: String)
    
    public enum ErrorCode: Int {
        case paramEncodeError = 0
        case closeDBFailed
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


