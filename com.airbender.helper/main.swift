//
//  main.swift
//  
//
//  Created by John Cris Antor on 6/11/2026.
//

import Foundation

NSLog("[AirBenderHelper] Starting privileged helper.")

let delegate = HelperService()
let listener = NSXPCListener(machServiceName: "com.airbender.helper")
listener.delegate = delegate
listener.resume()

NSLog("[AirBenderHelper] XPC listener is running.")
RunLoop.current.run()
