//
//  YPLibraryVC+CollectionView.swift
//  YPImagePicker
//
//  Created by Sacha DSO on 26/01/2018.
//  Copyright © 2018 Yummypets. All rights reserved.
//

import UIKit
import Photos

extension YPLibraryVC {
    var isLimitExceeded: Bool { return YPLibraryVC.selection.count >= YPConfig.library.maxNumberOfItems }
	static var canDeselectItem: Bool { return YPLibraryVC.selection.count > 1 }
    
    func setupCollectionView() {
        v.collectionView.dataSource = self
        v.collectionView.delegate = self
        v.collectionView.register(YPLibraryViewCell.self, forCellWithReuseIdentifier: "YPLibraryViewCell")
        v.thumbCollectionView.dataSource = self
        v.thumbCollectionView.delegate = self
        v.thumbCollectionView.register(YPLibraryThumbCell.self, forCellWithReuseIdentifier: "YPLibraryThumbCell")
        // Long press on cell to enable multiple selection
        let longPressGR = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(longPressGR:)))
        longPressGR.minimumPressDuration = 0.5
        v.collectionView.addGestureRecognizer(longPressGR)
    }
	
	// TODO? remove this or keep it but account for our changes
    /// When tapping on the cell with long press, clear all previously selected cells.
    @objc func handleLongPress(longPressGR: UILongPressGestureRecognizer) {
        if multipleSelectionEnabled || isProcessing || YPConfig.library.maxNumberOfItems <= 1 {
            return
        }
		
		assertionFailure("Unintended code path")
		return
		
        if longPressGR.state == .began {
            let point = longPressGR.location(in: v.collectionView)
            guard let indexPath = v.collectionView.indexPathForItem(at: point) else {
                return
            }
            startMultipleSelection(at: indexPath)
        }
    }
    
    func startMultipleSelection(at indexPath: IndexPath) {
		assertionFailure("Unintended code path")
		return
        currentlySelectedIndex = indexPath.row
        multipleSelectionButtonTapped()
        
        // Update preview.
        changeAsset(mediaManager.fetchResult[indexPath.row])
        
        // Bring preview down and keep selected cell visible.
        panGestureHelper.resetToOriginalState()
        if !panGestureHelper.isImageShown {
            v.collectionView.scrollToItem(at: indexPath, at: .top, animated: true)
        }
        v.refreshImageCurtainAlpha()
    }
    
    // MARK: - Library collection view cell managing
    /// Delete from thumb
    @objc func deleteFromThumb() {
		deselect(indexPath: IndexPath(row: currentlySelectedThumb, section: 0), fromThumb: true)
		
		return
		/*
        if (currentlySelectedThumb >= 0) && (currentlySelectedThumb < YPLibraryVC.selection.count) {
            YPLibraryVC.selection.remove(at: currentlySelectedThumb)
            v.collectionView.reloadData()
            if YPLibraryVC.selection.count > 0 {
                currentlySelectedThumb = 0
                v.assetViewContainer.deleteButton.isHidden = false
                v.thumbCollectionView.reloadData()
                self.selectItemFromThumb(index: 0)
            } else {
                currentlySelectedThumb = -1
                v.assetViewContainer.deleteButton.isHidden = true
                v.thumbCollectionView.reloadData()
                selectItemFromGallery(index: 0)
            }
            checkLimit()
        }
		*/
    }
    
    /// Select item from thumb
    func selectItemFromThumb(index: Int) {
		// indices
		currentlySelectedThumb = index
		
		// get the asset
		//let assetIndex = YPLibraryVC.selection[index].index
		var asset: PHAsset? // = mediaManager.fetchResult?[assetIndex]
		let assetIdentifier = YPLibraryVC.selection[index].assetIdentifier
		let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
		if fetchResult.count > 0 {
			asset = fetchResult[0]
		}
		
		// change the aset
		if let asset = asset {
			changeAsset(asset, fromThumb: true)
		}
		
		// reset and reload
		panGestureHelper.resetToOriginalState()
		if !panGestureHelper.isImageShown {
			v.collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: .top, animated: true)
		}
		v.refreshImageCurtainAlpha()
		v.thumbCollectionView.reloadData()
		
		self.v.layoutIfNeeded()
    }
    
    /// Select item from thumb
    func selectItemFromGallery(index: Int) {
        let asset = mediaManager.fetchResult[index]
        changeAsset(asset)
        panGestureHelper.resetToOriginalState()
        v.refreshImageCurtainAlpha()
    }
    
    /// Removes cell from selection
	func deselect(indexPath: IndexPath, fromThumb: Bool = false) {
		guard YPLibraryVC.canDeselectItem else { return }
		
        //guard let positionIndex = YPLibraryVC.selection.index(where: { $0.assetIdentifier == mediaManager.fetchResult[indexPath.row].localIdentifier }) else { return }
		let deselectionMediaLibraryIndex = YPLibraryVC.selection[currentlySelectedThumb].index
		YPLibraryVC.selection.remove(at: currentlySelectedThumb)
		
		// select the last selected item in the selection
		currentlySelectedThumb = YPLibraryVC.selection.count - 1
		currentlySelectedIndex = YPLibraryVC.selection.last?.index ?? 0
		
		/*
		let cellIsInTheSelectionPool = isInSelectionPool(indexPath: indexPath)
		let cellIsCurrentlySelected = previouslySelectedIndexPath.row == currentlySelectedIndex
		if cellIsInTheSelectionPool {
			if cellIsCurrentlySelected {
				deselect(indexPath: indexPath)
		}
		*/
		
		// Replace the current selected image with the previously selected one
		/*
		if let previouslySelectedIndexPath = selectedIndexPaths.last {
			v.collectionView.selectItem(at: previouslySelectedIndexPath, animated: false, scrollPosition: [])
			v.thumbCollectionView.selectItem(at: previouslySelectedIndexPath, animated: false, scrollPosition: [])
			currentlySelectedIndex = previouslySelectedIndexPath.row
			currentlySelectedThumb = previouslySelectedIndexPath.row
			changeAsset(mediaManager.fetchResult[previouslySelectedIndexPath.row])
		}
		*/
		
		// change the asset to the last selected item
		selectItemFromThumb(index: currentlySelectedThumb)
		
		// Refresh the numbers
		refreshMediaLibraryNumbers(with: deselectionMediaLibraryIndex)
		
		v.thumbCollectionView.reloadData()
		self.v.assetViewContainer.deleteButton.isHidden = !YPLibraryVC.canDeselectItem
		
		checkLimit()
    }
    
    /// Adds cell to selection
    func addToSelection(indexPath: IndexPath) {
        let asset = mediaManager.fetchResult[indexPath.item]
		
        YPLibraryVC.selection.append(
            YPLibrarySelection(
                index: indexPath.row,
                assetIdentifier: asset.localIdentifier,
				albumIdentifier: YPAlbumVC.selectedAlbum?.collection?.localIdentifier
            )
        )
		
		self.v.assetViewContainer.deleteButton.isHidden = !YPLibraryVC.canDeselectItem
		
        checkLimit()
    }
    
    func isInSelectionPool(indexPath: IndexPath) -> Bool {
        return YPLibraryVC.selection.contains(where: { $0.assetIdentifier == mediaManager.fetchResult[indexPath.row].localIdentifier })
    }
    
    /// Checks if there can be selected more items. If no - present warning.
    func checkLimit() {
        v.maxNumberWarningView.isHidden = !isLimitExceeded || multipleSelectionEnabled == false
    }
}

