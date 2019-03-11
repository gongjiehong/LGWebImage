//
//  LGExpiry.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2019/3/6.
//  Copyright © 2019年 龚杰洪. All rights reserved.
//

import Foundation


/// 缓存过期定义
///
/// - never: 永不过期
/// - ageLimit: 多少秒后过期
public enum LGExpiry {
    case never
    case ageLimit(TimeInterval)
}
