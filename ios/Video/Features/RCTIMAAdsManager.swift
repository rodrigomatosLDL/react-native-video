#if USE_GOOGLE_IMA
import Foundation
import GoogleInteractiveMediaAds

class RCTIMAAdsManager: NSObject, IMAAdsLoaderDelegate, IMAAdsManagerDelegate, IMALinkOpenerDelegate {
    private weak var _video: RCTVideo?
    private var _isPictureInPictureActive: () -> Bool

    // State flags
    private var adBreakStarted = false          // true after first start() in a break
    private var isAdPlaying = false             // true between ContentPauseRequested and ContentResumeRequested

    /* Entry point for the SDK. Used to make ad requests. */
    private var adsLoader: IMAAdsLoader!
    /* Main point of interaction with the SDK. Created by the SDK as the result of an ad request. */
    private var adsManager: IMAAdsManager!

    init(video: RCTVideo!, isPictureInPictureActive: @escaping () -> Bool) {
        _video = video
        _isPictureInPictureActive = isPictureInPictureActive
        super.init()
    }

    func setUpAdsLoader() {
        guard let _video else { return }
        let settings = IMASettings()
        if let adLanguage = _video.getAdLanguage() {
            settings.language = adLanguage
        }
        adsLoader = IMAAdsLoader(settings: settings)
        adsLoader.delegate = self
    }

    func requestAds() {
        guard let _video else { return }
        // fixes RCTVideo --> RCTIMAAdsManager --> IMAAdsLoader --> IMAAdDisplayContainer --> RCTVideo memory leak.
        let adContainerView = UIView(frame: _video.bounds)
        adContainerView.backgroundColor = .clear
        adContainerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        _video.addSubview(adContainerView)

        let adDisplayContainer = IMAAdDisplayContainer(
            adContainer: adContainerView,
            viewController: _video.reactViewController()
        )

        let adTagUrl = _video.getAdTagUrl()
        let contentPlayhead = _video.getContentPlayhead()

        if let adTagUrl, let contentPlayhead {
            let request = IMAAdsRequest(
                adTagUrl: adTagUrl,
                adDisplayContainer: adDisplayContainer,
                contentPlayhead: contentPlayhead,
                userContext: nil
            )
            adsLoader.requestAds(with: request)
        }
    }

    func releaseAds() {
        // Reset local flags early to avoid stale state
        adBreakStarted = false
        isAdPlaying = false

        guard let adsManager else { return }
        // Stop immediately (tvos 17 / detach race fix)
        adsManager.volume = 0
        adsManager.pause()
        adsManager.destroy()
    }

    // MARK: - Getters

    func getAdsLoader() -> IMAAdsLoader? { adsLoader }
    func getAdsManager() -> IMAAdsManager? { adsManager }

    // MARK: - IMAAdsLoaderDelegate

    func adsLoader(_ loader: IMAAdsLoader, adsLoadedWith adsLoadedData: IMAAdsLoadedData) {
        guard let _video else { return }
        adsManager = adsLoadedData.adsManager
        adsManager?.delegate = self

        let adsRenderingSettings = IMAAdsRenderingSettings()
        adsRenderingSettings.linkOpenerDelegate = self
        adsRenderingSettings.linkOpenerPresentingController = _video.reactViewController()

        adsManager.initialize(with: adsRenderingSettings)

        // Reset per-request flags
        adBreakStarted = false
        isAdPlaying = false
    }

    func adsLoader(_ loader: IMAAdsLoader, failedWith adErrorData: IMAAdLoadingErrorData) {
        if let message = adErrorData.adError.message {
            print("IMA load error:", message)
        }
        _video?.setPaused(false)
    }

    // MARK: - IMAAdsManagerDelegate

