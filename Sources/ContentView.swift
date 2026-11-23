import SwiftUI
import AVKit
import AVFoundation

struct PiPHostView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 110))
        displayLayer.frame = view.bounds
        view.layer.addSublayer(displayLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        displayLayer.frame = uiView.bounds
    }
}

class ThermalPiPManager: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    @Published var stateText: String = "MÁT • ỔN ĐỊNH"
    @Published var detailText: String = "Không giảm xung (~32–36°C)"
    @Published var statusColor: UIColor = .systemGreen
    @Published var isPiPActive: Bool = false

    let displayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?
    private var timer: Timer?

    override init() {
        super.init()
        setupAudioSession()
        setupPiP()
        updateThermalState()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.updateThermalState()
        }
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: .mixWithOthers)
        try? session.setActive(true)
    }

    private func setupPiP() {
        displayLayer.videoGravity = .resizeAspect
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        pipController = AVPictureInPictureController(contentSource: contentSource)
        pipController?.delegate = self
        pipController?.canStartPictureInPictureAutomaticallyFromInline = true
    }

    func togglePiP() {
        guard let pip = pipController else { return }
        renderFrame()
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                pip.startPictureInPicture()
            }
        }
    }

    func updateThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        DispatchQueue.main.async {
            switch state {
            case .nominal:
                self.stateText = "MÁT • ỔN ĐỊNH"
                self.detailText = "Không giảm xung (~32–36°C)"
                self.statusColor = .systemGreen
            case .fair:
                self.stateText = "HƠI ẤM"
                self.detailText = "Bắt đầu ấm lên (~37–40°C)"
                self.statusColor = .systemYellow
            case .serious:
                self.stateText = "NÓNG • CẢNH BÁO"
                self.detailText = "Sắp giảm FPS (~41–44°C)"
                self.statusColor = .systemOrange
            case .critical:
                self.stateText = "QUÁ NHIỆT • BÓP XUNG"
                self.detailText = "Giảm mạnh hiệu năng (>45°C)"
                self.statusColor = .systemRed
            @unknown default:
                self.stateText = "KHÔNG XÁC ĐỊNH"
                self.detailText = "Đang theo dõi..."
                self.statusColor = .systemGray
            }
            self.renderFrame()
        }
    }

    private func renderFrame() {
        let size = CGSize(width: 320, height: 110)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let badgeRect = CGRect(x: 12, y: 12, width: size.width - 24, height: size.height - 24)
            let path = UIBezierPath(roundedRect: badgeRect, cornerRadius: 16)
            statusColor.withAlphaComponent(0.25).setFill()
            path.fill()
            statusColor.setStroke()
            path.lineWidth = 3
            path.stroke()

            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: statusColor
            ]
            let subAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: UIColor.white
            ]
            (stateText as NSString).draw(at: CGPoint(x: 26, y: 24), withAttributes: titleAttr)
            (detailText as NSString).draw(at: CGPoint(x: 26, y: 60), withAttributes: subAttr)
        }

        if let sampleBuffer = image.toSampleBuffer() {
            if displayLayer.status == .failed {
                displayLayer.flush()
            }
            displayLayer.enqueue(sampleBuffer)
        }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = true
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = false
    }
}

extension ThermalPiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {}
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        return CMTimeRange(start: .zero, duration: .positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool { return false }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) { completionHandler() }
}

extension UIImage {
    func toSampleBuffer() -> CMSampleBuffer? {
        guard let cgImage = self.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var pixelBuffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                width: width, height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &formatDesc)
        guard let desc = formatDesc else { return nil }

        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: desc, sampleTiming: &timing, sampleBufferOut: &sampleBuffer)
        return sampleBuffer
    }
}

struct ContentView: View {
    @StateObject private var manager = ThermalPiPManager()

    var body: some View {
        VStack(spacing: 20) {
            Text("Giám Sát Nhiệt Độ")
                .font(.title.bold())

            PiPHostView(displayLayer: manager.displayLayer)
                .frame(width: 320, height: 110)
                .cornerRadius(16)

            Button(action: { manager.togglePiP() }) {
                Label(manager.isPiPActive ? "Tắt Cửa Sổ Nổi" : "Bật Cửa Sổ Nổi Khi Chơi Game",
                      systemImage: "pip.enter")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(12)
            }

            Text("Bấm nút trên rồi vuốt thoát ra màn hình chính, khung nhiệt độ sẽ tự động thu nhỏ nổi trên mọi ứng dụng.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
