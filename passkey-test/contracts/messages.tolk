// Body of a single passkey-signed operation. Its TVM cell hash is what the
// off-chain wallet feeds to `navigator.credentials.get` as `challenge`. The
// browser base64url-encodes those 32 bytes and embeds the result in
// clientDataJSON, which the passkey then signs.
//
// Adding/changing fields here changes cell.hash → invalidates outstanding
// signatures. Layout is intentionally tiny so the body cell is easy to inspect
// off-chain.
struct Body {
    seqno: uint32         // must match Storage.seqno
    validUntil: uint32    // unix seconds; rejected once blockchain.now() >= validUntil
    sendMode: uint8       // arg passed to send_raw_message
    outMsg: cell          // ref: serialized internal-message that the wallet should send
}

// External-message body wraps the WebAuthn signature, the b64url challenge bytes
// (i.e. ref[1] of the layout we benchmarked in b64url-fast.test.tolk), and the
// operation body. cdjPrefix and cdjSuffix come from contract storage, not from
// the external message.
struct ExternalRequest {
    signature: bits512    // raw r||s ECDSA-P256 signature (64 bytes)
    challenge: bits344    // base64url(cell.hash(body)) = 43 ASCII chars
    body: cell            // ref: the Body cell described above
}
