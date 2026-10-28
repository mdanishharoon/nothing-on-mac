// Wire framing for the Nothing / CMF serial control protocol (RFCOMM).
//
// Every packet is:
//   55 60 01 | cmd lo | cmd hi | payload length | 00 | operation id | payload… | crc lo | crc hi
// with a CRC-16/MODBUS over everything before the checksum.
// Ported from radiance-project/ear-web (res/js/bluetooth_socket.js).

public enum CRC16 {
    /// CRC-16/MODBUS: reflected polynomial 0xA001, initial value 0xFFFF.
    public static func modbus<C: Collection>(_ bytes: C) -> UInt16 where C.Element == UInt8 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        return crc
    }
}

public enum Wire {
    public static let marker: UInt8 = 0x55
    public static let headerLength = 8
}

public struct Frame: Equatable, Sendable {
    public let command: UInt16
    public let operationID: UInt8
    public let payload: [UInt8]
    /// False when the frame had no trailing checksum or the checksum did not match.
    public let checksumValid: Bool

    public init(command: UInt16, operationID: UInt8, payload: [UInt8], checksumValid: Bool) {
        self.command = command
        self.operationID = operationID
        self.payload = payload
        self.checksumValid = checksumValid
    }
}

public struct PacketEncoder: Sendable {
    public private(set) var operationID: UInt8 = 0

    public init() {}

    public mutating func encode(_ request: Request) -> [UInt8] {
        precondition(request.payload.count <= 255, "payload length is a single byte")
        operationID = operationID >= 250 ? 1 : operationID + 1
        var bytes: [UInt8] = [
            Wire.marker, 0x60, 0x01,
            UInt8(request.command & 0xFF), UInt8(request.command >> 8),
            UInt8(request.payload.count), 0x00, operationID,
        ]
        bytes += request.payload
        let crc = CRC16.modbus(bytes)
        bytes += [UInt8(crc & 0xFF), UInt8(crc >> 8)]
        return bytes
    }
}

/// Reassembles frames from an RFCOMM byte stream, which may split or coalesce packets.
public struct FrameParser: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func append(_ bytes: [UInt8]) -> [Frame] {
        buffer += bytes
        var frames: [Frame] = []
        while true {
            guard let start = buffer.firstIndex(of: Wire.marker) else {
                buffer.removeAll()
                break
            }
            buffer.removeFirst(start)
            guard buffer.count >= Wire.headerLength else { break }

            let bodyEnd = Wire.headerLength + Int(buffer[5])
            guard buffer.count >= bodyEnd else { break }
            let body = Array(buffer[0..<bodyEnd])

            let hasRoomForChecksum = buffer.count >= bodyEnd + 2
            if hasRoomForChecksum,
               CRC16.modbus(body) == UInt16(buffer[bodyEnd]) | UInt16(buffer[bodyEnd + 1]) << 8 {
                frames.append(Self.frame(body, checksumValid: true))
                buffer.removeFirst(bodyEnd + 2)
                continue
            }
            // No checksum: the body ends the stream, or the next frame starts right after it.
            if buffer.count == bodyEnd || buffer[bodyEnd] == Wire.marker {
                frames.append(Self.frame(body, checksumValid: false))
                buffer.removeFirst(bodyEnd)
                continue
            }
            guard hasRoomForChecksum else { break }
            frames.append(Self.frame(body, checksumValid: false))
            buffer.removeFirst(bodyEnd + 2)
        }
        return frames
    }

    private static func frame(_ body: [UInt8], checksumValid: Bool) -> Frame {
        Frame(
            command: UInt16(body[3]) | UInt16(body[4]) << 8,
            operationID: body[7],
            payload: Array(body[Wire.headerLength...]),
            checksumValid: checksumValid
        )
    }
}
