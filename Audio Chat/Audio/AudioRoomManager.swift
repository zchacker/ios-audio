//
//  AudioRoomManager.swift
//  Audio Chat
//
//  Created by Brown Diamond Tech on 7/25/24.
//

import Foundation
import AVFoundation
import SocketIO

class AudioRoomManager {
    
    // audio settings
    let sample_rate:opus_int32      = 48000
    let channel:Int32               = 1
    let frameSize:opus_int32        = 2880 // 4000 // 320// 4000 // 2000 /// 5760
    let encodeBlockSize:opus_int32  = 280// 2880 // 160 // 2880  /// 1440
    
    // Define the target format
    let targetSampleRate: Double = 48000.0
    let channelCount: AVAudioChannelCount = 1
    
    let audioEngine = AVAudioEngine()
    var playerNodes: [String: AVAudioPlayerNode] = [:]
    let socket: SocketIOClient

    init(socketURL: URL, username: String) {
        
        self.socket = SocketHandeler.shared.getSocket()
        
        self.requestMicrophonePermission { granted in
            if granted {
                // open decoder
                OpusSwiftPort.shared.initialize(
                    sampleRate: self.sample_rate,
                    numberOfChannels: self.channel,
                    frameSize: self.frameSize,
                    encodeBlockSize: self.encodeBlockSize
                )
                self.setupSocket(username: username)
                self.setupAudioEngine()
            } else {
                print("Microphone permission not granted")
            }
        }
    }
    
    // request mic permission
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        
        let audioSession = AVAudioSession.sharedInstance()
        
        do {

            try audioSession.setActive(true , options: [.notifyOthersOnDeactivation])
            try audioSession.setCategory( .playAndRecord , mode: .default , options: [ .defaultToSpeaker ])// <-- https://www.hackingwithswift.com/forums/ios/bi-directional-play-record-w-bluetooth-earpods/6137
            try audioSession.setPreferredIOBufferDuration(0.06)
            try audioSession.setPreferredSampleRate(Double(sample_rate))
            
        } catch {
            print("audioSession properties weren't set because of an error.")
        }
        
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    // connect to server
    private func setupSocket(username:String) {
                        
        self.socket.on(clientEvent: .connect) { data, ack in
            print("socket connected")
            self.socket.emit("addUser", ["username": username])
        }

        self.socket.on("audioData") { data, ack in
        
            if let audioDataDict = data[0] as? [String: Any]{
                let userId = audioDataDict["userId"] as? String
                
                guard let audioDataStream = audioDataDict["audio"] else{
                    print("it not found")
                    return
                }
                
                let audioData = audioDataStream as? Data

                guard audioData?.count ?? 0 > 0 else {
                    print("No audio data")
                    return
                }
                
                self.processAudioData(userId: userId!, data: audioData ?? Data())

            }
        }
        
        SocketHandeler.shared.connect()
    }
            
    private func setupAudioEngine() {
        
        self.startRecording()
        
        //let targetInputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate, channels: channelCount, interleaved: true)!
       
        // Connect nodes and start the audio engine
        // audioEngine.connect(audioEngine.inputNode, to: audioEngine.mainMixerNode, format: targetFormat)
        
        let targetOutputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate, channels: channelCount, interleaved: true)!

        // Create a converter for the output side if needed
        let outputConverter = AVAudioConverter(from: audioEngine.outputNode.outputFormat(forBus: 0), to: targetOutputFormat)!

