import "@acton/testing/expect"
import "@acton/testing/assert"
import "@acton/io"
import "@stdlib/gas-payments"

// ──────────────────────────────────────────────────────────────────────────
// On-chain base64url encode/decode for binding a 32-byte cell hash to the
// `challenge` field of a WebAuthn clientDataJSON.
//
// The wallet flow:
//   off-chain:  challenge_value = base64url( cell.hash(body) )
//               that string is embedded literally in clientDataJSON,
//               which is then signed by the passkey.
//   on-chain:   contract receives the 43-char `challenge` slice (ref[1] of the
//               5-cell layout) and the body cell (ref[3]). It must check that
//               base64url(cell.hash(body)) == challenge slice, i.e. that the
//               passkey-signed challenge actually commits to this body.
//
// We benchmark two equivalent strategies:
//   Variant A — encode the 256-bit hash on-chain to 43 ASCII bytes,
//               then compare that slice to the challenge slice.
//   Variant B — decode the 43 ASCII bytes on-chain to a 256-bit int,
//               then compare that int to cell.hash(body).
// Both produce the same boolean answer; we measure gas to choose.
// ──────────────────────────────────────────────────────────────────────────

// "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
const B64URL_ALPHABET: slice =
    "4142434445464748494a4b4c4d4e4f505152535455565758595a6162636465666768696a6b6c6d6e6f707172737475767778797a303132333435363738392d5f"
        .hexToSlice();

// ─── Variant A: encode 32 bytes (uint256) → 43-byte ASCII slice ──────────

@inline
fun b64urlCharFromAlphabet(v: int): int {
    var s: slice = B64URL_ALPHABET;
    s.skipBits(v * 8);
    return s.preloadUint(8);
}

fun b64urlEncode32(hash: uint256): slice {
    var b: builder = beginCell();
    var i: int = 0;
    // 42 full 6-bit groups, picked from the most significant bits.
    while (i < 42) {
        val shift = 250 - i * 6;          // 250, 244, ..., 4
        val v = (hash >> shift) & 0x3F;
        b = b.storeUint(b64urlCharFromAlphabet(v), 8);
        i += 1;
    }
    // Final group: only the bottom 4 bits of `hash`, left-aligned in a 6-bit cell.
    val last = (hash & 0xF) << 2;
    b = b.storeUint(b64urlCharFromAlphabet(last), 8);
    return b.toSlice();
}

// ─── Variant B: decode 43-byte ASCII slice → uint256 ─────────────────────

@inline
fun b64urlValueOfChar(c: int): int {
    // 'A'..'Z' -> 0..25
    if ((c >= 0x41) && (c <= 0x5A)) { return c - 0x41; }
    // 'a'..'z' -> 26..51
    if ((c >= 0x61) && (c <= 0x7A)) { return c - 0x61 + 26; }
    // '0'..'9' -> 52..61
    if ((c >= 0x30) && (c <= 0x39)) { return c - 0x30 + 52; }
    if (c == 0x2D) { return 62; }   // '-'
    if (c == 0x5F) { return 63; }   // '_'
    throw 0xb64;                     // not a valid base64url char
}

fun b64urlDecode43To32(input: slice): uint256 {
    var s: slice = input;
    var acc: int = 0;
    var i: int = 0;
    // First 42 chars contribute 6 bits each → 252 bits, well within uint256.
    while (i < 42) {
        val c = s.loadUint(8);
        acc = (acc << 6) | b64urlValueOfChar(c);
        i += 1;
    }
    // The 43rd char encodes only 4 useful high bits (the bottom 2 bits are
    // b64 zero-padding). Shift acc left by 4 and merge those 4 bits.
    val last = s.loadUint(8);
    return (acc << 4) | (b64urlValueOfChar(last) >> 2);
}

// ─── Variant C1: fixed 43-digit radix-64 number, padded at the front ─────
//
// This is not byte-compatible RFC base64url. It encodes the 256-bit integer
// as a fixed-width base64url number:
//   00 || hash[255:0]  -> 43 chars
// That removes the special trailing pad-bit case: every char contributes a
// full base64 digit, and decoding is just `acc = (acc << 6) | digit`.

fun b64urlEncodeRadix64_43(hash: uint256): slice {
    var b: builder = beginCell();
    var shift: int = 252;
    repeat (43) {
        val v = (hash >> shift) & 0x3F;
        b = b.storeUint(b64urlCharFromAlphabet(v), 8);
        shift -= 6;
    }
    return b.toSlice();
}

