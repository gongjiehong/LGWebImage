//
//  ViewController.swift
//  LGWebImageDemo
//
//  Created by 龚杰洪 on 2018/4/9.
//  Copyright © 2018年 龚杰洪. All rights reserved.
//

import UIKit
import LGWebImage
import LGHTTPRequest

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        print("0\(CACurrentMediaTime())")
        for index in 0...5 {
            let imageView = UIImageView(frame: CGRect(x: 0, y: 50 * index, width: 50, height: 50))
            self.view.addSubview(imageView)
            
            LGWebImageManager.default.downloadImageWith(url: "http://staticfile.cxylg.com/%E6%97%A0%E7%A0%81%E5%A4%A7%E5%9B%BE.jpg",
                                                        options: LGWebImageOptions.default,
                                                        progress:
                { (progress) in
                    print(progress.fractionCompleted)
            }) { (image, originUrl, sourceType, stage, error) in
                if error != nil {
                    
                } else {
                    print(image!)
                    DispatchQueue.main.async {
                        imageView.image = image
                        print(CACurrentMediaTime())
                    }
                }
            }
        }
        print("1\(CACurrentMediaTime())")
        
        
//        let imageView2 = UIImageView(frame: CGRect(x: 0, y: 320, width: 320, height: 320))
//
//        self.view.addSubview(imageView1)
//        self.view.addSubview(imageView2)
//        print(CACurrentMediaTime())
//        LGWebImageManager.default.downloadImageWith(url: "http://staticfile.cxylg.com/%E6%97%A0%E7%A0%81%E5%A4%A7%E5%9B%BE.jpg",
//                                                    options: LGWebImageOptions.default,
//                                                    progress:
//            { (progress) in
//            print(progress.fractionCompleted)
//        }) { (image, originUrl, sourceType, stage, error) in
//            if error != nil {
//
//            } else {
//                print(image!)
//                DispatchQueue.main.async {
//                    imageView1.image = image
//                    print(CACurrentMediaTime())
//                }
//            }
//        }
        
//        let request = LGURLSessionManager.default.request("https://isparta.github.io/compare-webp/image/gif_webp/webp/1.webp",
//                                            method: LGHTTPMethod.get)
//        request.validate().response { (response) in
//            print(response)
//        }
//        
//        request.stream { (data) in
//            print(data)
//        }
//        
//        request.downloadProgress(queue: DispatchQueue.userInteractive) { (progress) in
//            print(progress)
//        }
        
//        LGWebImageManager.default.downloadImageWith(url: "https://isparta.github.io/compare-webp/image/gif_webp/webp/1.webp",
//                                                    options: LGWebImageOptions.default,
//                                                    progress:
//            { (progress) in
//                print(progress.fractionCompleted)
//        }) { (image, originUrl, sourceType, stage, error) in
//            if error != nil {
//                
//            } else {
//                print(image!)
//                DispatchQueue.main.async {
//                    imageView2.image = image
//                }
//            }
//        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

