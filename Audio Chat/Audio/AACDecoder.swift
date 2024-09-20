//
//  AACDecoder.swift
//  Audio Chat
//
//  Created by Brown Diamond Tech on 9/20/24.
//

import Foundation
import AVFoundation

public class AACDecoder {
    
    var pcmFormat : AVAudioFormat?
    var decoderConverter : AVAudioConverter?
    
    var sampleRate:Double  = 48000
    var channels:UInt32    = 1
    var interleaved:Bool   = false
    
    
    public init(sampleRate: Double, channels: UInt32, interleaved: Bool){
        self.sampleRate     = sampleRate
        self.channels       = channels
        self.interleaved    = interleaved
        
        self.setUpDecoder()
    }
    
    private func setUpDecoder(){
        
        // Create an AudioStreamBasicDescription for AAC (input format)
        var aacFormatDesc = AudioStreamBasicDescription(
            mSampleRate: 8000,  // Example sample rate
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: AudioFormatFlags(MPEG4ObjectID.AAC_LC.rawValue),
            mBytesPerPacket: 0,          // Set to 0 for compressed formats
            mFramesPerPacket: 1024,      // AAC typically uses 1024 frames per packet
            mBytesPerFrame: 0,           // Compressed formats: 0
            mChannelsPerFrame: 1,        // Mono audio
            mBitsPerChannel: 0,          // Compressed formats: 0
            mReserved: 0
        )
        
        guard let aacFormat = AVAudioFormat(streamDescription: &aacFormatDesc) else {
            print("Error creating AAC input format.")
            return
        }
        
        // Create the PCM output format
        guard let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                            sampleRate: 8000, // Same sample rate
                                            channels: 1, interleaved: self.interleaved) else {
            print("Error creating PCM output format.")
            return
        }
        
        self.pcmFormat = pcmFormat
        
        // Create the converter
        guard let converter = AVAudioConverter(from: aacFormat, to: pcmFormat) else {
            print("Error creating AVAudioConverter.")
            return
        }
        
        self.decoderConverter = converter
        
    }
    
    private func decodeAACDataToPCM(aacData: Data) -> AVAudioPCMBuffer? {
                
        // Create an AudioStreamBasicDescription for AAC (input format)
        var aacFormatDesc = AudioStreamBasicDescription(
            mSampleRate: 8000,  // Example sample rate
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: AudioFormatFlags(MPEG4ObjectID.AAC_LC.rawValue),
            mBytesPerPacket: 0,          // Set to 0 for compressed formats
            mFramesPerPacket: 1024,      // AAC typically uses 1024 frames per packet
            mBytesPerFrame: 0,           // Compressed formats: 0
            mChannelsPerFrame: 1,        // Mono audio
            mBitsPerChannel: 0,          // Compressed formats: 0
            mReserved: 0
        )
        
        guard let aacFormat = AVAudioFormat(streamDescription: &aacFormatDesc) else {
            print("Error creating AAC input format.")
            return nil
        }
        
        // Create a buffer for the input AAC data (compressed)
        let inputBuffer = AVAudioCompressedBuffer(format: aacFormat,
                                                  packetCapacity: 8,
                                                  maximumPacketSize: aacData.count)
        
        inputBuffer.byteLength = UInt32(aacData.count)
        aacData.copyBytes(to: inputBuffer.data.assumingMemoryBound(to: UInt8.self), count: aacData.count)
        inputBuffer.packetCount = 8

        // Prepare an output buffer (PCM) for the decoded audio
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: self.pcmFormat!, frameCapacity: 1024) else {
            print("Error creating PCM output buffer.")
            return nil
        }

        // Perform the decoding
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        var error: NSError?
        let status = self.decoderConverter!.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if status == .error || error != nil {
            print("Decoding error: \(String(describing: error!.localizedDescription))")
            return nil
        }
        
        return outputBuffer
    }

    
}
