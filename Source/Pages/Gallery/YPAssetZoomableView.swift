//
//  YPAssetZoomableView.swift
//  YPImgePicker
//
//  Created by Sacha Durand Saint Omer on 2015/11/16.
//  Edited by Nik Kov || nik-kov.com on 2018/04
//  Copyright © 2015 Yummypets. All rights reserved.
//

import UIKit
import Photos

protocol YPAssetZoomableViewDelegate: class {
	func ypAssetZoomableViewDidLayoutSubviews(_ zoomableView: YPAssetZoomableView)
	func ypAssetZoomableViewScrollViewDidZoom()
	func ypAssetZoomableViewScrollViewDidEndZooming()
}

final class YPAssetZoomableView: UIScrollView {
	public weak var myDelegate: YPAssetZoomableViewDelegate?
	public var cropAreaDidChange = {}
	public var isVideoMode = false
	public var photoImageView = UIImageView()
	public var videoView = YPVideoView()
	public var squaredZoomScale: CGFloat = 1
	// @AlphaApps
	/// Zoom Scale in relation to the original media item's dimensions -- used instead of square zoom/scale to fit the original image
	public var originalZoomScale: CGFloat = 1
	private var originalAspectRatio: CGFloat = 1
	/// Used to set forcedAspectRatio to a uniform ratio (1:height)
	private var originalMediaDimensions: CGSize?
	/// Used to calculate correct zoomScale for multiple Selection
	static var firstItemZoomScale: CGFloat?
	/// Used to calculate correct zoomScale for multiple Selection
	static var firstItemSize: CGSize?
	/// Used to calculate correct zoomScale for multiple Selection
	static var firstItemFrameSize: CGSize?
	/// 1:height always (1:0.52, 1:1.25, etc..)
	static var forcedAspectRatio: CGFloat?
	static private var isSingleItem: Bool {
		return YPLibraryVC.selection.count <= 1
	}
	private let pickerEpsiolon: CGFloat = 0.005
	// !AlphaApps
	public var minWidth: CGFloat? = YPConfig.library.minWidthForItem
	
	fileprivate var currentAsset: PHAsset?
	
	// Image view of the asset for convenience. Can be video preview image view or photo image view.
	public var assetImageView: UIImageView {
		return isVideoMode ? videoView.previewImageView : photoImageView
	}
	
	/// Set zoom scale to fit the image to square or show the full image
	//
	/// - Parameters:
	///   - fit: If true - zoom to show squared. If false - show full.
	///   - animated: self-explanatory
	///   - shouldSetZoomScale: to prevent calling setZoomScale -- used in scenarios where we don't want to change the user's zoomScale
	public func fitImage(_ fit: Bool, animated isAnimated: Bool = false, shouldSetZoomScale: Bool = true) {
		if fit {
			minimumZoomScale = squaredZoomScale
			if shouldSetZoomScale {
				setZoomScale(squaredZoomScale, animated: isAnimated)
			}
		} else {
			minimumZoomScale = originalZoomScale
			if shouldSetZoomScale {
				setZoomScale(originalZoomScale, animated: isAnimated)
			}
		}
		
		if YPAssetZoomableView.isSingleItem {
			setForcedAspectRatio()
		}
	}
	
	/// Re-apply correct scrollview settings if image has already been adjusted in
	/// multiple selection mode so that user can see where they left off.
	public func applyStoredCropPosition(_ scp: YPLibrarySelection) {
		guard let zoomScale = scp.scrollViewZoomScale, let contentOffset = scp.scrollViewContentOffset else { return }
		// ZoomScale needs to be set first.
		setZoomScale(zoomScale, animated: false)
		setContentOffset(contentOffset, animated: false)
	}
	
