//
//  String+Extensions.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/9/12.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation
import CCommonCrypto


// MARK: - just for this framework

extension String {
    func md5Hash() -> String? {
        let length = Int(CC_MD5_DIGEST_LENGTH)
        
        guard let data = self.data(using: String.Encoding.utf8) else { return nil }
        
        let hash = data.withUnsafeBytes { (bytes: UnsafePointer<Data>) -> [UInt8] in
            var hash: [UInt8] = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            CC_MD5(bytes, CC_LONG(data.count), &hash)
            return hash
        }
        
        return (0..<length).map { String(format: "%02x", hash[$0]) }.joined()
    }
    
    var lg_length: Int {
        return self.count
    }
}






