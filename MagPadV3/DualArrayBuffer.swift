//
//  DualArrayBuffer.swift
//  MagPadV3
//
//  Created by Ding Xu on 3/4/15.
//  Copyright (c) 2015 Ding Xu. All rights reserved.
//

import UIKit

class DualArrayBuffer: NSObject {
    
    // buffer data: dual buffer
    var data: Array<CGFloat>
    
    var dataIndex: Int
    var bufferIndex: Bool   // false for buffer 1 and true for buffer 2
    let bufferSize: Int     // max capacity for each axis
    let bufferOffset: Int   // offset from buffer 1 to buffer 2
    
    init(bufSize:Int) {
        // init the size of buffer
        data = Array<CGFloat>(count: bufSize*3*2, repeatedValue:0)
        
        // init buffersize and bufferOffset
        bufferSize = bufSize
        bufferOffset = bufSize*3
        
        // data index in buffer
        dataIndex = 0
        
        // false for buffer 1 and true for buffer 2
        bufferIndex = false
        
        super.init()
    }
    
    // add new data into buffer and return if a buffer is full
    func addDatatoBuffer(valX:Double, valY:Double, valZ:Double) -> Bool {
        
        var result:Bool = false;
        
        // storage data
        if (self.dataIndex < self.bufferSize) {
            
            // store into buffer
            var idx = self.dataIndex*3 + (self.bufferIndex ? self.bufferOffset : 0)
            self.data[idx] = CGFloat(valX)
            self.data[idx+1] = CGFloat(valY)
            self.data[idx+2] = CGFloat(valZ)
            
            // update dataIndex
            self.dataIndex++
            
            //result = false
        }
        
        // check if buffer is full
        if (self.dataIndex >= self.bufferSize) {
            // update buffer inner index
            self.dataIndex = 0
            // change buffer index
            self.bufferIndex = !self.bufferIndex
            // update result
            result = true
        }
        
        return result
    }
    
    func generateStringForOSC() -> String {
        // check which buffer is being used now and the other is the buffered one for OSC
        var str:String = ""
        
        // self.bufferIndex == true:  buffer 2 is being used now and buffer 1 is ready for OSC
        // self.bufferIndex == false: buffer 1 is being used now and buffer 2 is ready for OSC
        var idx:Int = (self.bufferIndex ? 0 : self.bufferOffset)
        
        for i in 0...self.bufferSize-1 {
            str += "\(self.data[idx++]) \(self.data[idx++]) \(self.data[idx++]) "
        }
        
        return str
    }
    
}