	public func setVideo(_ video: PHAsset,
						 mediaManager: LibraryMediaManager,
						 storedCropPosition: YPLibrarySelection?,
						 completion: @escaping () -> Void) {
		mediaManager.imageManager?.fetchPreviewFor(video: video) { [weak self] preview in
			guard let strongSelf = self else { return }
			guard strongSelf.currentAsset != video else { completion() ; return }
			
			if strongSelf.videoView.isDescendant(of: strongSelf) == false {
				strongSelf.isVideoMode = true
				strongSelf.photoImageView.removeFromSuperview()
				strongSelf.addSubview(strongSelf.videoView)
			}
			
			strongSelf.videoView.setPreviewImage(preview)
			
			strongSelf.setAssetFrame(for: strongSelf.videoView, with: preview)
			
			completion()
			
			// Stored crop position in multiple selection
			if let scp173 = storedCropPosition {
				strongSelf.applyStoredCropPosition(scp173)
			}
		}
		mediaManager.imageManager?.fetchPlayerItem(for: video) { [weak self] playerItem in
			guard let strongSelf = self else { return }
			guard strongSelf.currentAsset != video else { completion() ; return }
			strongSelf.currentAsset = video
			
			strongSelf.videoView.loadVideo(playerItem)
			strongSelf.videoView.play()
		}
	}
	
	public func setImage(_ photo: PHAsset,
						 mediaManager: LibraryMediaManager,
						 storedCropPosition: YPLibrarySelection?,
						 completion: @escaping () -> Void) {
		guard currentAsset != photo else { DispatchQueue.main.async { completion() }; return }
		currentAsset = photo
		
		mediaManager.imageManager?.fetch(photo: photo) { [weak self] image, _ in
			guard let strongSelf = self else { return }
			
			if strongSelf.photoImageView.isDescendant(of: strongSelf) == false {
				strongSelf.isVideoMode = false
				strongSelf.videoView.removeFromSuperview()
				strongSelf.videoView.showPlayImage(show: false)
				strongSelf.videoView.deallocate()
				strongSelf.addSubview(strongSelf.photoImageView)
				
				strongSelf.photoImageView.contentMode = .scaleAspectFill
				strongSelf.photoImageView.clipsToBounds = true
			}
			
			strongSelf.photoImageView.image = image
			
			strongSelf.setAssetFrame(for: strongSelf.photoImageView, with: image)
			
			completion()
			
			// Stored crop position in multiple selection
			if let scp173 = storedCropPosition {
				strongSelf.applyStoredCropPosition(scp173)
			}
		}
	}
	
