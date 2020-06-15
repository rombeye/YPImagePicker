//
//  YPLibraryVC.swift
//  YPImagePicker
//
//  Created by Sacha Durand Saint Omer on 27/10/16.
//  Copyright © 2016 Yummypets. All rights reserved.
//

import UIKit
import Photos

public class YPImagePickerState {
	
	private init() {
	}
	
	public static func reset() {
		YPLibraryVC.selection = []
		YPLibraryVC.shouldExpanded = false
		YPLibraryVC.aspectRatio = CGFloat(1.0)
		YPLibraryVC.finishedInitialSelection = false
		
		YPAssetViewContainer.shouldCropToSquare = false
		
		YPAlbumVC.selectedAlbum = nil
		
		YPAssetZoomableView.forcedAspectRatio = nil
		YPAssetZoomableView.firstItemSize = nil
	}
}

public class YPLibraryVC: UIViewController, YPPermissionCheckable {

    internal weak var delegate: YPLibraryViewDelegate?
    internal var v: YPLibraryView!
    internal var isProcessing = false // true if video or image is in processing state
    internal var multipleSelectionEnabled = true
    internal var initialized = false
    public static var selection = [YPLibrarySelection]()
    public static var shouldExpanded = false
    public static var aspectRatio = CGFloat(1.0)
	public static var finishedInitialSelection = false
    internal var currentlySelectedIndex: Int = 0
    internal var currentlySelectedThumb: Int = -1
    internal let mediaManager = LibraryMediaManager()
    internal var latestImageTapped = ""
    internal let panGestureHelper = PanGestureHelper()
	
    // MARK: - Init

