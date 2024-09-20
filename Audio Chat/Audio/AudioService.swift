//
//  AudioService.swift
//  Audio Chat
//
//  Created by Brown Diamond Tech on 9/14/24.
//

import Foundation
import AVFoundation
import SocketIO

// https://arvindhsukumar.medium.com/using-avaudioengine-to-record-compress-and-stream-audio-on-ios-48dfee09fde4
public class AudioService {
    
    // audio settings
    let sample_rate:opus_int32      = 48000
    let channel:Int32               = 1
    let frameSize:opus_int32        = 2880 // 120, 240, 480, 960, 1920, and 2880 48Hz
    let encodeBlockSize:opus_int32  = 5670 //280// 2880 // 160 // 2880  /// 1440
    
    
    // Define the target format
    let targetSampleRate: Double = 48000.0// 44100.0
    let channelCount: AVAudioChannelCount = 1
    let interleaved:Bool = true
    
    var playerConverter : AVAudioConverter?
    var hardwarePlayerFormat: AVAudioFormat?
    var outFormat: AVAudioFormat?
    
    var audioRingBuffer:RingBuffer        = RingBuffer<AudioData>(size: 32)
    var audioEncoedRingBuffer:RingBuffer  = RingBuffer<AVAudioPCMBuffer>(size: 15)
    
    let audioEngine = AVAudioEngine()
    var playerNodes: [String: AVAudioPlayerNode] = [:]
    let socket: SocketIOClient
    
    // MARK: Instance Variables
    private let conversionQueue = DispatchQueue(label: "conversionQueue")
    let threadQueue             = DispatchQueue(label: "audioConversionQueue", qos: .background)
    
    var viewParent:ViewController?
    
    init(socketURL: URL, username: String, viewParent:ViewController ) {
        
        self.viewParent = viewParent
        self.socket     = SocketHandeler.shared.getSocket()
                
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
    
    // MARK: Prepare audio to open and play
    
    // request mic permission
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setActive(true , options: [.notifyOthersOnDeactivation])
            try audioSession.setCategory( .playAndRecord , mode: .default , options: [ .defaultToSpeaker, .allowAirPlay, .allowBluetooth ])
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
    
    // setup audio engine
    private func setupAudioEngine() {
        
        self.startRecording()
        
        audioEngine.mainMixerNode // this fix bug make app crash
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            print("Error starting audio engine: \(error)")
        }
        
//        let timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
//            self.checkAndSendBuffer()
//        }
        
        // outputNode for speakers
        self.hardwarePlayerFormat = audioEngine.outputNode.inputFormat(forBus: 0)
        self.outFormat   = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: channelCount,
            interleaved: self.interleaved
        )!
        
        self.playerConverter = AVAudioConverter(from: self.outFormat! , to: self.hardwarePlayerFormat!)
        self.playerConverter?.sampleRateConverterQuality = .max
            
    }
    
    // play audio
    private func processAudioData(userId: String, data: Data) {
        
        // Decode Opus data to raw PCM
        guard let decodedData = OpusSwiftPort.shared.decodeData(data) else {
            print("Failed to decode Opus data")
            return
        }

        guard let audioBuffer = decodedData.bestToAudioBuffer(format: self.outFormat!) else {
            print("Failed to create audio buffer from decoded data")
            return
        }
        
        // Check if resampling is needed
        if self.hardwarePlayerFormat != self.outFormat {
            
            let ratio = self.targetSampleRate / self.hardwarePlayerFormat!.sampleRate
            let frameCapacity = AVAudioFrameCount(Double(audioBuffer.frameCapacity) * ratio)
            
            let resampledBuffer = AVAudioPCMBuffer(pcmFormat: self.hardwarePlayerFormat!, frameCapacity: audioBuffer.frameCapacity)!
            //resampledBuffer.frameLength = resampledBuffer.frameCapacity
          
            var error: NSError? = nil
            self.playerConverter?.convert(to: resampledBuffer, error: &error, withInputFrom: { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return audioBuffer
            })
            
            if let error = error {
                print("Error during audio conversion: \(error)")
                return
            }
                    
            // Use the resampled buffer
             scheduleAndPlayAudio(userId: userId, buffer: resampledBuffer)
            
            // save it in buffer
//            let audioData = AudioData(userId: userId, buffer: resampledBuffer)
//            self.audioRingBuffer.write(audioData)
            
        } else {
            // No resampling needed, use the original buffer
             scheduleAndPlayAudio(userId: userId, buffer: audioBuffer)
            
            // save it in buffer
//            let audioData = AudioData(userId: userId, buffer: audioBuffer)
//            self.audioRingBuffer.write(audioData)
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
        if let buffer = self.audioEncoedRingBuffer.read() {
            // process audio
            let frameLength   = Int(buffer.frameLength)
            let bufferPointer = buffer.int16ChannelData!.pointee
            
            // Process the buffer data in chunks
            self.processBufferData(bufferPointer, frameLength: frameLength)
        }
    }
    
    // send data to hardware
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
        }
    }
    
    // MARK: this section gettting audio from mic and send to network
    
    // send audio
    private func startRecording() {
        
        let inputNode   = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: channelCount,
            interleaved: self.interleaved
        )!
        
        // Create a converter to convert the input audio to the target format
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            fatalError("Failed to create AVAudioConverter")
        }
        
        converter.sampleRateConverterQuality = .max
        
        // MARK: check this value
        let frameSize:UInt32 = 5760// 2880*2 //256// 2880*4 //5760// 280 // 5760 // 1024

        inputNode.installTap(onBus: 0, bufferSize: frameSize, format: inputFormat) { buffer, time in
                        
            if inputFormat != targetFormat {
                
                // Ensure that the buffer format matches the expected input format for the converter
                guard buffer.format == inputFormat else {
                    print("Buffer format does not match the expected input format for the converter")
                    return
                }
                
                var error: NSError? = nil
                
                let ratio = self.targetSampleRate / inputFormat.sampleRate
                let frameCapacity = AVAudioFrameCount(Double(buffer.frameCapacity) * ratio)
                
                // Create an output buffer with the target format
                //guard let resampledBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(self.targetSampleRate)) else {
                guard let resampledBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: buffer.frameCapacity) else {
                    print("Failed to create output buffer")
                    return
                }
                
//                print("buffer : \(buffer.frameLength)")
//                return // stop
                
                // Perform the conversion
                let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                
                converter.convert(to: resampledBuffer, error: &error, withInputFrom: inputBlock)
                
  
                if let error = error {
                    print("Error during conversion: \(error)")
                }

//                self.audioEncoedRingBuffer.write(resampledBuffer)
                
                // process audio
                let frameLength   = Int(resampledBuffer.frameLength)
                let bufferPointer = resampledBuffer.int16ChannelData!.pointee
                
                // Process the buffer data in chunks
                self.processBufferData(bufferPointer, frameLength: frameLength)
                
                
            }else{
                
//                self.audioEncoedRingBuffer.write(buffer)
                
                // process audio
                let frameLength   = Int(buffer.frameLength)
                let bufferPointer = buffer.int16ChannelData!.pointee
                
                // Process the buffer data in chunks
                self.processBufferData(bufferPointer, frameLength: frameLength)
                
            }
                            
        }
        
    }
    
    private func processBufferData(_ bufferPointer: UnsafePointer<Int16>, frameLength: Int) {
       
        let chunkSizeInFrames = 2880 // 60ms chunk size in frames
        let chunkSizeInBytes  = chunkSizeInFrames * MemoryLayout<Int16>.size // 5760 bytes
        
        // Convert the whole buffer to Data
        let data = Data(bytes: bufferPointer, count: frameLength * MemoryLayout<Int16>.size)
        
        var offset = 0
        let totalLength = data.count
        
        // Process each 5760-byte chunk
        while offset + chunkSizeInBytes <= totalLength {
            // Extract a 5760-byte chunk (2880 frames)
            let chunkData = data.subdata(in: offset..<(offset + chunkSizeInBytes))
            
            // Pass the chunk to the Opus encoder
            if let encodedPacket = OpusSwiftPort.shared.encodeData(chunkData) {
                //threadQueue.async {
                    self.socket.emit("audioData", encodedPacket)
               // }
            }
            
            offset += chunkSizeInBytes
        }
        
        
    }// end of sending audio data
    
}