	fileprivate func setAssetFrame(`for` view: UIView, with image: UIImage) {
		// show assetFrame
		self.isHidden = false
		
		// Reseting the previous scale
		self.minimumZoomScale = 1
		self.zoomScale = 1
		
		// Calculating and setting the image view frame depending on screenWidth
		let screenWidth: CGFloat = UIScreen.main.bounds.width - 32
		let w = image.size.width
		let h = image.size.height
		originalMediaDimensions = CGSize(width: w, height: h)
		if YPAssetZoomableView.isSingleItem {
			YPAssetZoomableView.firstItemSize = CGSize(width: w, height: h)
		}
		
		let aspectRatioType = determineAspectRatioType(image.size)
		
		var aspectRatio: CGFloat = 1
		var zoomScale: CGFloat = 1
		
		// fix zoomableView cropping frame?
		if !YPAssetZoomableView.isSingleItem, let forcedAspectRatio = YPAssetZoomableView.forcedAspectRatio {
			if forcedAspectRatio > 1 + pickerEpsiolon {
				// force portrait
				YPLibraryView.shared?.assetWidthConstraint = YPLibraryView.shared?.assetWidthConstraint.setMultiplier(multiplier: 1 / forcedAspectRatio)
				YPLibraryView.shared?.assetHeightConstraint = YPLibraryView.shared?.assetHeightConstraint.setMultiplier(multiplier: 1)
			} else if forcedAspectRatio < 1 - pickerEpsiolon {
				// force landscape
				YPLibraryView.shared?.assetWidthConstraint = YPLibraryView.shared?.assetWidthConstraint.setMultiplier(multiplier: 1)
				YPLibraryView.shared?.assetHeightConstraint = YPLibraryView.shared?.assetHeightConstraint.setMultiplier(multiplier: forcedAspectRatio)
			} else {
				// force square
				YPLibraryView.shared?.assetWidthConstraint = YPLibraryView.shared?.assetWidthConstraint.setMultiplier(multiplier: 1)
				YPLibraryView.shared?.assetHeightConstraint = YPLibraryView.shared?.assetHeightConstraint.setMultiplier(multiplier: 1)
			}
		} else {
			YPLibraryView.shared?.assetWidthConstraint = YPLibraryView.shared?.assetWidthConstraint.setMultiplier(multiplier: 1)
			YPLibraryView.shared?.assetHeightConstraint = YPLibraryView.shared?.assetHeightConstraint.setMultiplier(multiplier: 1)
		}
		YPLibraryView.shared?.layoutIfNeeded()
		
		switch aspectRatioType {
		case .landscape:
			var landscapeMinAspectRatio = CGFloat(0.52) // `1:0.52` or `1.923:1`
			if !YPAssetZoomableView.isSingleItem, let forcedAspectRatio = YPAssetZoomableView.forcedAspectRatio {
				landscapeMinAspectRatio = forcedAspectRatio
			}
			aspectRatio = h / w
			view.frame.size.width = screenWidth
			view.frame.size.height = screenWidth * aspectRatio
			if YPAssetZoomableView.isSingleItem {
				YPAssetZoomableView.firstItemFrameSize = view.frame.size
			}
			// cap the cropped landscape image to the minimum aspect ratio
			if aspectRatio < landscapeMinAspectRatio {
				if !YPAssetZoomableView.isSingleItem, landscapeMinAspectRatio > 1 + pickerEpsiolon {
					if let firstItemSize = YPAssetZoomableView.firstItemSize, let firstItemZoomScale = YPAssetZoomableView.firstItemZoomScale, let firstItemFrameSize = YPAssetZoomableView.firstItemFrameSize {
						zoomScale = firstItemFrameSize.height / view.frame.size.height
					}
				} else {
					aspectRatio = landscapeMinAspectRatio
					let landscapeMinWidth = h * (1/aspectRatio)
					zoomScale = w / landscapeMinWidth
				}
			}
			break
		case .portrait:
			var portraitMinAspectRatio = CGFloat(0.8) // `1:1.25` or `0.8:1`
			if !YPAssetZoomableView.isSingleItem, let forcedAspectRatio = YPAssetZoomableView.forcedAspectRatio {
				portraitMinAspectRatio = 1 / forcedAspectRatio
			}
			aspectRatio = w / h
			view.frame.size.width = screenWidth * aspectRatio
			view.frame.size.height = screenWidth
			if YPAssetZoomableView.isSingleItem {
				YPAssetZoomableView.firstItemFrameSize = view.frame.size
			}
			
			// cap the cropped portrait image to the minimum aspect ratio
			if aspectRatio < portraitMinAspectRatio {
				if !YPAssetZoomableView.isSingleItem, portraitMinAspectRatio > 1 + pickerEpsiolon {
					// multiple selection, first item is landscape
					if let _ = YPAssetZoomableView.firstItemSize, let _ = YPAssetZoomableView.firstItemZoomScale, let firstItemFrameSize = YPAssetZoomableView.firstItemFrameSize {
						zoomScale = firstItemFrameSize.width / view.frame.size.width
					}
				} else {
					aspectRatio = portraitMinAspectRatio
					let portraitMinHeight = w * (1/aspectRatio)
					zoomScale = h / portraitMinHeight
				}
			}
			break
		case .square:
			view.frame.size.width = screenWidth
			view.frame.size.height = screenWidth
			break
		}
		
		// Centering image view
		view.center = center
		centerAssetView()
		
		// Setting new scale
		squaredZoomScale = calculateSquaredZoomScale()
		if YPAssetZoomableView.isSingleItem {
			if aspectRatioType == .square {
				YPAssetViewContainer.shouldCropToSquare = true
				zoomScale = squaredZoomScale
			} else {
				YPAssetViewContainer.shouldCropToSquare = false
			}
		}
		self.minimumZoomScale = zoomScale
		self.zoomScale = zoomScale
		originalZoomScale = zoomScale
		setForcedAspectRatio(aspectRatio: aspectRatio)
	}
	