    public required init() {
        super.init(nibName: nil, bundle: nil)
        title = YPConfig.wordings.libraryTitle
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAlbum(_ album: YPAlbum) {
        title = album.title
        mediaManager.collection = album.collection
		// TODO set proper indices (chiefly currentlySelectedIndex has to be updated, currentlySelectedThumb is already correct)
        //currentlySelectedIndex = 0
        //currentlySelectedThumb = -1
    }

    func initialize() {
        mediaManager.initialize()
        mediaManager.v = v

        if mediaManager.fetchResult != nil {
            return
        }

        setupCollectionView()
        registerForLibraryChanges()
        panGestureHelper.registerForPanGesture(on: v)
        registerForTapOnPreview()
		if let album =  YPAlbumVC.selectedAlbum {
			// selected album
			setAlbum(album)
			title = album.title
			// TODO act upon shared instance of YPPickerVC
			//setTitleViewWithTitle(aTitle: album.title)
		}
		refreshMediaRequest()

        v.assetViewContainer.multipleSelectionButton.isHidden = true//!(YPConfig.library.maxNumberOfItems > 1)
        v.maxNumberWarningLabel.text = String(format: YPConfig.wordings.warningMaxItemsLimit, YPConfig.library.maxNumberOfItems)
        //refreshExpandState(changeState: false)
		
		if YPLibraryVC.selection.count <= 0 {
			showAssetViewContainer(show: false)
		} else {
			showAssetViewContainer(show: true)
		}
    }

    /// Current image type
    func isCurrentImagePortrait() -> Bool {
        if let image = self.v.assetZoomableView.photoImageView.image {
            let ratio = image.size.width / image.size.height
            // lanscape
            if ratio > 1 {
                return false
            }
        }
        return true
    }

    /// Get aspect ratio depending on collapse/expand option and image size
    func getAspectRatio(isExpanded: Bool) -> CGFloat {
        if let image = self.v.assetZoomableView.photoImageView.image {
            let ratio = image.size.width / image.size.height
            // portrait
            if ratio <= 1 {
                return isExpanded ? 0.8 : 1.0 //1:1.25
            } else {// landscape
                return isExpanded ? 1.0 : 1.93 //1:0.52
            }
        }
        // square
        return 1.0 // 1:1
    }

    // MARK: - View Lifecycle

    public override func loadView() {
        v = YPLibraryView.xibView()
        view = v
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        // When crop area changes in multiple selection mode,
        // we need to update the scrollView values in order to restore
        // them when user selects a previously selected item.
        v.assetZoomableView.cropAreaDidChange = { [weak self] in
            guard let strongSelf = self else {
                return
            }
			
			strongSelf.v.assetViewContainer.updateSquareCropButtonUI()
			
            strongSelf.updateCropInfo()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        v.assetViewContainer.squareCropButton
            .addTarget(self,
                       action: #selector(squareCropButtonTapped),
                       for: .touchUpInside)
        v.assetViewContainer.multipleSelectionButton
            .addTarget(self,
                       action: #selector(multipleSelectionButtonTapped),
                       for: .touchUpInside)
        v.assetViewContainer.deleteButton
            .addTarget(self,
                       action: #selector(deleteFromThumb),
                       for: .touchUpInside)
        // Forces assetZoomableView to have a contentSize.
        // otherwise 0 in first selection triggering the bug : "invalid image size 0x0"
        // Also fits the first element to the square if the onlySquareFromLibrary = true
        if !YPConfig.library.onlySquare && v.assetZoomableView.contentSize == CGSize(width: 0, height: 0) {
            v.assetZoomableView.setZoomScale(1, animated: false)
        }

        // Activate multiple selection when using `minNumberOfItems`
        if YPConfig.library.minNumberOfItems > 1 {
            multipleSelectionButtonTapped()
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        pausePlayer()
        NotificationCenter.default.removeObserver(self)
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // MARK: - Crop control

    @objc
    func squareCropButtonTapped() {
        doAfterPermissionCheck { [weak self] in
            self?.v.assetViewContainer.squareCropButtonTapped()
            //self?.refreshExpandState()
        }
    }

    // MARK: - Multiple Selection

    @objc
    func multipleSelectionButtonTapped() {
		assertionFailure("Unintended code path")
		return
        if !multipleSelectionEnabled {
            YPLibraryVC.selection.removeAll()
        }

        // Prevent desactivating multiple selection when using `minNumberOfItems`
        if YPConfig.library.minNumberOfItems > 1 && multipleSelectionEnabled {
            return
        }

        multipleSelectionEnabled = !multipleSelectionEnabled

        if multipleSelectionEnabled {
            if YPLibraryVC.selection.isEmpty {
                let asset = mediaManager.fetchResult[currentlySelectedIndex]
                YPLibraryVC.selection = [
                    YPLibrarySelection(index: currentlySelectedIndex,
                                       cropRect: v.currentCropRect(),
                                       scrollViewContentOffset: v.assetZoomableView!.contentOffset,
                                       scrollViewZoomScale: v.assetZoomableView!.zoomScale,
                                       assetIdentifier: asset.localIdentifier,
									   albumIdentifier: YPAlbumVC.selectedAlbum?.collection?.localIdentifier)
                ]
            }
        } else {
            YPLibraryVC.selection.removeAll()
            addToSelection(indexPath: IndexPath(row: currentlySelectedIndex, section: 0))
        }

        v.assetViewContainer.setMultipleSelectionMode(on: multipleSelectionEnabled)
        v.collectionView.reloadData()
        v.thumbCollectionView.reloadData()
        checkLimit()
        delegate?.libraryViewDidToggleMultipleSelection(enabled: multipleSelectionEnabled)
    }

    // MARK: - Tap Preview

    func registerForTapOnPreview() {
        let tapImageGesture = UITapGestureRecognizer(target: self, action: #selector(tappedImage))
        v.assetViewContainer.addGestureRecognizer(tapImageGesture)
    }

    @objc
    func tappedImage() {
        if !panGestureHelper.isImageShown {
            panGestureHelper.resetToOriginalState()
            // no dragup? needed? dragDirection = .up
            v.refreshImageCurtainAlpha()
        }
    }

    // MARK: - Permissions

    func doAfterPermissionCheck(block:@escaping () -> Void) {
        checkPermissionToAccessPhotoLibrary { hasPermission in
            if hasPermission {
                block()
            }
        }
    }

    func checkPermission() {
        checkPermissionToAccessPhotoLibrary { [weak self] hasPermission in
            guard let strongSelf = self else {
                return
            }
            if hasPermission && !strongSelf.initialized {
                strongSelf.initialize()
                strongSelf.initialized = true
            }
        }
    }

    // Async beacause will prompt permission if .notDetermined
    // and ask custom popup if denied.
    func checkPermissionToAccessPhotoLibrary(block: @escaping (Bool) -> Void) {
        // Only intilialize picker if photo permission is Allowed by user.
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .authorized:
            block(true)
        case .restricted, .denied:
            let popup = YPPermissionDeniedPopup()
            let alert = popup.popup(cancelBlock: {
                block(false)
            })
            present(alert, animated: true, completion: nil)
        case .notDetermined:
            // Show permission popup and get new status
            PHPhotoLibrary.requestAuthorization { s in
                DispatchQueue.main.async {
                    block(s == .authorized)
                }
            }
        @unknown default:
            fatalError()
        }
    }

	func refreshMediaRequest(isChangingAlbum: Bool = false) {

        let options = buildPHFetchOptions()

        if let collection = mediaManager.collection {
            mediaManager.fetchResult = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            mediaManager.fetchResult = PHAsset.fetchAssets(with: options)
        }

        if mediaManager.fetchResult.count > 0 {
			// prevent selecting asset when changing album or initializing picker
			if YPLibraryVC.selection.count > 0 {
				//changeAsset(mediaManager.fetchResult[0])
				if !isChangingAlbum {
					selectItemFromThumb(index: 0)
				}
			}
            v.collectionView.reloadData()
            v.thumbCollectionView.reloadData()
			// prevent selecting asset when changing album or initializing picker
			if YPLibraryVC.selection.count > 0 {
				/*
				v.collectionView.selectItem(at: IndexPath(row: 0, section: 0),
											animated: false,
											scrollPosition: UICollectionView.ScrollPosition())
				v.thumbCollectionView.selectItem(at: IndexPath(row: 0, section: 0),
												 animated: false,
												 scrollPosition: UICollectionView.ScrollPosition())
				*/
			}
			/*
            if !multipleSelectionEnabled {
                addToSelection(indexPath: IndexPath(row: 0, section: 0))
            }
			*/
        } else {
            delegate?.noPhotosForOptions()
        }
        scrollToTop()
    }

    func buildPHFetchOptions() -> PHFetchOptions {
        // Sorting condition
        if let userOpt = YPConfig.library.options {
            return userOpt
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = YPConfig.library.mediaType.predicate()
        return options
    }

    func scrollToTop() {
        tappedImage()
        v.collectionView.contentOffset = CGPoint.zero
    }

    // MARK: - ScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == v.collectionView {
            mediaManager.updateCachedAssets(in: self.v.collectionView)
        }
    }

	func changeAsset(_ asset: PHAsset, fromThumb: Bool = false) {
        latestImageTapped = asset.localIdentifier
        delegate?.libraryViewStartedLoading()

        let completion = {
            self.v.hideLoader()
            self.v.hideGrid()
            self.delegate?.libraryViewFinishedLoading()
			
			self.v.assetViewContainer.refreshSquareCropButton()
			
            //self.updateCropInfo(shouldUpdateOnlyIfNil: true, fromThumb: fromThumb)
			//self.updateCropInfo()
			self.updateCropInfo(shouldUpdateOnlyIfNil: true)
            //self.refreshExpandState(changeState: false)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            switch asset.mediaType {
            case .image:
                self.v.assetZoomableView.setImage(asset,
                                                  mediaManager: self.mediaManager,
												  storedCropPosition: self.fetchStoredCrop(),
                                                  completion: completion)
            case .video:
                self.v.assetZoomableView.setVideo(asset,
                                                  mediaManager: self.mediaManager,
                                                  storedCropPosition: self.fetchStoredCrop(),
                                                  completion: { completion(false) },
                                                  updateCropInfo: updateCropInfo)
            case .audio, .unknown:
                ()
            @unknown default:
                fatalError()
            }
        }
    }

    // MARK: - Verification

    private func fitsVideoLengthLimits(asset: PHAsset) -> Bool {
        guard asset.mediaType == .video else {
            return true
        }

        let tooLong = asset.duration > YPConfig.video.libraryTimeLimit
        let tooShort = asset.duration < YPConfig.video.minimumTimeLimit

        if tooLong || tooShort {
            DispatchQueue.main.async {
                let alert = tooLong ? YPAlert.videoTooLongAlert(self.view) : YPAlert.videoTooShortAlert(self.view)
                self.present(alert, animated: true, completion: nil)
            }
            return false
        }

        return true
    }

    // MARK: - Stored Crop Position

    internal func updateCropInfo(shouldUpdateOnlyIfNil: Bool = false, fromThumb: Bool = false) {
        var selectedAssetIndex = -1
		/*
        if fromThumb && (currentlySelectedThumb >= 0) && (currentlySelectedThumb < YPLibraryVC.selection.count) {
            selectedAssetIndex = currentlySelectedThumb
        } else if let selectedAssetInx = YPLibraryVC.selection.index(where: { $0.index == currentlySelectedIndex }) {
            selectedAssetIndex = selectedAssetInx
        } else {
            return
        }
		*/
		
		if currentlySelectedThumb >= 0, currentlySelectedThumb < YPLibraryVC.selection.count {
			selectedAssetIndex = currentlySelectedThumb
		}
		
		if shouldUpdateOnlyIfNil && YPLibraryVC.selection[selectedAssetIndex].scrollViewContentOffset != nil {
			return
		}

        // Fill new values
        var selectedAsset = YPLibraryVC.selection[selectedAssetIndex]
		selectedAsset.scrollViewZoomScale = v.assetZoomableView.zoomScale
        selectedAsset.scrollViewContentOffset = v.assetZoomableView.contentOffset
        selectedAsset.cropRect = v.currentCropRect()

        // Replace
        YPLibraryVC.selection.remove(at: selectedAssetIndex)
        YPLibraryVC.selection.insert(selectedAsset, at: selectedAssetIndex)
    }

	internal func fetchStoredCrop(fromThumb: Bool = false) -> YPLibrarySelection? {
		return YPLibraryVC.selection[currentlySelectedThumb]
		
		/*
        if self.multipleSelectionEnabled,
            YPLibraryVC.selection.contains(where: { $0.index == self.currentlySelectedIndex }) {
            guard let selectedAssetIndex = YPLibraryVC.selection
                .index(where: { $0.index == self.currentlySelectedIndex }) else {
                return nil
            }
            return YPLibraryVC.selection[selectedAssetIndex]
        }
        return nil
		*/
    }

    internal func hasStoredCrop(index: Int) -> Bool {
        return YPLibraryVC.selection.contains(where: { $0.index == index })
    }

    // MARK: - Fetching Media

    private func fetchImageAndCrop(for asset: PHAsset,
                                   withCropRect: CGRect? = nil,
                                   callback: @escaping (_ photo: UIImage, _ exif: [String : Any]) -> Void) {
        delegate?.libraryViewDidTapNext()
        let cropRect = withCropRect ?? DispatchQueue.main.sync { v.currentCropRect() }
        let ts = targetSize(for: asset, cropRect: cropRect)
        mediaManager.imageManager?.fetchImage(for: asset, cropRect: cropRect, targetSize: ts, callback: callback)
    }

    private func checkVideoLengthAndCrop(for asset: PHAsset,
                                         withCropRect: CGRect? = nil,
                                         callback: @escaping (_ videoURL: URL) -> Void) {
        if fitsVideoLengthLimits(asset: asset) == true {
            delegate?.libraryViewDidTapNext()
            let normalizedCropRect = withCropRect ?? DispatchQueue.main.sync { v.currentCropRect() }
            let ts = targetSize(for: asset, cropRect: normalizedCropRect)
            let xCrop: CGFloat = normalizedCropRect.origin.x * CGFloat(asset.pixelWidth)
            let yCrop: CGFloat = normalizedCropRect.origin.y * CGFloat(asset.pixelHeight)
            let resultCropRect = CGRect(x: xCrop,
                                        y: yCrop,
                                        width: ts.width,
                                        height: ts.height)
            mediaManager.fetchVideoUrlAndCrop(for: asset, cropRect: resultCropRect, callback: callback)
        }
    }

    public func selectedMedia(photoCallback: @escaping (_ photo: YPMediaPhoto) -> Void,
                              videoCallback: @escaping (_ videoURL: YPMediaVideo) -> Void,
                              multipleItemsCallback: @escaping (_ items: [YPMediaItem]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {

            let selectedAssets: [(asset: PHAsset, cropRect: CGRect?)] = YPLibraryVC.selection.map {
                guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [$0.assetIdentifier], options: PHFetchOptions()).firstObject else { fatalError() }
                return (asset, $0.cropRect)
            }

            // Multiple selection
            if self.multipleSelectionEnabled && YPLibraryVC.selection.count > 1 {

                // Check video length
                for asset in selectedAssets {
                    if self.fitsVideoLengthLimits(asset: asset.asset) == false {
                        return
                    }
                }

                // Fill result media items array
                var resultMediaItems: [YPMediaItem] = []
                let asyncGroup = DispatchGroup()

                for asset in selectedAssets {
                    asyncGroup.enter()

                    switch asset.asset.mediaType {
                    case .image:
                        self.fetchImageAndCrop(for: asset.asset, withCropRect: asset.cropRect) { image, exifMeta in
                            let photo = YPMediaPhoto(image: image.resizedImageIfNeeded(), exifMeta: exifMeta, asset: asset.asset)
                            resultMediaItems.append(YPMediaItem.photo(p: photo))
                            asyncGroup.leave()
                        }

                    case .video:
                        self.checkVideoLengthAndCrop(for: asset.asset, withCropRect: asset.cropRect) { videoURL in
                            let videoItem = YPMediaVideo(thumbnail: thumbnailFromVideoPath(videoURL),
                                                         videoURL: videoURL, asset: asset.asset)
                            resultMediaItems.append(YPMediaItem.video(v: videoItem))
                            asyncGroup.leave()
                        }
                    default:
                        break
                    }
                }

                asyncGroup.notify(queue: .main) {
                    multipleItemsCallback(resultMediaItems)
                    self.delegate?.libraryViewFinishedLoading()
                }
        } else {
                let asset = selectedAssets.first!.asset
                switch asset.mediaType {
                case .audio, .unknown:
                    return
                case .video:
                    self.checkVideoLengthAndCrop(for: asset, callback: { videoURL in
                        DispatchQueue.main.async {
                            self.delegate?.libraryViewFinishedLoading()
                            let video = YPMediaVideo(thumbnail: thumbnailFromVideoPath(videoURL),
                                                     videoURL: videoURL, asset: asset)
                            videoCallback(video)
                        }
                    })
                case .image:
                    self.fetchImageAndCrop(for: asset) { image, exifMeta in
                        DispatchQueue.main.async {
                            self.delegate?.libraryViewFinishedLoading()
                            let photo = YPMediaPhoto(image: image.resizedImageIfNeeded(),
                                                     exifMeta: exifMeta,
                                                     asset: asset)
                            photoCallback(photo)
                        }
                    }
                @unknown default:
                    fatalError()
                }
                return
            }
        }
    }

    // MARK: - TargetSize

    private func targetSize(for asset: PHAsset, cropRect: CGRect) -> CGSize {
        var width = (CGFloat(asset.pixelWidth) * cropRect.width).rounded(.toNearestOrEven)
        var height = (CGFloat(asset.pixelHeight) * cropRect.height).rounded(.toNearestOrEven)
        // round to lowest even number
        width = (width.truncatingRemainder(dividingBy: 2) == 0) ? width : width - 1
        height = (height.truncatingRemainder(dividingBy: 2) == 0) ? height : height - 1
        return CGSize(width: width, height: height)
    }

    // MARK: - Player

    func pausePlayer() {
        v.assetZoomableView.videoView.pause()
    }

    // MARK: - Deinit

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
}

extension NSLayoutConstraint {
    /**
     Change multiplier constraint

     - parameter multiplier: CGFloat
     - returns: NSLayoutConstraint
     */
    func setMultiplier(multiplier:CGFloat) -> NSLayoutConstraint {

        NSLayoutConstraint.deactivate([self])

        let newConstraint = NSLayoutConstraint(
            item: firstItem,
            attribute: firstAttribute,
            relatedBy: relation,
            toItem: secondItem,
            attribute: secondAttribute,
            multiplier: multiplier,
            constant: constant)

        newConstraint.priority = priority
        newConstraint.shouldBeArchived = self.shouldBeArchived
        newConstraint.identifier = self.identifier

        NSLayoutConstraint.activate([newConstraint])
        return newConstraint
    }
}

extension YPLibraryVC {
	func showAssetViewContainer(show: Bool) {
		let canShowSquareCropButton = YPLibraryVC.selection.count == 1
		
		self.v.assetViewContainer.isHidden = !show
		
		self.v.assetViewContainer.squareCropButton.isHidden = !canShowSquareCropButton
		
		self.v.assetViewContainer.deleteButton.isHidden = !YPLibraryVC.canDeselectItem
		
		self.v.assetViewContainerConstraintTop.constant = show ? 16 : -self.v.assetViewContainer.frame.size.height
		if !show {
			self.v.assetViewContainer.zoomableView?.collapseAssetFrame()
		}
		self.v.layoutIfNeeded()
	}
}
