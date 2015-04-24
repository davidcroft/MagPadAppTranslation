//
//  Constants.swift
//  MagPadV3
//
//  Created by Ding Xu on 3/4/15.
//  Copyright (c) 2015 Ding Xu. All rights reserved.
//

import Foundation
import UIKit

// the length of scope on x axis
//let BUFFERSIZE:Int = 32
let BUFFERSIZE:Int = 64

// color micro definition
let redColor:UIColor = colorWithRGB(0xcc3333, alpha: 1.0)
let greenColor:UIColor = colorWithRGB(0x86cc7d, alpha: 1.0)
let blueColor:UIColor =  colorWithRGB(0x336699, alpha: 1.0)
let pinkColor:UIColor =  colorWithRGB(0xff6666, alpha: 0.9)
let yellowColor:UIColor = colorWithRGB(0xffff66, alpha: 0.8)
let purpleColor: UIColor = colorWithRGB(0x800080, alpha: 0.9)

let transparentPinkColor: UIColor = colorWithRGB(0xff6666, alpha: 0.7)
let transparentGrayColor: UIColor = colorWithRGB(0x333333, alpha: 0.7)
let lineGranphbgColor:UIColor =  colorWithRGB(0xe3f2f6, alpha: 1.0)

// osc
var sendHost:String = ""
//var sendHost:String = "128.237.196.91"
//let sendHost:String = "128.237.197.156"
let sendPort:UInt16 = 3000
let recvPort:UInt16 = 3001

// scroll view
let pdfHeight:Double = 11       // 11 inch
let pdfWidth: Double = 8.5      // 8.5 inch

// OCR
let OCRMAXDIMENSION: CGFloat = 640

// Camera
let CAMERAOFFSETY: CGFloat = 50.0

// color helper function
func colorWithRGB(rgbValue : UInt, alpha : CGFloat = 1.0) -> UIColor {
    let red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255
    let green = CGFloat((rgbValue & 0xFF00) >> 8) / 255
    let blue = CGFloat(rgbValue & 0xFF) / 255
    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
}