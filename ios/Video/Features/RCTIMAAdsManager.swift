import Foundation
import AVFoundation
import GoogleInteractiveMediaAds
import React

@objc(RCTIMAAdsManager)
class RCTIMAAdsManager: NSObject, IMAAdsLoaderDelegate, IMAAdsManagerDelegate {

  private var adsLoader: IMAAdsLoader?
  private var adsManager: IMAAdsManager?
  private var adDisplayContainer: IMAAdDisplayContainer?
  private var player: AVPlayer?
  private var contentPlayhead: IMAAVPlayerContentPlayhead?
  private var contentUrl: String?
  private var adTagUrl: String?
  
  // React Native props
  var contentUri: String?
  var onReceiveAdEvent: RCTDirectEventBlock?

  init(withPlayer player: AVPlayer) {
    self.player = player
    self.contentPlayhead = IMAAVPlayerContentPlayhead(avPlayer: player)
    super.init()
    self.adsLoader = IMAAdsLoader(settings: nil)
    self.adsLoader?.delegate = self
  }

  @objc(requestAds:contentUri:onReceiveAdEvent:)
  func requestAds(_ adTagUrl: String, contentUri: String, onReceiveAdEvent: RCTDirectEventBlock?) {
    self.adTagUrl = adTagUrl
    self.contentUri = contentUri
    self.onReceiveAdEvent = onReceiveAdEvent
    
    // Create the ad display container
    let adContainerView = UIApplication.shared.keyWindow?.rootViewController?.view
    if let adContainerView = adContainerView {
      self.adDisplayContainer = IMAAdDisplayContainer(adContainer: adContainerView, viewController: nil)
    }

    // Create the ad request
    let adRequest = IMAAdsRequest(
      adTagUrl: self.adTagUrl,
      adDisplayContainer: self.adDisplayContainer,
      contentPlayhead: self.contentPlayhead,
      userContext: nil
    )

    self.adsLoader?.requestAds(with: adRequest)
  }

  // MARK: - IMAAdsLoaderDelegate

  func adsLoader(_ loader: IMAAdsLoader, adsLoadedWith adsLoadedData: IMAAdsLoadedData) {
    self.adsManager = adsLoadedData.adsManager
    self.adsManager?.delegate = self
    self.onReceiveAdEvent?([
      "event": "LOADED",
      "data": []
    ])
    self.adsManager?.initialize(with: self.contentPlayhead)
  }

  func adsLoader(_ loader: IMAAdsLoader, failedWith adErrorData: IMAAdLoadingErrorData) {
    print("Error loading ads: \(adErrorData.adError.message ?? "")")
    self.onReceiveAdEvent?([
      "event": "ERROR",
      "data": ["message": adErrorData.adError.message ?? "Unknown error"]
    ])
    self.resetAdsManager() // Clean up on error
  }

  // MARK: - IMAAdsManagerDelegate

  func adsManager(_ adsManager: IMAAdsManager, didReceive event: IMAAdEvent) {
    switch event.type {
    case .STARTED:
      self.onReceiveAdEvent?([
        "event": "STARTED",
        "data": ["ad": event.ad]
      ])
    case .LOADED:
      self.onReceiveAdEvent?([
        "event": "LOADED",
        "data": ["ad": event.ad]
      ])
    case .AD_BREAK_STARTED:
      self.onReceiveAdEvent?([
        "event": "AD_BREAK_STARTED",
        "data": []
      ])
    case .AD_BREAK_ENDED:
      self.onReceiveAdEvent?([
        "event": "AD_BREAK_ENDED",
        "data": []
      ])
    case .TAPPED:
      self.onReceiveAdEvent?([
        "event": "TAPPED",
        "data": []
      ])
    case .PAUSE:
      self.onReceiveAdEvent?([
        "event": "PAUSE",
        "data": []
      ])
    case .RESUME:
      self.onReceiveAdEvent?([
        "event": "RESUME",
        "data": []
      ])
    case .ALL_ADS_COMPLETED:
      self.onReceiveAdEvent?([
        "event": "ALL_ADS_COMPLETED",
        "data": []
      ])
    case .FIRST_QUARTILE:
      self.onReceiveAdEvent?([
        "event": "FIRST_QUARTILE",
        "data": []
      ])
    case .MIDPOINT:
      self.onReceiveAdEvent?([
        "event": "MIDPOINT",
        "data": []
      ])
    case .THIRD_QUARTILE:
      self.onReceiveAdEvent?([
        "event": "THIRD_QUARTILE",
        "data": []
      ])
    case .COMPLETED:
      self.onReceiveAdEvent?([
        "event": "COMPLETED",
        "data": []
      ])
      // CRITICAL FIX: Reset the ads manager after a single ad completes
      self.resetAdsManager()
    default:
      break
    }
  }

  // Fix for "does not conform to protocol" error
  func adsManager(_ adsManager: IMAAdsManager, adDidProgressToTime mediaTime: TimeInterval, adDuration: TimeInterval, adBreakDuration: TimeInterval, isAdBreakSkippable: Bool, adPosition: Int, totalAds: Int) {
      // This method is required by the IMAAdsManagerDelegate protocol
      // You can add logic here to track ad progress if needed
  }
  
  func adsManagerDidRequestContentPause(_ adsManager: IMAAdsManager) {
    self.onReceiveAdEvent?([
      "event": "CONTENT_PAUSE_REQUESTED",
      "data": []
    ])
  }

  func adsManagerDidRequestContentResume(_ adsManager: IMAAdsManager) {
    self.onReceiveAdEvent?([
      "event": "CONTENT_RESUME_REQUESTED",
      "data": []
    ])
  }

  func adsManager(_ adsManager: IMAAdsManager, adDidFailToLoadWith error: IMAAdError) {
    print("Ad load failed with error: \(error.message ?? "")")
    self.onReceiveAdEvent?([
      "event": "ERROR",
      "data": ["message": error.message ?? "Unknown error"]
    ])
    self.resetAdsManager() // Clean up on error
  }

  // MARK: - Private Methods
  
  // New private method to safely release ad objects
  private func resetAdsManager() {
    print("Resetting IMA Ads Manager")
    self.adsManager?.destroy()
    self.adsManager = nil
    self.adDisplayContainer = nil
    self.adsLoader = nil
  }
}