	/// Used when entering picker and there's no selection to show in assetFrame.
	func collapseAssetFrame() {
		// hide AssetFrame
		self.isHidden = true
		
		// empty asset viewer
		self.photoImageView.frame.size.width = 0
		self.photoImageView.frame.size.height = 0
		self.videoView.frame.size.width = 0
		self.videoView.frame.size.height = 0
	}
	
	/// Calculate zoom scale which will fit the image to square
	fileprivate func calculateSquaredZoomScale() -> CGFloat {
		guard let image = assetImageView.image else {
			return 1.0
		}
		
		var squareZoomScale: CGFloat = 1.0
		let w = image.size.width
		let h = image.size.height
		
		if w > h { // Landscape
			squareZoomScale = (w / h)
		} else if h > w { // Portrait
			squareZoomScale = (h / w)
		}
		
		return squareZoomScale
	}
	
	// Centring the image frame
	public func centerAssetView() {
		let assetView = isVideoMode ? videoView : photoImageView
		let scrollViewBoundsSize = self.bounds.size
		var assetFrame = assetView.frame
		let assetSize = assetView.frame.size
		
		assetFrame.origin.x = (assetSize.width < scrollViewBoundsSize.width) ?
			(scrollViewBoundsSize.width - assetSize.width) / 2.0 : 0
		assetFrame.origin.y = (assetSize.height < scrollViewBoundsSize.height) ?
			(scrollViewBoundsSize.height - assetSize.height) / 2.0 : 0.0
		
		assetView.frame = assetFrame
	}
	
	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)!
		frame.size      = CGSize.zero
		clipsToBounds   = true
		photoImageView.frame = CGRect(origin: CGPoint.zero, size: CGSize.zero)
		videoView.frame = CGRect(origin: CGPoint.zero, size: CGSize.zero)
		maximumZoomScale = 10.0
		minimumZoomScale = 1
		showsHorizontalScrollIndicator = false
		showsVerticalScrollIndicator   = false
		delegate = self
		alwaysBounceHorizontal = true
		alwaysBounceVertical = true
		isScrollEnabled = true
	}
	
	override func layoutSubviews() {
		super.layoutSubviews()
		myDelegate?.ypAssetZoomableViewDidLayoutSubviews(self)
	}
}

// MARK: UIScrollViewDelegate Protocol
extension YPAssetZoomableView: UIScrollViewDelegate {
	func viewForZooming(in scrollView: UIScrollView) -> UIView? {
		return isVideoMode ? videoView : photoImageView
	}
	
	func scrollViewDidZoom(_ scrollView: UIScrollView) {
		myDelegate?.ypAssetZoomableViewScrollViewDidZoom()
		centerAssetView()
	}
	
	func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
		func handleSingleItemCase(zoomScaleType: ZoomScaleType) {
			if !YPAssetViewContainer.shouldCropToSquare { // expanded mode
				switch zoomScaleType {
				case .zoomOut:
					// surpassed min expanded/original zoomScale?
					self.fitImage(false, animated: true)
				case .zoomIn:
					// zoomed in -> ##transition## to square mode
					YPAssetViewContainer.shouldCropToSquare = true
					// `shouldSetZoomScale` can be set to false here, in this case the user can apply ratio between original image ratio and landscape_min/portrait_max ratio
					// setting `shouldSetZoomScale` to true prevents changing ratio when not square
					self.fitImage(true, animated: true, shouldSetZoomScale: true)
					break
				default:
					break
				}
			} else { // square mode
				switch zoomScaleType {
				case .zoomOut:
					// surpassed min square zoomScale?
					// zoomed out -> ##transition## to expanded mode -- this needs to be in `scrollViewWillBeginZooming` as `scale` parameter here will have a value assigned when dragging & zooming ends and not when the user raises their finger (willEndDragging)
					break
				case .zoomIn:
					// do nothing, user wants to zoom in while in square mode
					break
				default:
					break
				}
			}
		}
		func handleMultipleItemsCase(zoomScaleType: ZoomScaleType) {
			// apply forcedAspectRatio
			switch zoomScaleType {
			case .zoomOut:
				/*
				if !YPAssetViewContainer.shouldCropToSquare {
				self.fitImage(false, animated: true)
				} else {
				self.fitImage(true, animated: true)
				}
				*/
				break
			case .zoomIn:
				// prevents changing ratio when not square
				if !YPAssetViewContainer.shouldCropToSquare {
					//self.fitImage(false, animated: true)
				}
			default:
				break
			}
		}
		
