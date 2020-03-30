//
//  YPLibraryViewCell.swift
//  YPImgePicker
//
//  Created by Sacha Durand Saint Omer on 2015/11/14.
//  Copyright © 2015 Yummypets. All rights reserved.
//

import UIKit
import Stevia

class YPMultipleSelectionIndicator: UIView {
    
    let selectionOverlay = UIView()
    let imageView = UIImageView()
    let circle = UIView()
    let label = UILabel()
    var selectionColor = UIColor.black
    
    convenience init() {
        self.init(frame: .zero)
        
        sv(
            selectionOverlay,
            imageView
        )
        imageView.centerInContainer()
        selectionOverlay.fillContainer()
        selectionOverlay.backgroundColor = .white
        /*imageView.centerInContainer
        imageView.contentMode = .center*/
        
        /*circle.fillContainer()
        circle.size(size)
        label.fillContainer()
        
        circle.layer.cornerRadius = size / 2.0
        label.textAlignment = .center
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 12, weight: .regular)*/
        
        set(number: nil)
    }
    
    func set(number: Int?) {
        imageView.isHidden = (number == nil)
        selectionOverlay.isHidden = (number == nil)
        if let number = number {
            imageView.image = imageFromBundle("yp_\(number)")
            selectionOverlay.alpha = 0.75
        } else {
            imageView.image = nil
            selectionOverlay.alpha = 0.0
        }
        /*label.isHidden = (number == nil)
        if let number = number {
            circle.backgroundColor = selectionColor
            circle.layer.borderColor = UIColor.clear.cgColor
            circle.layer.borderWidth = 0
            label.text = "\(number)"
        } else {
            circle.backgroundColor = UIColor.white.withAlphaComponent(0.3)
            circle.layer.borderColor = UIColor.white.cgColor
            circle.layer.borderWidth = 1
            label.text = ""
        }*/
    }
}

class YPLibraryViewCell: UICollectionViewCell {
    
    var representedAssetIdentifier: String!
    let imageView = UIImageView()
    let durationLabel = UILabel()
    let selectionOverlay = UIView()
    let multipleSelectionIndicator = YPMultipleSelectionIndicator()
    
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        sv(
            imageView,
            durationLabel,
            selectionOverlay,
            multipleSelectionIndicator
        )

        imageView.fillContainer()
        selectionOverlay.fillContainer()
        multipleSelectionIndicator.fillContainer()
        layout(
            durationLabel-5-|,
            5
        )
        
        /*layout(
            3,
            multipleSelectionIndicator-3-|
        )*/
        multipleSelectionIndicator.fillContainer()
        
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        durationLabel.textColor = .white
        durationLabel.font = .systemFont(ofSize: 12)
        durationLabel.isHidden = true
        selectionOverlay.backgroundColor = .white
        selectionOverlay.alpha = 0
        backgroundColor = UIColor(r: 247, g: 247, b: 247)
        multipleSelectionIndicator.isHidden = true
    }

    override var isSelected: Bool {
        didSet {
            isHighlighted = isSelected
        }
    }
    
    override var isHighlighted: Bool {
        didSet {
        }
    }
}

class YPLibraryThumbCell: UICollectionViewCell {
    
    var representedAssetIdentifier: String!
    let imageView = UIImageView()
    let selectionOverlay = UIView()
    
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        sv(
            imageView,
            selectionOverlay
        )
        
        imageView.fillContainer()
        selectionOverlay.fillContainer()

        self.layer.cornerRadius = 8.0
        self.layer.borderColor = UIColor.white.cgColor
        self.layer.borderWidth = 0.5
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8.0
        self.layer.masksToBounds = true
        selectionOverlay.backgroundColor = .white
        selectionOverlay.alpha = 0
    }
    
    override var isSelected: Bool {
        didSet {
            isHighlighted = isSelected
        }
    }
    
    override var isHighlighted: Bool {
        didSet {
            selectionOverlay.alpha = 0.0
            if isHighlighted {
                selectionOverlay.alpha = 0.8
            }
        }
    }
}
