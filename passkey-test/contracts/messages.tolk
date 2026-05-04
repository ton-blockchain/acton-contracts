// v4r2-compatible unsigned payload:
//   subwallet_id:uint32 valid_until:uint32 seqno:uint32 op:uint8
//   for op=0: repeated (mode:uint8, ref message) pairs.
//
// External-message body wraps the WebAuthn signature, b64url challenge bytes,
// WebAuthn witness data, and then this payload as RemainingBitsAndRefs.
// `webauthn` cell layout:
//   authTail:bits40 cdjPrefixBytes:uint8 cdjPrefix:bits(prefixBytes*8) cdjSuffix:remaining
// Keeping the payload last lets off-chain code reuse existing v4r2 payload builders.
struct ExternalRequest {
    signature: bits512    // raw r||s ECDSA-P256 signature (64 bytes)
    challenge: bits344    // base64url(cell.hash(payload)) = 43 ASCII chars
    webauthn: cell         // authTail || cdjPrefixBytes || cdjPrefix || cdjSuffix
    payload: RemainingBitsAndRefs
}
