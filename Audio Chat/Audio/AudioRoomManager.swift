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
    let frameSize:opus_int32        = 2880 //2880 // 4000 // 320// 4000 // 2000 /// 5760
    let encodeBlockSize:opus_int32  = 5670 //280// 2880 // 160 // 2880  /// 1440
    
    // Define the target format
    let targetSampleRate: Double = 48000.0
    let channelCount: AVAudioChannelCount = 1
    
    var audioRingBuffer:RingBuffer        = RingBuffer<AudioData>(size: 32)
    var audioEncoedRingBuffer:RingBuffer  = RingBuffer<Data>(size: 30)
    
    let audioEngine = AVAudioEngine()
    var playerNodes: [String: AVAudioPlayerNode] = [:]
    let socket: SocketIOClient
    
    // MARK: Instance Variables
    private let conversionQueue = DispatchQueue(label: "conversionQueue")

    var viewParent:ViewController?
    
    init(socketURL: URL, username: String, viewParent:ViewController ) {
        
        self.viewParent = viewParent
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
            try audioSession.setPreferredIOBufferDuration(0.06)// 60ms
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
            DispatchQueue.main.async {
                self.viewParent!.loadingView.isHidden = true
            }
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
        audioEngine.mainMixerNode // this fix bug make app crash
        audioEngine.prepare()
        
        do {
            
            try audioEngine.start()
            
            let timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
                self.checkAndPlayBuffer()
            }
            
//            let senderTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
//                self.checkAndSendBuffer()
//            }
            
        } catch {
            print("Error starting audio engine: \(error)")
        }
        
    }
   
    // play audio
    private func processAudioData(userId: String, data: Data) {
        
        // Decode Opus data to raw PCM
        guard let decodedData = OpusSwiftPort.shared.decodeData(data) else {
            print("Failed to decode Opus data")
            return
        }
        
        //let decodedData = data
        
        // Determine the output format of the audio engine
        let outputFormat = audioEngine.outputNode.outputFormat(forBus: 0)
        
        // Convert decoded data to AVAudioPCMBuffer
        guard let inputBufferFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: self.targetSampleRate, channels: self.channelCount, interleaved: false) else {
            print("Failed to create input buffer format")
            return
        }
        
        guard let audioBuffer = decodedData.toAudioBuffer(format: inputBufferFormat) else {
            print("Failed to create audio buffer from decoded data")
            return
        }
        
        //scheduleAndPlayAudio(userId: userId, buffer: audioBuffer)
        
        
        // Check if resampling is needed
        if inputBufferFormat != outputFormat {
            guard let converter = AVAudioConverter(from: inputBufferFormat, to: outputFormat) else {
                print("Failed to create AVAudioConverter")
                return
            }
            
            let resampledBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: audioBuffer.frameCapacity)!
            
            var error: NSError? = nil
            converter.convert(to: resampledBuffer, error: &error, withInputFrom: { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return audioBuffer
            })
            
            if let error = error {
                print("Error during audio conversion: \(error)")
                return
            }
            
        
            // Use the resampled buffer
            // scheduleAndPlayAudio(userId: userId, buffer: resampledBuffer)
            
            // save it in buffer
            let audioData = AudioData(userId: userId, buffer: resampledBuffer)
            self.audioRingBuffer.write(audioData)
            
        } else {
            // No resampling needed, use the original buffer
            // scheduleAndPlayAudio(userId: userId, buffer: audioBuffer)
            
            // save it in buffer
            let audioData = AudioData(userId: userId, buffer: audioBuffer)
            self.audioRingBuffer.write(audioData)
            
        }
        

    }
    
    // read from buffer then play
    private func checkAndPlayBuffer() {
        if let audioData = audioRingBuffer.read() {
            scheduleAndPlayAudio(userId: audioData.userId, buffer: audioData.buffer)
            //print("Play buffer data")
        }else{
            //print("No buffer data")
        }
    }
    
    // read from buffer then send
    private func checkAndSendBuffer(){
        if let audioData = audioEncoedRingBuffer.read() {
            self.socket.emit("audioData", audioData)
        }
    }
    
    private func scheduleAndPlayAudio(userId: String, buffer: AVAudioPCMBuffer) {
        if let playerNode = playerNodes[userId] {
            playerNode.scheduleBuffer(buffer, at: nil)
            if !playerNode.isPlaying {
                playerNode.play()
            }
        } else {
            let playerNode = AVAudioPlayerNode()
            playerNodes[userId] = playerNode
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: buffer.format)
            playerNode.scheduleBuffer(buffer, at: nil)
            playerNode.play()
            print("Buffer format: \(buffer.format)")
        }
    }

    // send audio
    // this is for info
    // https://github.com/tensorflow/examples/blob/master/lite/examples/speech_commands/ios/SpeechCommands/AudioInputManager/AudioInputManager.swift
    // https://stackoverflow.com/questions/67661093/how-to-get-buffer-from-avaudioengines-installtap-at-high-frequency
    private func startRecording() {
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        // let inputFormat =  AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 1, interleaved: false)!
        
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate, channels: channelCount, interleaved: false)!
        
        // Create a converter to convert the input audio to the target format
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            fatalError("Failed to create AVAudioConverter")
        }
        
        // MARK: check this value
        let frameSize:UInt32 = 5760// 280 // 5760 // 1024
        print("recordingFormat: \(targetFormat)")
        
        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(frameSize), format: inputFormat) { buffer, time in
            
            self.conversionQueue.async {
                                                
                //guard let channelData = buffer.floatChannelData?[0] else {  print("not sendt"); return }
                //guard let channelData = buffer.int16ChannelData?[0] else { print("not sendt");  return }
                
                // Ensure that the buffer format matches the expected input format for the converter
                guard buffer.format == inputFormat else {
                    print("Buffer format does not match the expected input format for the converter")
                    return
                }
                
                
                var error: NSError? = nil
                
                // Create an output buffer with the target format
                //guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(self.targetSampleRate)) else {
                guard let resampledBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: buffer.frameCapacity) else {
                    print("Failed to create output buffer")
                    return
                }
                
                // Perform the conversion
                let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                
                converter.convert(to: resampledBuffer, error: &error, withInputFrom: inputBlock)
                                
                
                if let error = error {
                    print("Error during conversion: \(error)")
                } else {
                    // Here, you can use `outputBuffer` for further processing or output
                    // For example, write it to a file or send it to an audio output node
                    //print("Successfully converted audio")
                }
                
                // Now, outputBuffer contains the audio data in the new format (41,000 Hz, Int16)
                // You can further process or send this data to an audio output node
                
                //let data = resampledBuffer.toData() // resampled buffer
                //let data = buffer.toData() // original buffer
                
                //print("Sent size: \(data.count)")
                
                // encode audio data
                //let packet = OpusSwiftPort.shared.encodeData(data)
                
                //self.socket.emit("audioData", packet ?? Data())
                //self.socket.emit("audioData", data)
                
                // process audio
                let frameLength   = Int(resampledBuffer.frameLength)
                let bufferPointer = resampledBuffer.int16ChannelData!.pointee
                
                // Process the buffer data in chunks
                self.processBufferData(bufferPointer, frameLength: frameLength)
                
                
            }// end of conversionQueue
        }
        
    }
    
    private func processBufferData(_ bufferPointer: UnsafePointer<Int16>, frameLength: Int) {
        let chunkSize = 2880 // 60ms chunk size (48000 * 0.06 seconds)
        
        // Convert the whole buffer to Data
        let data = Data(bytes: bufferPointer, count: frameLength * 2)
        
        var offset = 0
        
        // Process each 60ms chunk
        while offset + chunkSize <= frameLength {
            let chunkData = data.subdata(in: offset..<(offset + chunkSize * 2))
            if let encodedPacket = OpusSwiftPort.shared.encodeData(chunkData) {                
                 self.socket.emit("audioData", encodedPacket)
                // save it to buffer
                //self.audioEncoedRingBuffer.write(encodedPacket)
            }
            offset += chunkSize
        }
    }// end of sending audio data
    
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


struct AudioData {
    let userId: String
    let buffer: AVAudioPCMBuffer
}