extension YPLibraryVC: UICollectionViewDataSource {
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == v.thumbCollectionView {
            return YPLibraryVC.selection.count
        }
        return mediaManager.fetchResult.count
    }
}

extension YPLibraryVC: UICollectionViewDelegate {
    
    public func collectionView(_ collectionView: UICollectionView,
                               cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		// MARK: thumb collectionView cellForItemAt
        if collectionView == v.thumbCollectionView {
			var fetchedAsset: PHAsset?
            let assetIdentifier = YPLibraryVC.selection[indexPath.item].assetIdentifier
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
            if fetchResult.count > 0 {
                fetchedAsset = fetchResult[0]
            }
			guard let asset: PHAsset = fetchedAsset ?? mediaManager.fetchResult?[indexPath.item] else { assertionFailure("asset not found") ; return UICollectionViewCell() }
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "YPLibraryThumbCell",
                                                                for: indexPath) as? YPLibraryThumbCell else {
				fatalError("unexpected cell in collection view")
            }
            cell.representedAssetIdentifier = asset.localIdentifier
            mediaManager.imageManager?.requestImage(for: asset,
                                                    targetSize: v.cellSize(),
                                                    contentMode: .aspectFill,
                                                    options: nil) { image, _ in
                                                        // The cell may have been recycled when the time this gets called
                                                        // set image only if it's still showing the same asset.
                                                        if cell.representedAssetIdentifier == asset.localIdentifier && image != nil {
                                                            cell.imageView.image = image
                                                        }
            }
            cell.isSelected = currentlySelectedThumb == indexPath.row
            // Prevent weird animation where thumbnail fills cell on first scrolls.
            UIView.performWithoutAnimation {
                cell.layoutIfNeeded()
            }
            return cell
        }
		
