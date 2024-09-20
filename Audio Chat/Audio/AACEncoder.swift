//
//  AACEncoder.swift
//  Audio Chat
//
//  Created by Brown Diamond Tech on 9/20/24.
//

import Foundation
import AVFoundation

public class AACEncoder {
    
    var aacFormat : AVAudioFormat?
    var encoderConverter : AVAudioConverter?
    
    var sampleRate:Double  = 48000
    var channels:UInt32    = 1
    var interleaved:Bool   = false
    let conversionQueue    = DispatchQueue(label: "audioConversionQueue", qos: .userInitiated)
    
    public init(sampleRate: Double, channels: UInt32, interleaved: Bool){
        self.sampleRate     = sampleRate
        self.channels       = channels
        self.interleaved    = interleaved
        
        self.setUpEncoder()
    }
    
    private func setUpEncoder(){
        
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate:     self.sampleRate,
            channels:       self.channels,
            interleaved:    self.interleaved
        )!
        
        // Create an AudioStreamBasicDescription for AAC
        var outDesc = AudioStreamBasicDescription(
            mSampleRate: 8000,              // Example sample rate
            mFormatID: kAudioFormatMPEG4AAC,// codec type
            mFormatFlags: AudioFormatFlags(MPEG4ObjectID.AAC_LC.rawValue),
            mBytesPerPacket: 0,             // Set to 0 for compressed formats
            mFramesPerPacket: 1024,         // AAC typically uses 1024 frames per packet
            mBytesPerFrame: 0,              // Compressed formats: 0
            mChannelsPerFrame: 1,           // Mono audio
            mBitsPerChannel: 0,             // Compressed formats: 0
            mReserved: 0
        )
        
        
        guard let outputFormat = AVAudioFormat(streamDescription: &outDesc) else {
            print("Failed to create output format.")
            return
        }
        
        self.aacFormat = outputFormat
        
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            print("Failed to create AVAudioConverter.")
            print("Input format: \(inputFormat)")
            print("Output format: \(outputFormat)")
            return
        }
        converter.bitRate = 24000
        
        self.encoderConverter = converter // we can reuse this again
        
    }
    
    // encode audio to AAC
    public func convertPCMBufferToAAC(inBuffer: AVAudioPCMBuffer) -> AVAudioCompressedBuffer {
        
        // Prepare an output buffer
        let outBuffer = AVAudioCompressedBuffer(
            format: self.aacFormat!,
            packetCapacity: 8,
            maximumPacketSize: self.encoderConverter!.maximumOutputPacketSize
        )
        
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inBuffer
        }
        
        var error: NSError?
        
        let status = self.encoderConverter!.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        
        // Error handling and conversion status check
        if status == .error || error != nil {
            print("Error during conversion: \(error?.localizedDescription ?? "Unknown error")")
            return AVAudioCompressedBuffer()
        } else {
            //print("Conversion: \(outBuffer.byteLength) \(outBuffer.packetCount) successful! Ready to send.")
            return outBuffer
        }
        
    }
    
}


extension AVAudioCompressedBuffer {
    
    func toData() -> Data {
        // The audio data starts at `data`, and its length is determined by `byteLength`.
        let bufferPointer = self.data
        let dataSize = Int(self.byteLength)
        
        // Create a Data object from the buffer's raw data
        let audioData = Data(bytes: bufferPointer, count: dataSize)
        
        return audioData
    }
    
}
