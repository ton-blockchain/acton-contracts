// ──────────────────────────────────────────────────────────────────────────
// WebAuthn ES256 (P-256) verification primitives.
//
// Two helpers below are full TVM asm wrappers; the rest is the b64url-binding
// check, picked from the V18 / V14 benchmarks in tests/b64url-fast.test.tolk:
//
//   pre-ACCEPT (must fit in TVM gas-credit, default 10000):
//     V18 prefix check verifies that the FIRST 19 chars of the on-chain
//     challenge slice equal base64url(top 114 bits of cell.hash(payload)).
//     ~5350 gas for the binding check, ~9500 gas end-to-end. This is the
//     spam filter.
//
//   post-ACCEPT (full security):
//     V14 full check verifies all 43 chars against cell.hash(payload) (256 bits).
//     ~11650 gas. Catches any prefix-only collision attempt; runs after
//     ACCEPT_MESSAGE so a failure costs only the gas spent (sub-cent), not
//     the wallet's funds.
// ──────────────────────────────────────────────────────────────────────────
// TVM op P256_CHKSIGNS — ECDSA-P256-SHA256 verify.
//   `d`      = arbitrary slice; the op SHA-256s its bytes internally.
//   `sig`    = raw r||s, 64 bytes.
//   `pubKey` = SEC1 compressed point, 33 bytes.
// check-disable-next-line asm-function-missing-safety-comment
fun p256ChkSignS(d: slice, sig: slice, pubKey: slice): bool
    asm "P256_CHKSIGNS"

// TVM op HASHEXT_SHA256 — sha256 of the concatenation of n slices.
// We always pass exactly 3 slices: cdj_prefix, on-chain challenge, cdj_suffix.
// check-disable-next-line asm-function-missing-safety-comment
fun sha256ThreeSlices(s1: slice, s2: slice, s3: slice): uint256
    asm "3 PUSHINT HASHEXT_SHA256"

const B64URL_ALPHABET : slice = "4142434445464748494a4b4c4d4e4f505152535455565758595a6162636465666768696a6b6c6d6e6f707172737475767778797a303132333435363738392d5f"
    .hexToSlice()

@inline
fun b64urlPackedAscii64(packed6: int): int {
    return packed6 + 0x4141414141414141 +
    ((((packed6 + 0x6666666666666666) | packed6) & 0x8080808080808080) >> 7) * 6 -
    ((((packed6 + 0x4C4C4C4C4C4C4C4C) | packed6) & 0x8080808080808080) >> 7) * 75 -
    ((((packed6 + 0x4242424242424242) | packed6) & 0x8080808080808080) >> 7) * 13 +
    ((((packed6 + 0x4141414141414141) | packed6) & 0x8080808080808080) >> 7) * 49;
}

@inline
fun pack48To6BitBytes(chunk: int): int {
    val y = ((chunk >> 24) << 32) | (chunk & 0xFFFFFF);
    return ((y & 0x00FC000000FC0000) << 6) | ((y & 0x0003F0000003F000) << 4) |
    ((y & 0x00000FC000000FC0) << 2) |
    (y & 0x0000003F0000003F);
}

// ─── Pre-ACCEPT: 114-bit prefix check (V18, single 19-byte compare) ──────
// Reads the FIRST 19 bytes of `challenge` (= 19 ASCII chars = 114-bit prefix
// in base64url), compares them against base64url(top 114 bits of `bodyHash`).
// `challenge` is passed by value; the caller's slice is not mutated.
@inline
fun verifyB64uPrefix114(bodyHash: uint256, challenge: slice): bool {
    val alpha: slice = B64URL_ALPHABET;
    val hash114 = bodyHash >> 142;

    val chunk0 = (hash114 >> 66) & 0xFFFFFFFFFFFF;
    val ascii0 = b64urlPackedAscii64(pack48To6BitBytes(chunk0));

    val chunk1 = (hash114 >> 18) & 0xFFFFFFFFFFFF;
    val ascii1 = b64urlPackedAscii64(pack48To6BitBytes(chunk1));

    val last18 = hash114 & 0x3FFFF;
    var a0 = alpha;
    a0.skipBits(((last18 >> 12) & 0x3F) * 8);
    var a1 = alpha;
    a1.skipBits(((last18 >> 6) & 0x3F) * 8);
    var a2 = alpha;
    a2.skipBits((last18 & 0x3F) * 8);
    val tail = (a0.preloadUint(8) << 16) | (a1.preloadUint(8) << 8) | a2.preloadUint(8);

    val expected = (ascii0 << 88) | (ascii1 << 24) | tail;
    return challenge.loadUint(152) == expected;
}

// ─── Post-ACCEPT: full 256-bit check (V14 SWAR, 48-bit chunks) ───────────
// Verifies every byte of the 43-char `challenge` against base64url(bodyHash).
// 5 full 48-bit chunks (40 chars) + 16 trailing bits (3 chars).
fun verifyB64uFull256(bodyHash: uint256, challenge: slice): bool {
    var input: slice = challenge;
    var shift: int = 208;
    repeat (5) {
        val chunk = (bodyHash >> shift) & 0xFFFFFFFFFFFF;
        if (input.loadUint(64) != b64urlPackedAscii64(pack48To6BitBytes(chunk))) {
            return false;
        }
        shift -= 48;
    }

    val last16 = bodyHash & 0xFFFF;
    val tailPacked = (((last16 >> 10) & 0x3F) << 56) | (((last16 >> 4) & 0x3F) << 48) |
    (((last16 & 0xF) << 2) << 40);
    return input.loadUint(24) == (b64urlPackedAscii64(tailPacked) >> 40);
}
