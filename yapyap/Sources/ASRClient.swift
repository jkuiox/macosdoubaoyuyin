import Foundation
import Compression

class ASRClient {
    var onTextUpdate: ((String) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private let settings = SettingsStore.shared

    // Binary protocol constants
    private let protocolVersion: UInt8 = 0x1
    private let headerSize: UInt8 = 0x1

    func connect() {
        let connectId = UUID().uuidString

        guard let url = URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel") else { return }

        var request = URLRequest(url: url)
        request.setValue(settings.appKey, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(settings.accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(settings.resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectId, forHTTPHeaderField: "X-Api-Connect-Id")

        session = URLSession(configuration: .default)
        webSocketTask = session?.webSocketTask(with: request)
        webSocketTask?.resume()

        sendFullClientRequest()
        receiveLoop()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: - Send

    func sendAudio(data: Data) {
        let packet = buildAudioPacket(data: data, isLast: false)
        webSocketTask?.send(.data(packet)) { error in
            if let error { print("Send audio error: \(error)") }
        }
    }

    func sendLastAudio() {
        // Send an empty last packet
        let packet = buildAudioPacket(data: Data(), isLast: true)
        webSocketTask?.send(.data(packet)) { error in
            if let error { print("Send last audio error: \(error)") }
        }
    }

    private func sendFullClientRequest() {
        let payload: [String: Any] = [
            "user": [
                "uid": "yapyap_user"
            ],
            "audio": [
                "format": "pcm",
                "rate": 16000,
                "bits": 16,
                "channel": 1,
                "codec": "raw"
            ],
            "request": [
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "enable_ddc": true,
                "result_type": "full",
                "show_utterances": true
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let gzipped = gzip(data: jsonData) else { return }

        // Header: version=1, headerSize=1, msgType=0001(full client), flags=0000,
        //         serialization=0001(JSON), compression=0001(Gzip), reserved=0x00
        let header = buildHeader(messageType: 0x1, flags: 0x0, serialization: 0x1, compression: 0x1)

        var packet = Data()
        packet.append(contentsOf: header)
        // Payload size (big-endian uint32)
        var size = UInt32(gzipped.count).bigEndian
        packet.append(Data(bytes: &size, count: 4))
        packet.append(gzipped)

        webSocketTask?.send(.data(packet)) { error in
            if let error { print("Send full client request error: \(error)") }
        }
    }

    private func buildAudioPacket(data: Data, isLast: Bool) -> Data {
        let gzipped = gzip(data: data) ?? data

        // msgType=0010(audio only), flags=0000(normal) or 0010(last)
        let flags: UInt8 = isLast ? 0x2 : 0x0
        let header = buildHeader(messageType: 0x2, flags: flags, serialization: 0x0, compression: 0x1)

        var packet = Data()
        packet.append(contentsOf: header)
        var size = UInt32(gzipped.count).bigEndian
        packet.append(Data(bytes: &size, count: 4))
        packet.append(gzipped)
        return packet
    }

    private func buildHeader(messageType: UInt8, flags: UInt8, serialization: UInt8, compression: UInt8) -> [UInt8] {
        let byte0 = (protocolVersion << 4) | headerSize
        let byte1 = (messageType << 4) | flags
        let byte2 = (serialization << 4) | compression
        let byte3: UInt8 = 0x00
        return [byte0, byte1, byte2, byte3]
    }

    // MARK: - Receive

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.parseResponse(data)
                case .string(let text):
                    print("Received text (unexpected): \(text)")
                @unknown default:
                    break
                }
                self.receiveLoop()

            case .failure(let error):
                print("WebSocket receive error: \(error)")
            }
        }
    }

    private func parseResponse(_ data: Data) {
        guard data.count >= 4 else { return }

        let byte1 = data[1]
        let messageType = (byte1 >> 4) & 0x0F

        if messageType == 0xF {
            // Error response
            parseErrorResponse(data)
            return
        }

        guard messageType == 0x9 else { return } // Full server response

        let byte2 = data[2]
        let compression = byte2 & 0x0F

        // Skip header (4 bytes) + sequence (4 bytes)
        guard data.count >= 12 else { return }
        let payloadSizeBytes = data[8..<12]
        let payloadSize = UInt32(bigEndian: payloadSizeBytes.withUnsafeBytes { $0.load(as: UInt32.self) })

        guard data.count >= 12 + Int(payloadSize) else { return }
        var payload = data[12..<(12 + Int(payloadSize))]

        if compression == 0x1 {
            guard let decompressed = gunzip(data: Data(payload)) else { return }
            payload = decompressed[decompressed.startIndex..<decompressed.endIndex]
        }

        guard let json = try? JSONSerialization.jsonObject(with: Data(payload)) as? [String: Any],
              let resultList = json["result"] as? [String: Any],
              let text = resultList["text"] as? String else { return }

        DispatchQueue.main.async {
            self.onTextUpdate?(text)
        }
    }

    private func parseErrorResponse(_ data: Data) {
        guard data.count >= 12 else { return }
        let errorCodeBytes = data[4..<8]
        let errorCode = UInt32(bigEndian: errorCodeBytes.withUnsafeBytes { $0.load(as: UInt32.self) })
        let msgSizeBytes = data[8..<12]
        let msgSize = UInt32(bigEndian: msgSizeBytes.withUnsafeBytes { $0.load(as: UInt32.self) })

        var errorMsg = ""
        if data.count >= 12 + Int(msgSize) {
            errorMsg = String(data: data[12..<(12 + Int(msgSize))], encoding: .utf8) ?? ""
        }
        print("ASR Error \(errorCode): \(errorMsg)")
    }

    // MARK: - Compression

    private func gzip(data: Data) -> Data? {
        guard !data.isEmpty else {
            // Return minimal valid gzip for empty data
            return Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03,
                         0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        }

        var compressed = Data()
        // Gzip header
        compressed.append(contentsOf: [0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])

        // Deflate the data
        let bufferSize = max(data.count, 128)
        var deflated = Data(count: bufferSize)

        let result = deflated.withUnsafeMutableBytes { destPtr -> Int in
            data.withUnsafeBytes { srcPtr -> Int in
                let bound = destPtr.bindMemory(to: UInt8.self)
                let srcBound = srcPtr.bindMemory(to: UInt8.self)
                let written = compression_encode_buffer(
                    bound.baseAddress!, bufferSize,
                    srcBound.baseAddress!, data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
                return written
            }
        }

        guard result > 0 else { return nil }
        deflated.count = result
        compressed.append(deflated)

        // CRC32 + original size (little-endian)
        var crc = crc32(data: data)
        compressed.append(Data(bytes: &crc, count: 4))
        var originalSize = UInt32(data.count)
        compressed.append(Data(bytes: &originalSize, count: 4))

        return compressed
    }

    private func gunzip(data: Data) -> Data? {
        // Skip gzip header (minimum 10 bytes)
        guard data.count > 10, data[0] == 0x1f, data[1] == 0x8b else {
            // Try raw inflate
            return inflate(data: data)
        }

        var headerLen = 10
        let flags = data[3]
        if flags & 0x04 != 0 { // FEXTRA
            guard data.count > headerLen + 2 else { return nil }
            let extraLen = Int(data[headerLen]) | (Int(data[headerLen + 1]) << 8)
            headerLen += 2 + extraLen
        }
        if flags & 0x08 != 0 { // FNAME
            while headerLen < data.count && data[headerLen] != 0 { headerLen += 1 }
            headerLen += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while headerLen < data.count && data[headerLen] != 0 { headerLen += 1 }
            headerLen += 1
        }
        if flags & 0x02 != 0 { headerLen += 2 } // FHCRC

        guard headerLen < data.count else { return nil }

        // Strip gzip header and 8-byte trailer (CRC32 + size)
        let compressed = data[headerLen..<max(headerLen, data.count - 8)]
        return inflate(data: Data(compressed))
    }

    private func inflate(data: Data) -> Data? {
        let bufferSize = data.count * 10
        var decompressed = Data(count: bufferSize)

        let result = decompressed.withUnsafeMutableBytes { destPtr -> Int in
            data.withUnsafeBytes { srcPtr -> Int in
                let bound = destPtr.bindMemory(to: UInt8.self)
                let srcBound = srcPtr.bindMemory(to: UInt8.self)
                return compression_decode_buffer(
                    bound.baseAddress!, bufferSize,
                    srcBound.baseAddress!, data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard result > 0 else { return nil }
        decompressed.count = result
        return decompressed
    }

    private func crc32(data: Data) -> UInt32 {
        let table: [UInt32] = (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 != 0) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
