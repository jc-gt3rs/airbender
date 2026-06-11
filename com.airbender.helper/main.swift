//
//  main.swift
//  
//
//  Created by John Cris Antor on 6/11/2026.
//

import Foundation

let delegate = HelperService()
let listener = NSXPCListener(machServiceName: "com.airbender.helper")
listener.delegate = delegate
listener.resume()

RunLoop.current.run()
