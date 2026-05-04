import "@stdlib/gas-payments"
import "errors"
import "messages"
import "passkey-verify"
import "storage"

const LOCALHOST_RP_ID_HASH: uint256 = 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763;

contract PasskeyWallet {
    author: "Acton passkey wallet (v0.1)"
    version: "0.1.0"
    description: "P-256 / WebAuthn-backed wallet. External-only by design."
    incomingMessages: NoIncomingMessages
    storage: Storage
}

// We don't accept any internal messages by design (per spec). The Acton
// framework requires `incomingMessages`, so this is a never-sent dummy.
struct (0xFFFFFFFF) NoIncomingMessages { }

@on_bounced_policy("manual")
fun onInternalMessage(_in: InMessage) {
    // Silently accept TON deposits / ignore unknown bodies. No state mutation.
}

fun onExternalMessage(inBody: slice) {
    // External layout: ExternalRequest = signature || challenge || webauthn ref || v4r2-compatible payload.
    // Payload stays last as RemainingBitsAndRefs, so v4r2 payload builders can
    // be reused off-chain after inserting the WebAuthn wrapper fields.
    val req = ExternalRequest.fromSlice(inBody);
    val signatureSlice: slice = req.signature as slice;
    val challengeSlice: slice = req.challenge as slice;
    // webauthn cell layout (variable-length cdjPrefix prevents a clean struct):
    //   authTail:bits40 cdjPrefixBytes:uint8 cdjPrefix:bits(prefixBytes*8) cdjSuffix:remaining
    var webauthnSlice = req.webauthn.beginParse();
    val authTailSlice: slice = webauthnSlice.loadBits(40);
    val cdjPrefixBits = webauthnSlice.loadUint(8) << 3;
    var payloadSlice: slice = req.payload as slice;

    var storage = Storage.load();

    val payloadHash: uint256 = payloadSlice.hash();

    assert (
        verifyB64uPrefix114(payloadHash, challengeSlice)
    ) throw ERROR_CHALLENGE_BINDING_PRE;

    val payloadSubwalletId = payloadSlice.loadUint(32);
    val payloadValidUntil  = payloadSlice.loadUint(32);
    val payloadSeqno       = payloadSlice.loadUint(32);
    assert (payloadSubwalletId == storage.subwalletId) throw ERROR_INVALID_SUBWALLET;
    assert (payloadSeqno == storage.seqno) throw ERROR_INVALID_SEQNO;
    assert (payloadValidUntil > blockchain.now()) throw ERROR_EXPIRED;

    val cdjPrefixSlice = webauthnSlice.loadBits(cdjPrefixBits);
    val cdjHash: uint256 = sha256ThreeSlices(
        cdjPrefixSlice,
        challengeSlice,
        webauthnSlice,
    );
    val signedMessage: slice = beginCell()
        .storeUint(LOCALHOST_RP_ID_HASH, 256)
        .storeSlice(authTailSlice)
        .storeUint(cdjHash, 256)
        .toSlice();
    assert (
        p256ChkSignS(signedMessage, signatureSlice, storage.pubkey as slice)
    ) throw ERROR_INVALID_SIGNATURE;

    // --- ACCEPT ---
    acceptExternalMessage();

    // --- Post-ACCEPT: full 256-bit binding check ---
    // The 114-bit prefix is only the pre-ACCEPT spam filter. Re-verifying
    // all 43 chars against payloadHash slams that door. ~11650 gas; failure
    // throws and the wallet only loses the gas already spent on this
    // message (sub-cent), no funds.
    assert (
        verifyB64uFull256(payloadHash, challengeSlice)
    ) throw ERROR_CHALLENGE_BINDING_FULL;

    // Bump seqno BEFORE the outgoing-action so replay protection commits
    // even if the outgoing message reverts later in the transaction.
    storage.seqno = (storage.seqno + 1) as uint32;
    storage.save();
    commitContractDataAndActions();

    // --- Send the requested v4r2 op=0 messages ---
    val op = payloadSlice.loadUint(8);
    assert (op == 0) throw ERROR_INVALID_BODY;
    while (payloadSlice.remainingRefsCount() != 0) {
        val sendMode = payloadSlice.loadUint(8);
        val outMsg = payloadSlice.loadRef();
        sendRawMessage(outMsg, sendMode);
    }
}

// --- Get-methods ---

get fun seqno(): int {
    return Storage.load().seqno;
}

get fun get_subwallet_id(): int {
    return Storage.load().subwalletId;
}

get fun pubkey(): slice {
    return Storage.load().pubkey as slice;
}

get fun rpIdHash(): slice {
    return beginCell().storeUint(LOCALHOST_RP_ID_HASH, 256).toSlice();
}