		// MARK: normal collectionView cellForItemAt
		
        // photo collection
        let asset = mediaManager.fetchResult[indexPath.item]
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "YPLibraryViewCell",
                                                            for: indexPath) as? YPLibraryViewCell else {
                                                                fatalError("unexpected cell in collection view")
        }
        cell.representedAssetIdentifier = asset.localIdentifier
        cell.multipleSelectionIndicator.selectionColor = YPConfig.colors.multipleItemsSelectedCircleColor
                                                            ?? YPConfig.colors.tintColor
        mediaManager.imageManager?.requestImage(for: asset,
                                   targetSize: v.cellSize(),
                                   contentMode: .aspectFill,
                                   options: nil) { image, _ in
                                    // The cell may have been recycled when the time this gets called
                                    // set image only if it's still showing the same asset.
                                    if cell.representedAssetIdentifier == asset.localIdentifier && image != nil {
                                        cell.imageView.image = image
                                    }
        }
        
        let isVideo = (asset.mediaType == .video)
        cell.durationLabel.isHidden = !isVideo
        cell.durationLabel.text = isVideo ? YPHelper.formattedStrigFrom(asset.duration) : ""
        cell.multipleSelectionIndicator.isHidden = !multipleSelectionEnabled
        cell.isSelected = currentlySelectedIndex == indexPath.row
        
        // Set correct selection number
        if let index = YPLibraryVC.selection.index(where: { $0.assetIdentifier == asset.localIdentifier }) {
            cell.multipleSelectionIndicator.set(number: index + 1) // start at 1, not 0
        } else {
            cell.multipleSelectionIndicator.set(number: nil)
        }

        // Prevent weird animation where thumbnail fills cell on first scrolls.
        UIView.performWithoutAnimation {
            cell.layoutIfNeeded()
        }
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		// MARK: initial selection
		if !YPLibraryVC.finishedInitialSelection {
			YPLibraryVC.finishedInitialSelection = true
			handleInitialSelection(indexPath: indexPath)
			return
		}
		
		// MARK: thumb collectionView selection
        if collectionView == v.thumbCollectionView {
			// prevent seelcting the same thumbnail twice
			if currentlySelectedThumb != indexPath.item {
				selectItemFromThumb(index: indexPath.item)
			}
			return
        }
		
		// MARK: normal selection -- first tap on an item selects it
		if !YPLibraryVC.canDeselectItem, currentlySelectedIndex == indexPath.item {
			// do nothing, can't deselect the last selected item
			return
		}
		
        // photo collection
        let previouslySelectedIndexPath = IndexPath(row: currentlySelectedIndex, section: 0)
        currentlySelectedIndex = indexPath.row

        if multipleSelectionEnabled {
            
            let cellIsInTheSelectionPool = isInSelectionPool(indexPath: indexPath)
            let cellIsCurrentlySelected = previouslySelectedIndexPath.row == currentlySelectedIndex

            if cellIsInTheSelectionPool {
                if cellIsCurrentlySelected {
                    deselect(indexPath: indexPath)
					return
                }
            } else if isLimitExceeded == false {
                addToSelection(indexPath: indexPath)
            }
        } else {
			/*
            let previouslySelectedIndices = YPLibraryVC.selection
            YPLibraryVC.selection.removeAll()
            addToSelection(indexPath: indexPath)
            if let selectedRow = previouslySelectedIndices.first?.index {
                let previouslySelectedIndexPath = IndexPath(row: selectedRow, section: 0)
                collectionView.reloadItems(at: [previouslySelectedIndexPath])
            }
			*/
			assertionFailure("Unintended code path")
        }

		// update thumbs collectionView
		if let index = YPLibraryVC.selection.index(where: { $0.assetIdentifier == mediaManager.fetchResult[indexPath.row].localIdentifier }) {
			currentlySelectedThumb = index
			v.thumbCollectionView.reloadData()
		}
		
		changeAsset(mediaManager.fetchResult[indexPath.row])
		panGestureHelper.resetToOriginalState()
		
		// Only scroll cell to top if preview is hidden.
		if !panGestureHelper.isImageShown {
			collectionView.scrollToItem(at: indexPath, at: .top, animated: true)
		}
		v.refreshImageCurtainAlpha()
		
        collectionView.reloadItems(at: [indexPath])
		// prevent crash when reloading previously selected index path that is in another album e.g. select item 10 from albumA then go to albumB that has only 3 items, selecting an item from albumB will cause a crash when reloading collectionItem of row 10 which does not exist
		if previouslySelectedIndexPath.row < mediaManager.fetchResult.count {
			collectionView.reloadItems(at: [previouslySelectedIndexPath])
		}
    }
    
    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return isProcessing == false
    }
    
    public func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
        return isProcessing == false
    }
}