        audioEngine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: targetOutputFormat) { buffer, _ in
            var error: NSError? = nil
            let convertedOutputBuffer = AVAudioPCMBuffer(pcmFormat: targetOutputFormat, frameCapacity: AVAudioFrameCount(self.targetSampleRate))!
            //let convertedOutputBuffer = AVAudioPCMBuffer(pcmFormat: targetOutputFormat, frameCapacity: buffer.frameCapacity)!

            let outputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            outputConverter.convert(to: convertedOutputBuffer, error: &error, withInputFrom: outputBlock)
            // Here you have the resampled output audio data that you can send to the output node
        }
        
        
        audioEngine.mainMixerNode // this fix bug make app crash
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("Error starting audio engine: \(error)")
        }
    }

   
    // play audio
    private func processAudioData(userId: String, data: Data) {
        // decode audio
        //let data = OpusSwiftPort.shared.decodeData(data) ?? Data()
        //let bufferFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
        let bufferFormat = audioEngine.outputNode.outputFormat(forBus: 0)
        //let bufferFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: self.targetSampleRate, channels: 1, interleaved: true)!
        
        //let audioBuffer = AVAudioPCMBuffer(pcmFormat: bufferFormat, frameCapacity:  AVAudioFrameCount(data.count) )!
        //let audioBuffer = AVAudioPCMBuffer(pcmFormat: bufferFormat, frameCapacity:  UInt32(data.count) / bufferFormat.streamDescription.pointee.mBytesPerFrame )!
        //audioBuffer.frameLength = audioBuffer.frameCapacity
        //data.withUnsafeBytes { audioBuffer.int16ChannelData?.pointee.update(from: $0.bindMemory(to: Int16.self).baseAddress!, count: Int(audioBuffer.frameCapacity)) }
        
        let audioBuffer = data.toAudioBuffer(format: bufferFormat)!
        
        if let playerNode = playerNodes[userId] {
            playerNode.scheduleBuffer(audioBuffer, at: nil)
            if !playerNode.isPlaying {
                playerNode.play()
            }
        } else {
            let playerNode = AVAudioPlayerNode()
            playerNodes[userId] = playerNode
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: bufferFormat)
            //audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioEngine.inputNode.outputFormat(forBus: 0))
            playerNode.scheduleBuffer(audioBuffer, at: nil)
            playerNode.play()
            print("Buffer: \(bufferFormat)")
        }
    }

    // send audio
    private func startRecording() {
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        // let inputFormat =  AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 1, interleaved: false)!
        
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate, channels: channelCount, interleaved: true)!
        
        // Create a converter to convert the input audio to the target format
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            fatalError("Failed to create AVAudioConverter")
        }
        
        // MARK: check this value
        let frameSize:UInt32 = 4096// 280 // 5760 // 1024
        print("recordingFormat: \(inputFormat)")
        
        inputNode.installTap(onBus: 0, bufferSize: frameSize, format: inputFormat) { buffer, time in
            //guard let channelData = buffer.floatChannelData?[0] else {  print("not sendt"); return }
            //guard let channelData = buffer.int16ChannelData?[0] else { print("not sendt");  return }
            
            // Ensure that the buffer format matches the expected input format for the converter
            guard buffer.format == inputFormat else {
                print("Buffer format does not match the expected input format for the converter")
                return
            }
            
            var error: NSError? = nil
            
            // Create an output buffer with the target format
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(self.targetSampleRate)) else {
            //guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: buffer.frameCapacity) else {
                print("Failed to create output buffer")
                return
            }
            
            
            // Perform the conversion
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
            
            if let error = error {
                print("Error during conversion: \(error)")
            } else {
                // Here, you can use `outputBuffer` for further processing or output
                // For example, write it to a file or send it to an audio output node
                //print("Successfully converted audio")
            }
            
            // Now, outputBuffer contains the audio data in the new format (41,000 Hz, Int16)
            // You can further process or send this data to an audio output node
            
            //let data = outputBuffer.toData()
            let data = buffer.toData()
            //let data = Data(bytes: channelData, count: Int(buffer.frameCapacity * buffer.format.streamDescription.pointee.mBytesPerFrame))
            print("converted size: \(outputBuffer.toData().count) old: \(data.count)")
            
            // encode audio data
            let packet = OpusSwiftPort.shared.encodeData(data)
            
            //self.socket.emit("audioData", ["audio": packet])
            //self.socket.emit("audioData", packet ?? Data())
            self.socket.emit("audioData", data)
            //self.processAudioData(userId: "Ahmed", data: data )
        }
        
    }
    
}


// MARK: - Helper Extensions
extension AVAudioPCMBuffer {
    func toData() -> Data {
        let audioBuffer = self.audioBufferList.pointee.mBuffers
        return Data(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
    }
}

extension Data {
    func toAudioBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let audioBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(self.count) / format.streamDescription.pointee.mBytesPerFrame)
        audioBuffer?.audioBufferList.pointee.mBuffers.mData?.copyMemory(from: [UInt8](self), byteCount: self.count)
        audioBuffer?.frameLength = audioBuffer!.frameCapacity
        return audioBuffer
    }
}
