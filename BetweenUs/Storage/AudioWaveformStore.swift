import DSWaveformImage
import Foundation

/// 语音条形的振幅来源。
///
/// 一次解码得到固定分辨率的振幅并缓存，视图宽度变化时只在内存里重采样，
/// 不重复读文件。`DSWaveformImage` 只负责分析，绘制仍由界面自己完成。
actor AudioWaveformStore {
    static let shared = AudioWaveformStore()

    /// 分析分辨率。解码只做一次，取高一点以便拿到峰值，再在内存里降到条形数量。
    private let resolution = 2_048
    private var cache: [String: [Float]] = [:]
    private var inFlight: [String: Task<[Float]?, Never>] = [:]

    /// 返回 `0...1` 的响度序列：0 是静音，1 是最响。分析失败时返回 `nil`。
    func loudness(for url: URL) async -> [Float]? {
        let key = url.path
        if let cached = cache[key] { return cached }
        if let task = inFlight[key] { return await task.value }

        let resolution = resolution
        let task = Task<[Float]?, Never> {
            // DSWaveformImage 的振幅方向相反：0 最响、1 静音；单桶取的是 dB 均值，
            // 时长越长越贴近静音底，所以这里统一按文件峰值重标定。
            guard let amplitudes = try? await WaveformAnalyzer().samples(
                fromAudioAt: url,
                count: resolution
            ), !amplitudes.isEmpty else { return nil }

            let values = amplitudes.map { min(max(1 - $0, 0), 1) }
            // 以偏上的分位数为基准：用最大值会被一两声噪声压平，用中位数则整条都贴在顶部。
            let reference = max(Self.percentile(values, 0.9), 0.0001)
            return values.map { min($0 / reference, 1) }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { cache[key] = result }
        return result
    }

    /// 把缓存分辨率重采样到当前条形数量。
    ///
    /// 降到更少条形时取区间均值：取峰值会把整条波形拉平，静音和说话看起来一样高。
    static func resample(_ samples: [Float]?, to count: Int) -> [Float]? {
        guard let samples, !samples.isEmpty, count > 0 else { return nil }
        guard samples.count != count else { return samples }
        if samples.count > count {
            return (0..<count).map { index in
                let start = index * samples.count / count
                let end = max(start + 1, (index + 1) * samples.count / count)
                let slice = samples[start..<min(end, samples.count)]
                return slice.reduce(0, +) / Float(slice.count)
            }
        }
        return (0..<count).map { samples[min(samples.count - 1, $0 * samples.count / count)] }
    }

    private static func percentile(_ values: [Float], _ fraction: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * fraction).rounded())
        return sorted[min(max(index, 0), sorted.count - 1)]
    }
}