extension YPLibraryVC: UICollectionViewDelegateFlowLayout {
    public func collectionView(_ collectionView: UICollectionView,
                               layout collectionViewLayout: UICollectionViewLayout,
                               sizeForItemAt indexPath: IndexPath) -> CGSize {
        if collectionView == v.thumbCollectionView {
            return CGSize(width: 40, height: 40)
        }
        let margins = YPConfig.library.spacingBetweenItems * CGFloat(YPConfig.library.numberOfItemsInRow + 1)
        let screen = UIScreen.main.bounds.width
        let width:CGFloat = CGFloat(screen - margins) / CGFloat(YPConfig.library.numberOfItemsInRow)
        
        return CGSize(width: width, height: width)
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        if collectionView == v.thumbCollectionView {
            return 16.0
        }
        return YPConfig.library.spacingBetweenItems
    }
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        if collectionView == v.thumbCollectionView {
                  return UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        }
        return UIEdgeInsets(top: 0, left: 1, bottom: 0, right: 1)
    }
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        if collectionView == v.thumbCollectionView {
            return 16.0
        }
        return YPConfig.library.spacingBetweenItems
    }
}

extension YPLibraryVC {
	func handleInitialSelection(indexPath: IndexPath) {
		showAssetViewContainer(show: true)
		
		// indices
		currentlySelectedIndex = indexPath.row
		addToSelection(indexPath: indexPath)
		currentlySelectedThumb = 0
		if let index = YPLibraryVC.selection.index(where: { $0.assetIdentifier == mediaManager.fetchResult[indexPath.row].localIdentifier }) {
			currentlySelectedThumb = index
		}
		
		changeAsset(mediaManager.fetchResult[indexPath.row])
		
		// reloadData
		v.collectionView.reloadData()
		v.thumbCollectionView.reloadData()
	}
	
	func refreshMediaLibraryNumbers(with previousIndex: Int) {
		var selectedIndexPaths = [IndexPath]()
		selectedIndexPaths.append(IndexPath(row: previousIndex, section: 0))
		mediaManager.fetchResult.enumerateObjects { [unowned self] (asset, index, _) in
			if YPLibraryVC.selection.contains(where: { $0.assetIdentifier == asset.localIdentifier }) {
				selectedIndexPaths.append(IndexPath(row: index, section: 0))
			}
		}
		v.collectionView.reloadItems(at: selectedIndexPaths)
	}
}