fun b64urlDecodeRadix64_43To32(input: slice): uint256 {
    var s: slice = input;
    val first = b64urlValueOfChar(s.loadUint(8));
    if (first > 15) { throw 0xb65; }

    var acc: int = first;
    repeat (42) {
        acc = (acc << 6) | b64urlValueOfChar(s.loadUint(8));
    }
    return acc;
}

// ─── Variant C2: four independently padded uint64 words, 44 chars ───────
//
//   00 || w0  00 || w1  00 || w2  00 || w3
//
// Each uint64 is encoded as 11 base64url digits. This costs one extra char
// versus C1, but every block stays inside a 64-bit word boundary.

fun b64urlEncodePaddedWords44(hash: uint256): slice {
    var b: builder = beginCell();
    var wordShift: int = 192;
    repeat (4) {
        val word = (hash >> wordShift) & 0xFFFFFFFFFFFFFFFF;
        var digitShift: int = 60;
        repeat (11) {
            val v = (word >> digitShift) & 0x3F;
            b = b.storeUint(b64urlCharFromAlphabet(v), 8);
            digitShift -= 6;
        }
        wordShift -= 64;
    }
    return b.toSlice();
}

fun b64urlDecodePaddedWords44To32(input: slice): uint256 {
    var s: slice = input;
    var acc: int = 0;
    repeat (4) {
        val first = b64urlValueOfChar(s.loadUint(8));
        if (first > 15) { throw 0xb66; }

        var word: int = first;
        repeat (10) {
            word = (word << 6) | b64urlValueOfChar(s.loadUint(8));
        }
        acc = (acc << 64) | word;
    }
    return acc;
}

// ─── Variant D: 114-bit hash prefix, exactly 19 base64url digits ─────────
//
// 114 = 19 * 6, so this truncation needs no pad bits at either end. It is
// just the fixed-width base64url representation of the top 114 hash bits.

fun b64urlEncodePrefix114(hash: uint256): slice {
    var b: builder = beginCell();
    var shift: int = 250;
    repeat (19) {
        val v = (hash >> shift) & 0x3F;
        b = b.storeUint(b64urlCharFromAlphabet(v), 8);
        shift -= 6;
    }
    return b.toSlice();
}

fun b64urlDecodePrefix114(input: slice): int {
    var s: slice = input;
    var acc: int = 0;
    repeat (19) {
        acc = (acc << 6) | b64urlValueOfChar(s.loadUint(8));
    }
    return acc;
}

// ──────────────────────────────────────────────────────────────────────────
// Test vector. The clientDataJSON we already use in passkey.test.tolk binds
// challenge = base64url("4a4b4c…5e5f"). We reuse those 32 bytes as a "fake"
// cell hash to exercise the encoder/decoder.
// ──────────────────────────────────────────────────────────────────────────

const HASH32_HEX = "4a4b4c4d4e4f50515253545556575859505152535455565758595a5b5c5d5e5f";
const EXPECTED_B64U_HEX = "536b744d545535505546465355315256566c645957564252556c4e5556565a5857466c6157317864586c38";
const EXPECTED_RADIX64_43_HEX = "45704c5445314f54314252556c4e5556565a5857466c5155564a54564656575631685a576c746358563566";
const EXPECTED_PADDED_WORDS44_HEX = "45704c5445314f54314252464a54564656575631685a464252556c4e5556565a5846685a576c746358563566";
const EXPECTED_PREFIX114_HEX = "536b744d545535505546465355315256566c64";

fun loadHash32(): uint256 {
    var s: slice = HASH32_HEX.hexToSlice();
    return s.loadUint(256);
}

// ─── Correctness ──────────────────────────────────────────────────────────

get fun `test b64url encode produces expected 43-char string`() {
    val hash = loadHash32();
    val encoded: slice = b64urlEncode32(hash);
    val expected: slice = EXPECTED_B64U_HEX.hexToSlice();
    // Slice equality on data bits.
    expect(encoded.bitsHash()).toEqual(expected.bitsHash());
}

get fun `test b64url decode reverses the encoding`() {
    val expected: slice = EXPECTED_B64U_HEX.hexToSlice();
    val decoded: uint256 = b64urlDecode43To32(expected);
    expect(decoded).toEqual(loadHash32());
}

