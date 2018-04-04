//
//  LGWebImageURLRequestConvertible.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/11/9.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation

public protocol LGWebImageURLRequestConvertible {
    func asURLRequest() throws -> URLRequest
}

public protocol LGWebImageURLConvertible {
    func asURL() throws -> URL
}


extension String: LGWebImageURLConvertible, LGWebImageURLRequestConvertible {
    public func asURL() throws -> URL {
        guard let url = URL(string: self) else {
            throw LGWebImageDownloaderError.errorWith(code: LGWebImageDownloaderError.ErrorCode.invalidPath,
                                                      description: "无效的路径")
        }
        return url
    }
    
    public func asURLRequest() throws -> URLRequest {
        let url = try self.asURL()
        return URLRequest(url: url)
    }
}


extension URLRequest: LGWebImageURLRequestConvertible {
    public func asURLRequest() throws -> URLRequest {
        return self
    }
}

extension URL: LGWebImageURLRequestConvertible, LGWebImageURLConvertible {
    public func asURLRequest() throws -> URLRequest {
        return URLRequest(url: self)
    }
    
    public func asURL() throws -> URL {
        return self
    }
}