extension AVAudioPCMBuffer {
    
    public func convertToData() -> Data {
        let format = self.format
        let frameLength = Int(self.frameLength)
        
        let audioBuffer = self.audioBufferList.pointee.mBuffers
        
        switch format.commonFormat {
        case .pcmFormatFloat32:
            // Handle Float32 format
            guard let channelData = self.floatChannelData else {
                return Data()
            }
            let channelDataPointer = channelData.pointee
            let channelDataSize = frameLength * MemoryLayout<Float32>.size
            return Data(bytes: channelDataPointer, count: channelDataSize)
            
        case .pcmFormatInt16:
            // Handle Int16 format
            guard let channelData = self.int16ChannelData else {
                return Data()
            }
            let channelDataPointer = channelData.pointee
            let channelDataSize = frameLength * MemoryLayout<Int16>.size
            //print("mDataByteSize: \(Int(audioBuffer.mDataByteSize)), channelDataSize: \(channelDataSize)")
            return Data(bytes: channelDataPointer, count: channelDataSize)

        case .pcmFormatInt32:
            // Handle Int32 format
            guard let channelData = self.int32ChannelData else {
                return Data()
            }
            let channelDataPointer = channelData.pointee
            let channelDataSize = frameLength * MemoryLayout<Int32>.size
            return Data(bytes: channelDataPointer, count: channelDataSize)

        default:
            // Unsupported format
            print("Unsupported format")
            return Data()
        }
    }
    
}


extension Data {
    
    func bestToAudioBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Calculate the frame capacity based on the data size and format
        let frameCapacity = UInt32(self.count) / format.streamDescription.pointee.mBytesPerFrame
        guard let audioBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }
        
        audioBuffer.frameLength = frameCapacity

        switch format.commonFormat {
        case .pcmFormatFloat32:
            // Handle Float32 format
            guard let channelData = audioBuffer.floatChannelData else { return nil }
            self.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                let floatData = bytes.bindMemory(to: Float32.self)
                for channel in 0..<Int(format.channelCount) {
                    channelData[channel].assign(from: floatData.baseAddress!, count: Int(audioBuffer.frameLength))
                }
            }

        case .pcmFormatInt16:
            // Handle Int16 format
            guard let channelData = audioBuffer.int16ChannelData else { return nil }
            self.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                let int16Data = bytes.bindMemory(to: Int16.self)
                for channel in 0..<Int(format.channelCount) {
                    channelData[channel].assign(from: int16Data.baseAddress!, count: Int(audioBuffer.frameLength))
                }
            }

        case .pcmFormatInt32:
            // Handle Int32 format
            guard let channelData = audioBuffer.int32ChannelData else { return nil }
            self.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                let int32Data = bytes.bindMemory(to: Int32.self)
                for channel in 0..<Int(format.channelCount) {
                    channelData[channel].assign(from: int32Data.baseAddress!, count: Int(audioBuffer.frameLength))
                }
            }

        default:
            // Unsupported format
            return nil
        }
        
        return audioBuffer
    }
        
}