get fun `test encode . decode == identity over a different hash`() {
    // Different 32-byte hash to make sure we're not memorising the table.
    var s: slice = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20".hexToSlice();
    val hash = s.loadUint(256);
    val enc = b64urlEncode32(hash);
    val dec = b64urlDecode43To32(enc);
    expect(dec).toEqual(hash);
}

get fun `test padded radix64 43-char format is correct`() {
    val hash = loadHash32();
    val expected: slice = EXPECTED_RADIX64_43_HEX.hexToSlice();
    val encoded = b64urlEncodeRadix64_43(hash);
    val decoded = b64urlDecodeRadix64_43To32(expected);

    expect(encoded.bitsHash()).toEqual(expected.bitsHash());
    expect(decoded).toEqual(hash);
}

get fun `test padded uint64 words 44-char format is correct`() {
    val hash = loadHash32();
    val expected: slice = EXPECTED_PADDED_WORDS44_HEX.hexToSlice();
    val encoded = b64urlEncodePaddedWords44(hash);
    val decoded = b64urlDecodePaddedWords44To32(expected);

    expect(encoded.bitsHash()).toEqual(expected.bitsHash());
    expect(decoded).toEqual(hash);
}

get fun `test 114-bit prefix format is correct`() {
    val hash = loadHash32();
    val expected: slice = EXPECTED_PREFIX114_HEX.hexToSlice();
    val encoded = b64urlEncodePrefix114(hash);
    val decoded = b64urlDecodePrefix114(expected);

    expect(encoded.bitsHash()).toEqual(expected.bitsHash());
    expect(decoded).toEqual(hash >> 142);
}

// ─── Gas cost ─────────────────────────────────────────────────────────────
//
// Last measurement on this machine (debug build of acton 0.3.2):
//   Variant A (encode + slice compare) ≈ 21989 gas
//   Variant B (decode + int compare)   ≈ 25849 gas
//
// Variant A is ~15% cheaper, so the contract should prefer encoding the body
// hash on-chain and slice-comparing against ref[1].
//
// The tests below pin a slack budget around the measured numbers so a
// regression (e.g. a more expensive alphabet lookup) shows up loudly.

get fun `test gas:variant A — encode 32 bytes + compare slices stays under budget`() {
    val hash = loadHash32();
    val expected: slice = EXPECTED_B64U_HEX.hexToSlice();
    val ok = Assert.consumesLessThan(fun() {
        val encoded: slice = b64urlEncode32(hash);
        return encoded.bitsHash() == expected.bitsHash();
    }, 25000);
    expect(ok).toBeTrue();
}

get fun `test gas:variant B — decode 43 chars + compare ints stays under budget`() {
    val hash = loadHash32();
    val challenge: slice = EXPECTED_B64U_HEX.hexToSlice();
    val ok = Assert.consumesLessThan(fun() {
        val decoded: uint256 = b64urlDecode43To32(challenge);
        return decoded == hash;
    }, 30000);
    expect(ok).toBeTrue();
}

get fun `test gas:padded variants — decode base64 digits + compare ints`() {
    val hash = loadHash32();
    val radix43: slice = EXPECTED_RADIX64_43_HEX.hexToSlice();
    val words44: slice = EXPECTED_PADDED_WORDS44_HEX.hexToSlice();

    val okRadix43 = Assert.consumesLessThan(fun() {
        return b64urlDecodeRadix64_43To32(radix43) == hash;
    }, 30000);
    val okWords44 = Assert.consumesLessThan(fun() {
        return b64urlDecodePaddedWords44To32(words44) == hash;
    }, 32000);

    expect(okRadix43).toBeTrue();
    expect(okWords44).toBeTrue();
}

get fun `test gas:padded variants — encode padded hash + compare base64`() {
    val hash = loadHash32();
    val radix43: slice = EXPECTED_RADIX64_43_HEX.hexToSlice();
    val words44: slice = EXPECTED_PADDED_WORDS44_HEX.hexToSlice();

    val okRadix43 = Assert.consumesLessThan(fun() {
        return b64urlEncodeRadix64_43(hash).bitsEqual(radix43);
    }, 25000);
    val okWords44 = Assert.consumesLessThan(fun() {
        return b64urlEncodePaddedWords44(hash).bitsEqual(words44);
    }, 27000);

    expect(okRadix43).toBeTrue();
    expect(okWords44).toBeTrue();
}

