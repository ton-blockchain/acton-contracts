// ──────────────────────────────────────────────────────────────────────────
// WebAuthn ES256 (P-256) verification primitives.
//
// Two helpers below are full TVM asm wrappers; the rest is the b64url-binding
// check, picked from the V13 / V10 benchmarks in tests/b64url-fast.test.tolk:
//
//   pre-ACCEPT (must fit in TVM gas-credit, default 10000):
//     V13 prefix check verifies that the FIRST 16 chars of the on-chain
//     challenge slice equal base64url(top 96 bits of cell.hash(body)).
//     5143 gas. This is the spam filter.
//
//   post-ACCEPT (full security):
//     V10 full check verifies all 43 chars against cell.hash(body) (256 bits).
//     ~14750 gas. Catches the 2^48-collision attempt that the prefix check
//     could miss; runs after ACCEPT_MESSAGE so a failure costs only the gas
//     spent (sub-cent), not the wallet's funds.
// ──────────────────────────────────────────────────────────────────────────

// TVM op P256_CHKSIGNS — ECDSA-P256-SHA256 verify.
//   `d`      = arbitrary slice; the op SHA-256s its bytes internally.
//   `sig`    = raw r||s, 64 bytes.
//   `pubKey` = SEC1 compressed point, 33 bytes.
// check-disable-next-line asm-function-missing-safety-comment
fun p256ChkSignS(d: slice, sig: slice, pubKey: slice): bool
    asm "P256_CHKSIGNS";

// TVM op HASHEXT_SHA256 — sha256 of the concatenation of n slices.
// We always pass exactly 3 slices: cdj_prefix, on-chain challenge, cdj_suffix.
// check-disable-next-line asm-function-missing-safety-comment
fun sha256ThreeSlices(s1: slice, s2: slice, s3: slice): uint256
    asm "3 PUSHINT HASHEXT_SHA256";

// "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
const B64URL_ALPHABET: slice =
    "4142434445464748494a4b4c4d4e4f505152535455565758595a6162636465666768696a6b6c6d6e6f707172737475767778797a303132333435363738392d5f"
        .hexToSlice();

// ─── Pre-ACCEPT: 96-bit prefix check (V13, fully unrolled, 2 chunks) ─────
// Reads the FIRST 16 bytes of `challenge` (= 16 ASCII chars = 96-bit prefix
// in base64url), compares them against base64url(top 96 bits of `bodyHash`).
// `challenge` is passed by value; the caller's slice is not mutated.
fun verifyB64uPrefix96(bodyHash: uint256, challenge: slice): bool {
    val alpha: slice = B64URL_ALPHABET;
    val hash96 = bodyHash >> 160;
    var input: slice = challenge;
    // Chunk 0: top 48 bits of hash96.
    val chunk0 = (hash96 >> 48) & 0xFFFFFFFFFFFF;
    var a0 = alpha; a0.skipBits(((chunk0 >> 42) & 0x3F) * 8);
    var a1 = alpha; a1.skipBits(((chunk0 >> 36) & 0x3F) * 8);
    var a2 = alpha; a2.skipBits(((chunk0 >> 30) & 0x3F) * 8);
    var a3 = alpha; a3.skipBits(((chunk0 >> 24) & 0x3F) * 8);
    var a4 = alpha; a4.skipBits(((chunk0 >> 18) & 0x3F) * 8);
    var a5 = alpha; a5.skipBits(((chunk0 >> 12) & 0x3F) * 8);
    var a6 = alpha; a6.skipBits(((chunk0 >>  6) & 0x3F) * 8);
    var a7 = alpha; a7.skipBits(((chunk0       ) & 0x3F) * 8);
    val expected0 =
          (a0.preloadUint(8) << 56)
        | (a1.preloadUint(8) << 48)
        | (a2.preloadUint(8) << 40)
        | (a3.preloadUint(8) << 32)
        | (a4.preloadUint(8) << 24)
        | (a5.preloadUint(8) << 16)
        | (a6.preloadUint(8) <<  8)
        |  a7.preloadUint(8);
    if (input.loadUint(64) != expected0) { return false; }
    // Chunk 1: bottom 48 bits.
    val chunk1 = hash96 & 0xFFFFFFFFFFFF;
    var b0 = alpha; b0.skipBits(((chunk1 >> 42) & 0x3F) * 8);
    var b1 = alpha; b1.skipBits(((chunk1 >> 36) & 0x3F) * 8);
    var b2 = alpha; b2.skipBits(((chunk1 >> 30) & 0x3F) * 8);
    var b3 = alpha; b3.skipBits(((chunk1 >> 24) & 0x3F) * 8);
    var b4 = alpha; b4.skipBits(((chunk1 >> 18) & 0x3F) * 8);
    var b5 = alpha; b5.skipBits(((chunk1 >> 12) & 0x3F) * 8);
    var b6 = alpha; b6.skipBits(((chunk1 >>  6) & 0x3F) * 8);
    var b7 = alpha; b7.skipBits(((chunk1       ) & 0x3F) * 8);
    val expected1 =
          (b0.preloadUint(8) << 56)
        | (b1.preloadUint(8) << 48)
        | (b2.preloadUint(8) << 40)
        | (b3.preloadUint(8) << 32)
        | (b4.preloadUint(8) << 24)
        | (b5.preloadUint(8) << 16)
        | (b6.preloadUint(8) <<  8)
        |  b7.preloadUint(8);
    return input.loadUint(64) == expected1;
}

