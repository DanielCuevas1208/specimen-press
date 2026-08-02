import Foundation

struct BinaryReader {
    let data: Data

    var count: Int { data.count }

    func require(offset: Int, length: Int) throws {
        guard offset >= 0, length >= 0, offset <= data.count - length else {
            throw FontError.dataTooShort(offset: offset, length: length)
        }
    }

    func uint8(at offset: Int) throws -> UInt8 {
        try require(offset: offset, length: 1)
        return data[offset]
    }

    func int8(at offset: Int) throws -> Int8 {
        Int8(bitPattern: try uint8(at: offset))
    }

    func uint16(at offset: Int) throws -> UInt16 {
        try require(offset: offset, length: 2)
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    func int16(at offset: Int) throws -> Int16 {
        Int16(bitPattern: try uint16(at: offset))
    }

    func uint32(at offset: Int) throws -> UInt32 {
        try require(offset: offset, length: 4)
        return (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }

    func int32(at offset: Int) throws -> Int32 {
        Int32(bitPattern: try uint32(at: offset))
    }

    func tag(at offset: Int) throws -> String {
        try require(offset: offset, length: 4)
        return String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
    }

    func subdata(offset: Int, length: Int) throws -> Data {
        try require(offset: offset, length: length)
        return data.subdata(in: offset..<(offset + length))
    }
