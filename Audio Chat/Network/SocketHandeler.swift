//
//  SocketManager.swift
//  Audio Chat
//
//  Created by Brown Diamond Tech on 8/4/24.
//

import Foundation
import SocketIO

class SocketHandeler : NSObject {
    
    public static let shared = SocketHandeler()
    //let manager = SocketManager(socketURL: URL(string: "http://192.168.100.17:3000")!, config: [.log(false), .compress])
    let manager = SocketManager(socketURL: URL(string: "https://voice.ovemenu.com")!, config: [.log(false), .compress])

    let socket: SocketIOClient!
    
    override init() {
        self.socket = self.manager.defaultSocket
    }
    
    func getSocket() -> SocketIOClient {
        return self.socket
    }
    
    func connect(){
        self.socket.connect()
    }
    
    func disconnect(){
        self.socket.disconnect()
    }
    
}