    func adsManager(_ adsManager: IMAAdsManager, didReceive event: IMAAdEvent) {
        guard let _video else { return }

        // Keep ad volume in sync with player mute
        if _video.isMuted() {
            adsManager.volume = 0
        }

        switch event.type {
        case .LOADED:
            // Start an ad only if no ad is currently playing.
            // Handles both: (1) single pod (first LOADED starts sequencing)
            // and (2) multiple separate ads in a single VAST (each LOADED needs a start after resume).
            if !_isPictureInPictureActive() && !isAdPlaying {
                adsManager.start()
                adBreakStarted = true
            }

        case .AD_BREAK_STARTED:
            // Break started; keep flags consistent
            adBreakStarted = true

        case .ALL_ADS_COMPLETED, .AD_BREAK_ENDED:
            // End of the ad break; let ContentResumeRequested do the actual resume.
            adBreakStarted = false

        default:
            break
        }

        // Emit events to JS
        if let onReceiveAdEvent = _video.onReceiveAdEvent {
            let type = convertEventToString(event: event.type)
            if let adData = event.adData {
                onReceiveAdEvent([
                    "event": type,
                    "data": adData,
                    "target": _video.reactTag!,
                ])
            } else {
                onReceiveAdEvent([
                    "event": type,
                    "target": _video.reactTag!,
                ])
            }
        }
    }

    func adsManager(_ adsManager: IMAAdsManager, didReceive error: IMAAdError) {
        if let message = error.message {
            print("IMA manager error:", message)
        }

        guard let _video else { return }

        if let onReceiveAdEvent = _video.onReceiveAdEvent {
            onReceiveAdEvent([
                "event": "ERROR",
                "data": [
                    "message": error.message ?? "",
                    "code": error.code,
                    "type": error.type,
                ],
                "target": _video.reactTag!,
            ])
        }

        // Failover to content
        adBreakStarted = false
        isAdPlaying = false
        _video.setPaused(false)
    }

    func adsManagerDidRequestContentPause(_ adsManager: IMAAdsManager) {
        // SDK is about to play ads
        isAdPlaying = true
        _video?.setPaused(true)
        _video?.setAdPlaying(true)
    }

    func adsManagerDidRequestContentResume(_ adsManager: IMAAdsManager) {
        // SDK finished the ad break
        isAdPlaying = false
        adBreakStarted = false
        _video?.setAdPlaying(false)
        _video?.setPaused(false)
    }

    // MARK: - IMALinkOpenerDelegate

    func linkOpenerDidClose(inAppLink _: NSObject) {
        adsManager?.resume()
    }

    // MARK: - Helpers

    func convertEventToString(event: IMAAdEventType!) -> String {
        var result = "UNKNOWN"
        switch event {
        case .AD_BREAK_READY:     result = "AD_BREAK_READY"
        case .AD_BREAK_ENDED:     result = "AD_BREAK_ENDED"
        case .AD_BREAK_STARTED:   result = "AD_BREAK_STARTED"
        case .AD_PERIOD_ENDED:    result = "AD_PERIOD_ENDED"
        case .AD_PERIOD_STARTED:  result = "AD_PERIOD_STARTED"
        case .ALL_ADS_COMPLETED:  result = "ALL_ADS_COMPLETED"
        case .CLICKED:            result = "CLICK"
        case .COMPLETE:           result = "COMPLETED"
        case .CUEPOINTS_CHANGED:  result = "CUEPOINTS_CHANGED"
        case .FIRST_QUARTILE:     result = "FIRST_QUARTILE"
        case .LOADED:             result = "LOADED"
        case .LOG:                result = "LOG"
        case .MIDPOINT:           result = "MIDPOINT"
        case .PAUSE:              result = "PAUSED"
        case .RESUME:             result = "RESUMED"
        case .SKIPPED:            result = "SKIPPED"
        case .STARTED:            result = "STARTED"
        case .STREAM_LOADED:      result = "STREAM_LOADED"
        case .TAPPED:             result = "TAPPED"
        case .THIRD_QUARTILE:     result = "THIRD_QUARTILE"
        default:                  result = "UNKNOWN"
        }
        return result
    }
}
#endif
