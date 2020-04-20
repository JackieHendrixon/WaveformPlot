//
//  ViewController.swift
//  Waveform
//
//  Created by Franek on 17/03/2020.
//  Copyright © 2020 Frankie. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        // --- 1. Prepare everything ---
        
        // Make some space
        var firstFrame = self.view.frame
        firstFrame.size.height /= 2
        
        var secondFrame = firstFrame;
        secondFrame.origin.y += secondFrame.height
        
        // Load some assets
        guard let path = Bundle.main.path(forResource: "Track", ofType: ".mp3") else {
            fatalError("Couldn't find the path to resource")
        }
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: NSNumber(value: true as Bool)])
        
        
        // --- 2. Use ---
        
        
        let waveGen = WaveformLayerGenerator();
        
        waveGen.plotColor = UIColor.orange.cgColor
        waveGen.targetBars = 40
        waveGen.db = false
        
        // Create from asset
        
        waveGen.getLayer(audio: asset, frame: firstFrame) { (layer) in
            self.view.layer.addSublayer(layer)
            
        }
        
        // ..or from the resource file
        waveGen.getLayer(resourceName: "Track2", ofType: "mp3", frame: secondFrame){ (layer) in
            self.view.layer.addSublayer(layer)
            
        }

    }
    
}

