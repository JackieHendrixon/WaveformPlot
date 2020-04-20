//
//  WaveformPlotView.swift
//  Waveform
//
//  Created by Franek on 26/03/2020.
//  Copyright © 2020 Frankie. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation


class WaveformLayerGenerator {
    
    //MARK: Soundprocessing options
    
    var db:Bool = false
    
    //MARK: Apperance options
    
    var targetBars = 30
    
    var spacing:CGFloat = 10
    
    var plotColor:CGColor = UIColor.orange.cgColor
    
    func getLayer(audio asset: AVAsset, frame: CGRect,completion:  @escaping (CALayer) -> ()) {
        
        WaveformProcessor.AudioContext.load(from: asset) { audioContext in
            guard let audioContext = audioContext else {
                fatalError("Couldn't create the audioContext")
            }
            
            let samples = WaveformProcessor.render(audioContext: audioContext, targetSamples: self.targetBars, db: self.db)
            DispatchQueue.main.async {
                var samples = samples.map({CGFloat.init($0)})
                let scale: CGFloat
                if (self.db) {
                    scale = CGFloat(WaveformProcessor.noiseFloor)
                    samples = samples.map({$0+scale})
                } else {
                    scale = CGFloat(WaveformProcessor.sampleMax);
                }
                
                let plot = WaveformLayer(frame: frame,
                                         values: samples,
                                         scale: scale,
                                         spacing: self.spacing,
                                         plotColor: self.plotColor)
                completion(plot)
            }
        }
    }
    
    func getLayer(resourceName: String, ofType: String, frame: CGRect, completion: @escaping(CALayer) -> ()) {
        guard let path = Bundle.main.path(forResource: resourceName, ofType: ".mp3") else {
            fatalError("Couldn't find the path to resource")
        }
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: NSNumber(value: true as Bool)])
        getLayer(audio: asset, frame: frame, completion: completion)
    }
}



class WaveformLayer: CALayer {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    init(frame: CGRect, values: [CGFloat], scale: CGFloat, spacing: CGFloat, plotColor: CGColor) {
        super.init()
        self.frame = frame
        
        let barCount =  CGFloat(values.count)
        let barWidth = (frame.width) / barCount
        for (i, value) in values.enumerated() {
            var barFrame = bounds
            barFrame.size.width = barWidth
            barFrame.origin.x = barFrame.size.width * CGFloat(i)+spacing/2
            barFrame.size.width -= spacing
            
            barFrame.origin.y += bounds.height/2
            let bar = BarLayer(frame: barFrame, value: value, scale: scale, color: plotColor)
            bar.frame.origin.y -= bar.frame.height/2
            self.addSublayer(bar)
        }
    }
}


class BarLayer: CALayer {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    init(frame: CGRect, value: CGFloat, scale: CGFloat, color: CGColor) {
        super.init()
        self.frame = frame
        self.frame.size.height *= value/scale
        backgroundColor = color
        shadowColor = backgroundColor
        shadowRadius = 2
        shadowOffset = CGSize(width: 0, height: 0)
        shadowOpacity = 0.5
    }
}

