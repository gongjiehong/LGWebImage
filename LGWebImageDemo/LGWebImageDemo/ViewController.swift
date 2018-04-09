//
//  ViewController.swift
//  LGWebImageDemo
//
//  Created by 龚杰洪 on 2018/4/9.
//  Copyright © 2018年 龚杰洪. All rights reserved.
//

import UIKit
import LGWebImage

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        LGWebImageManager.default.downloadImageWith(url: "https://dtaw5kick3bfu.cloudfront.net/2794/C9122688-1A7E-B74A-DFC4-323F16D43C43.jpg",
                                                    options: LGWebImageOptions.default,
                                                    progress:
            { (progress) in
            print(progress.fractionCompleted)
        }) { (image, originUrl, sourceType, stage, error) in
            if error != nil {
                
            } else {
                print(image!)
            }
        }
        LGWebImageManager.default.downloadImageWith(url: "https://isparta.github.io/compare-webp/image/gif_webp/webp/1.webp",
                                                    options: LGWebImageOptions.default,
                                                    progress:
            { (progress) in
                print(progress.fractionCompleted)
        }) { (image, originUrl, sourceType, stage, error) in
            if error != nil {
                
            } else {
                print(image!)
            }
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