		guard let view = view, view == photoImageView || view == videoView else { return }
		
		let zoomScaleType = determineZoomScaleType(scale)
		
		if YPAssetZoomableView.isSingleItem {
			handleSingleItemCase(zoomScaleType: zoomScaleType)
		} else {
			handleMultipleItemsCase(zoomScaleType: zoomScaleType)
		}
		
		myDelegate?.ypAssetZoomableViewScrollViewDidEndZooming()
		cropAreaDidChange()
	}
	
	func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
		if YPAssetViewContainer.shouldCropToSquare
			, YPAssetZoomableView.isSingleItem
			, determineZoomScaleType(zoomScale) == .zoomOut
		{
			// stop where the user is ending dragging -- bugfix when setting zoomScale afterwards
			targetContentOffset.pointee = contentOffset
			
			// zoomed out -> ##transition## to expanded mode
			YPAssetViewContainer.shouldCropToSquare = false
			self.fitImage(false, animated: true)
		}
	}
	
	func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
		cropAreaDidChange()
	}
	
	func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
		cropAreaDidChange()
	}
}

extension YPAssetZoomableView {
	fileprivate enum ZoomScaleType {
		case zoomIn, zoomOut, unknown
	}
	
	fileprivate enum AspectRatioType {
		case landscape, portrait, square
	}
	
	fileprivate func determineZoomScaleType(_ scale: CGFloat) -> ZoomScaleType {
		if !YPAssetViewContainer.shouldCropToSquare { // expanded mode
			// surpassed min expanded/original zoomScale?
			if scale <= minimumZoomScale {
				return ZoomScaleType.zoomOut
			} else if scale > minimumZoomScale {
				// zoomed in -> ##transition## to square mode
				return ZoomScaleType.zoomIn
			}
		} else { // square mode
			// surpassed min square zoomScale?
			if scale < squaredZoomScale {
				// zoomed out -> ##transition## to expanded mode -- this needs to be in `scrollViewWillBeginZooming` as `scale` parameter here will have a value assigned when dragging & zooming ends and not when the user raises their finger (willEndDragging)
				return ZoomScaleType.zoomOut
			} else {
				// do nothing, user wants to zoom in while in square mode
				return ZoomScaleType.zoomIn
			}
		}
		
		return ZoomScaleType.unknown
	}
	
	fileprivate func determineAspectRatioType(_ currentImageSize: CGSize) -> AspectRatioType {
		let w = currentImageSize.width
		let h = currentImageSize.height
		
		if w - h > pickerEpsiolon {
			// w > h
			return AspectRatioType.landscape
		} else if h - w > pickerEpsiolon {
			// h > w
			return AspectRatioType.portrait
		} else {
			// w == h
			return AspectRatioType.square
		}
	}
	
	func setForcedAspectRatio(aspectRatio: CGFloat? = nil) {
		guard YPAssetZoomableView.isSingleItem else { return }
		
		if let aspectRatio = aspectRatio {
			originalAspectRatio = aspectRatio
		}
		
		if YPAssetViewContainer.shouldCropToSquare {
			YPAssetZoomableView.forcedAspectRatio = CGFloat(1)
		} else {
			if let originalMediaDimensions = originalMediaDimensions {
				if originalMediaDimensions.height > originalMediaDimensions.width + pickerEpsiolon {
					// portrait
					YPAssetZoomableView.forcedAspectRatio = 1 / originalAspectRatio
				} else {
					// landscape
					YPAssetZoomableView.forcedAspectRatio = originalAspectRatio
				}
			}
		}
		
		YPAssetZoomableView.firstItemZoomScale = minimumZoomScale
	}
}
