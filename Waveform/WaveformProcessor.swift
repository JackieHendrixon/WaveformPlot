//
//  Waveform.swift
//  Waveform
//
//  Created by Franek on 17/03/2020.
//  Copyright © 2020 Frankie. All rights reserved.
//

import Foundation
import Accelerate
import AVFoundation

class WaveformProcessor {

    /// Holds audio information used for building waveforms
    final class AudioContext {


        /// Total number of samples in loaded asset
        public let totalSamples: Int

        /// Loaded asset
        public let asset: AVAsset

        // Loaded assetTrack
        public let assetTrack: AVAssetTrack

        private init(totalSamples: Int, asset: AVAsset, assetTrack: AVAssetTrack) {

            self.totalSamples = totalSamples
            self.asset = asset
            self.assetTrack = assetTrack
        }

        public static func load(from asset: AVAsset, completionHandler: @escaping (_ audioContext: AudioContext?) -> ()) {
           

            guard let assetTrack = asset.tracks(withMediaType: AVMediaType.audio).first else {
                fatalError("Couldn't load AVAssetTrack")
            }

            asset.loadValuesAsynchronously(forKeys: ["duration"]) {
                var error: NSError?
                let status = asset.statusOfValue(forKey: "duration", error: &error)
                switch status {
                case .loaded:
                    guard
                        let formatDescriptions = assetTrack.formatDescriptions as? [CMAudioFormatDescription],
                        let audioFormatDesc = formatDescriptions.first,
                        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDesc)
                        else { break }

                    let totalSamples = Int((asbd.pointee.mSampleRate) * Float64(asset.duration.value) / Float64(asset.duration.timescale))
                    let audioContext = AudioContext(totalSamples: totalSamples, asset: asset, assetTrack: assetTrack)
                    completionHandler(audioContext)
                    return

                case .failed, .cancelled, .loading, .unknown:
                    print("Couldn't load asset: \(error?.localizedDescription ?? "Unknown error")")
                }

                completionHandler(nil)
            }
        }
    }

    static var noiseFloor: Float = -60
    static let sampleMax: Float = 32768

    static public func render(audioContext: AudioContext?, targetSamples: Int = 100, db:Bool) -> [Float]{
        guard let audioContext = audioContext else {
            fatalError("Couldn't create the audioContext")
        }

        let sampleRange: CountableRange<Int> = 0..<audioContext.totalSamples/3

        guard let reader = try? AVAssetReader(asset: audioContext.asset)
            else {
                fatalError("Couldn't initialize the AVAssetReader")
        }

        reader.timeRange = CMTimeRange(start: CMTime(value: Int64(sampleRange.lowerBound), timescale: audioContext.asset.duration.timescale),
                                       duration: CMTime(value: Int64(sampleRange.count), timescale: audioContext.asset.duration.timescale))

        let outputSettingsDict: [String : Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: audioContext.assetTrack,
                                                    outputSettings: outputSettingsDict)
        readerOutput.alwaysCopiesSampleData = false
        reader.add(readerOutput)

        var channelCount = 1
        let formatDescriptions = audioContext.assetTrack.formatDescriptions as! [CMAudioFormatDescription]
        for item in formatDescriptions {
            guard let fmtDesc = CMAudioFormatDescriptionGetStreamBasicDescription(item) else {
                fatalError("Couldn't get the format description")
            }
            channelCount = Int(fmtDesc.pointee.mChannelsPerFrame)
        }

        let samplesPerPixel = max(1, channelCount * sampleRange.count / targetSamples)
        let filter = [Float](repeating: 1.0 / Float(samplesPerPixel), count: samplesPerPixel)

        var outputSamples = [Float]()
        var sampleBuffer = Data()

        // 16-bit samples
        reader.startReading()
        defer { reader.cancelReading() }

        while reader.status == .reading {
            guard let readSampleBuffer = readerOutput.copyNextSampleBuffer(),
                let readBuffer = CMSampleBufferGetDataBuffer(readSampleBuffer) else {
                    break
            }
            // Append audio sample buffer into our current sample buffer
            var readBufferLength = 0
            var readBufferPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(readBuffer,
                                        atOffset: 0,
                                        lengthAtOffsetOut: &readBufferLength,
                                        totalLengthOut: nil,
                                        dataPointerOut: &readBufferPointer)
            sampleBuffer.append(UnsafeBufferPointer(start: readBufferPointer, count: readBufferLength))
            CMSampleBufferInvalidate(readSampleBuffer)

            let totalSamples = sampleBuffer.count / MemoryLayout<Int16>.size
            let downSampledLength = totalSamples / samplesPerPixel
            let samplesToProcess = downSampledLength * samplesPerPixel

            guard samplesToProcess > 0 else { continue }

            processSamples(fromData: &sampleBuffer,
                           outputSamples: &outputSamples,
                           samplesToProcess: samplesToProcess,
                           downSampledLength: downSampledLength,
                           samplesPerPixel: samplesPerPixel,
                           filter: filter, db:db)
            //print("Status: \(reader.status)")
        }

        // Process the remaining samples at the end which didn't fit into samplesPerPixel
        let samplesToProcess = sampleBuffer.count / MemoryLayout<Int16>.size
        if samplesToProcess > 0 {
            let downSampledLength = 1
            let samplesPerPixel = samplesToProcess
            let filter = [Float](repeating: 1.0 / Float(samplesPerPixel), count: samplesPerPixel)

            processSamples(fromData: &sampleBuffer,
                           outputSamples: &outputSamples,
                           samplesToProcess: samplesToProcess,
                           downSampledLength: downSampledLength,
                           samplesPerPixel: samplesPerPixel,
                           filter: filter, db:db)
            //print("Status: \(reader.status)")
        }

        // if (reader.status == AVAssetReaderStatusFailed || reader.status == AVAssetReaderStatusUnknown)
        guard reader.status == .completed else {
            fatalError("Couldn't read the audio file")
        }

        return outputSamples
    }

    private static func processSamples(fromData sampleBuffer: inout Data,
                        outputSamples: inout [Float],
                        samplesToProcess: Int,
                        downSampledLength: Int,
                        samplesPerPixel: Int,
                        filter: [Float], db:Bool) {
        sampleBuffer.withUnsafeBytes { (samples: UnsafePointer<Int16>) in
            var processingBuffer = [Float](repeating: 0.0, count: samplesToProcess)

            let sampleCount = vDSP_Length(samplesToProcess)

            //Convert 16bit int samples to floats
            vDSP_vflt16(samples, 1, &processingBuffer, 1, sampleCount)

            //Take the absolute values to get amplitude
            vDSP_vabs(processingBuffer, 1, &processingBuffer, 1, sampleCount)

            //get the corresponding dB, and clip the results
            if (db) {
                getdB(from: &processingBuffer)
            }
            
            //Downsample and average
            var downSampledData = [Float](repeating: 0.0, count: downSampledLength)
            vDSP_desamp(processingBuffer,
                        vDSP_Stride(samplesPerPixel),
                        filter, &downSampledData,
                        vDSP_Length(downSampledLength),
                        vDSP_Length(samplesPerPixel))

            //Remove processed samples
            sampleBuffer.removeFirst(samplesToProcess * MemoryLayout<Int16>.size)

            outputSamples += downSampledData
        }
    }

    private static func getdB(from normalizedSamples: inout [Float]) {
        // Convert samples to a log scale
        var zero: Float = 32768.0
        vDSP_vdbcon(normalizedSamples, 1, &zero, &normalizedSamples, 1, vDSP_Length(normalizedSamples.count), 1)

        //Clip to [noiseFloor, 0]
        var ceil: Float = 0.0
        var noiseFloorMutable = noiseFloor
        vDSP_vclip(normalizedSamples, 1, &noiseFloorMutable, &ceil, &normalizedSamples, 1, vDSP_Length(normalizedSamples.count))
        
        vDSP_vabs(normalizedSamples, 1, &normalizedSamples, 1, vDSP_Length(normalizedSamples.count))
    }

}