get fun `test gas:114-bit prefix — decode and encode`() {
    val hash = loadHash32();
    val challenge: slice = EXPECTED_PREFIX114_HEX.hexToSlice();
    val hash114 = hash >> 142;

    val okDecode = Assert.consumesLessThan(fun() {
        return b64urlDecodePrefix114(challenge) == hash114;
    }, 14000);
    val okEncode = Assert.consumesLessThan(fun() {
        return b64urlEncodePrefix114(hash).bitsEqual(challenge);
    }, 10000);

    expect(okDecode).toBeTrue();
    expect(okEncode).toBeTrue();
}

// Print both numbers in the same run so the comparison is in the test output
// every time without diffing against the comment above.
get fun `test gas:print numbers for both variants side by side`() {
    val hash = loadHash32();
    val expected: slice = EXPECTED_B64U_HEX.hexToSlice();
    val radix43: slice = EXPECTED_RADIX64_43_HEX.hexToSlice();
    val words44: slice = EXPECTED_PADDED_WORDS44_HEX.hexToSlice();
    val prefix114: slice = EXPECTED_PREFIX114_HEX.hexToSlice();
    val hash114 = hash >> 142;

    val a0 = getGasConsumedAtTheMoment();
    val encoded: slice = b64urlEncode32(hash);
    val okA = encoded.bitsHash() == expected.bitsHash();
    val a1 = getGasConsumedAtTheMoment();

    val b0 = getGasConsumedAtTheMoment();
    val decoded: uint256 = b64urlDecode43To32(expected);
    val okB = decoded == hash;
    val b1 = getGasConsumedAtTheMoment();

    val c0 = getGasConsumedAtTheMoment();
    val decodedRadix43: uint256 = b64urlDecodeRadix64_43To32(radix43);
    val okC = decodedRadix43 == hash;
    val c1 = getGasConsumedAtTheMoment();

    val d0 = getGasConsumedAtTheMoment();
    val encodedRadix43: slice = b64urlEncodeRadix64_43(hash);
    val okD = encodedRadix43.bitsEqual(radix43);
    val d1 = getGasConsumedAtTheMoment();

    val e0 = getGasConsumedAtTheMoment();
    val decodedWords44: uint256 = b64urlDecodePaddedWords44To32(words44);
    val okE = decodedWords44 == hash;
    val e1 = getGasConsumedAtTheMoment();

    val f0 = getGasConsumedAtTheMoment();
    val encodedWords44: slice = b64urlEncodePaddedWords44(hash);
    val okF = encodedWords44.bitsEqual(words44);
    val f1 = getGasConsumedAtTheMoment();

    val g0 = getGasConsumedAtTheMoment();
    val decodedPrefix114: int = b64urlDecodePrefix114(prefix114);
    val okG = decodedPrefix114 == hash114;
    val g1 = getGasConsumedAtTheMoment();

    val h0 = getGasConsumedAtTheMoment();
    val encodedPrefix114: slice = b64urlEncodePrefix114(hash);
    val okH = encodedPrefix114.bitsEqual(prefix114);
    val h1 = getGasConsumedAtTheMoment();

    expect(okA).toBeTrue();
    expect(okB).toBeTrue();
    expect(okC).toBeTrue();
    expect(okD).toBeTrue();
    expect(okE).toBeTrue();
    expect(okF).toBeTrue();
    expect(okG).toBeTrue();
    expect(okH).toBeTrue();
    println("variant A (RFC encode + slice hash cmp)    : ", a1 - a0 - 26, " gas");
    println("variant B (RFC decode + int compare)      : ", b1 - b0 - 26, " gas");
    println("variant C1 (43 radix decode + int compare): ", c1 - c0 - 26, " gas");
    println("variant C1 (43 radix encode + bitsEqual)  : ", d1 - d0 - 26, " gas");
    println("variant C2 (44 words decode + int compare): ", e1 - e0 - 26, " gas");
    println("variant C2 (44 words encode + bitsEqual)  : ", f1 - f0 - 26, " gas");
    println("variant D  (114-bit decode + int compare) : ", g1 - g0 - 26, " gas");
    println("variant D  (114-bit encode + bitsEqual)   : ", h1 - h0 - 26, " gas");
}
