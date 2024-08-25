//
//  ViewController.swift
//  Audio Chat
//
//  Created by Brown Diamond Tech on 7/25/24.
//

import UIKit

class ViewController: UIViewController {

    @IBOutlet var start_btn:UIButton!
    @IBOutlet var username:UITextField!
    @IBOutlet var exit_btn:UIButton!
    var online = false
    var audioRoomManager: AudioRoomManager?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.                        
        
    }
    
    @IBAction func start_room(){
        let username = self.username.text ?? ""
        DispatchQueue.global(qos: .background).async {
            let socketURL = URL(string: "http://192.168.100.17:3000")!
            self.audioRoomManager = AudioRoomManager(socketURL: socketURL, username: username)
        }
        self.online = true
        self.exit_btn.isHidden = false
        self.username.isEnabled = false
        self.start_btn.isHidden = true
    }

    @IBAction func exit_room(){
        SocketHandeler.shared.disconnect()
        self.exit_btn.isHidden = true
        self.username.isEnabled = true
        self.start_btn.isHidden = false
        exit(0)
    }

}

