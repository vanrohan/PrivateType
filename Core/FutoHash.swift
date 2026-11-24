import Foundation

// These operations match FUTO's wyhash and multiply-shift vocabulary lookup.
public enum FutoHash {
    public static func buckets(_ word: String) -> [Int64] {
        let key = hash(Array(word.utf8))
        return [Int64((key &* 0x9E3779B97F4A7C15) >> 49), Int64((key &* 0x517CC1B727220A95) >> 49)]
    }

    private static func mix(_ a: UInt64, _ b: UInt64) -> UInt64 {
        let product = a.multipliedFullWidth(by: b)
        return product.high ^ product.low
    }

    public static func hash(_ bytes: [UInt8]) -> UInt64 {
        let s0: UInt64 = 0xa0761d6478bd642f, s1: UInt64 = 0xe7037ed1a0b428db
        let s2: UInt64 = 0x8ebc6af09c88c6e3, s3: UInt64 = 0x589965cc75374cc3
        let length = bytes.count
        func read(_ position: Int, _ count: Int) -> UInt64 {
            var result: UInt64 = 0
            for index in 0..<count { result |= UInt64(bytes[position + index]) << (index * 8) }
            return result
        }
        var seed = mix(s0, s1), a: UInt64 = 0, b: UInt64 = 0
        if length <= 16 {
            if length >= 4 {
                a = (read(0, 4) << 32) | read((length >> 3) << 2, 4)
                b = (read(length - 4, 4) << 32) | read(length - 4 - ((length >> 3) << 2), 4)
            } else if length > 0 {
                a = (UInt64(bytes[0]) << 16) | (UInt64(bytes[length >> 1]) << 8) | UInt64(bytes[length - 1])
            }
        } else {
            var index = 0
            if length > 48 {
                var see1 = seed, see2 = seed
                while index + 48 <= length {
                    seed = mix(read(index, 8) ^ s1, read(index + 8, 8) ^ seed)
                    see1 = mix(read(index + 16, 8) ^ s2, read(index + 24, 8) ^ see1)
                    see2 = mix(read(index + 32, 8) ^ s3, read(index + 40, 8) ^ see2)
                    index += 48
                }
                while index + 16 <= length {
                    seed = mix(read(index, 8) ^ s1, read(index + 8, 8) ^ seed)
                    index += 16
                }
                seed ^= see1 ^ see2
            } else {
                while index + 16 <= length {
                    seed = mix(read(index, 8) ^ s1, read(index + 8, 8) ^ seed)
                    index += 16
                }
            }
            a = read(length - 16, 8)
            b = read(length - 8, 8)
        }
        return mix(s1 ^ UInt64(length), mix(a ^ s1, b ^ seed))
    }
}