// ─── Post-ACCEPT: full 256-bit check (V10, 48-bit chunks) ────────────────
// Verifies every byte of the 43-char `challenge` against base64url(bodyHash).
// 5 full 48-bit chunks (40 chars) + 16 trailing bits (3 chars).
fun verifyB64uFull256(bodyHash: uint256, challenge: slice): bool {
    val alpha: slice = B64URL_ALPHABET;
    var input: slice = challenge;
    var shift: int = 208;
    repeat (5) {
        val chunk = (bodyHash >> shift) & 0xFFFFFFFFFFFF;
        var a0 = alpha; a0.skipBits(((chunk >> 42) & 0x3F) * 8);
        var a1 = alpha; a1.skipBits(((chunk >> 36) & 0x3F) * 8);
        var a2 = alpha; a2.skipBits(((chunk >> 30) & 0x3F) * 8);
        var a3 = alpha; a3.skipBits(((chunk >> 24) & 0x3F) * 8);
        var a4 = alpha; a4.skipBits(((chunk >> 18) & 0x3F) * 8);
        var a5 = alpha; a5.skipBits(((chunk >> 12) & 0x3F) * 8);
        var a6 = alpha; a6.skipBits(((chunk >>  6) & 0x3F) * 8);
        var a7 = alpha; a7.skipBits(((chunk       ) & 0x3F) * 8);
        val expected =
              (a0.preloadUint(8) << 56)
            | (a1.preloadUint(8) << 48)
            | (a2.preloadUint(8) << 40)
            | (a3.preloadUint(8) << 32)
            | (a4.preloadUint(8) << 24)
            | (a5.preloadUint(8) << 16)
            | (a6.preloadUint(8) <<  8)
            |  a7.preloadUint(8);
        if (input.loadUint(64) != expected) { return false; }
        shift -= 48;
    }
    val last16 = bodyHash & 0xFFFF;
    var t0 = alpha; t0.skipBits((((last16 >> 10) & 0x3F)) * 8);
    var t1 = alpha; t1.skipBits((((last16 >>  4) & 0x3F)) * 8);
    var t2 = alpha; t2.skipBits((((last16 & 0xF) << 2)) * 8);
    val expectedTail =
          (t0.preloadUint(8) << 16)
        | (t1.preloadUint(8) <<  8)
        |  t2.preloadUint(8);
    return input.loadUint(24) == expectedTail;
}
