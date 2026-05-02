import "@stdlib/gas-payments"
import "errors"
import "messages"
import "passkey-verify"
import "storage"

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
fun onInternalMessage(in: InMessage) {
    // Silently accept TON deposits / ignore unknown bodies. No state mutation.
}

fun onExternalMessage(inBody: slice) {
    val req = ExternalRequest.fromSlice(inBody);
    var storage = lazy Storage.load();

    val challengeSlice: slice = (req.challenge as slice);
    val bodyHash: uint256 = req.body.hash();

    assert (
        verifyB64uPrefix96(bodyHash, challengeSlice)
    ) throw ERROR_CHALLENGE_BINDING_PRE;

    var bodyHead = req.body.beginParse();
    val bodySeqno      = bodyHead.loadUint(32);
    val bodyValidUntil = bodyHead.loadUint(32);
    assert (bodySeqno == storage.seqno) throw ERROR_INVALID_SEQNO;
    assert (bodyValidUntil > blockchain.now()) throw ERROR_EXPIRED;

    val cdjHash: uint256 = sha256ThreeSlices(
        storage.cdjPrefix.beginParse(),
        challengeSlice,
        storage.cdjSuffix.beginParse(),
    );
    val signedMessage: slice = beginCell()
        .storeSlice(storage.authData as slice)
        .storeUint(cdjHash, 256)
        .endCell()
        .beginParse();
    assert (
        p256ChkSignS(signedMessage, req.signature as slice, storage.pubkey as slice)
    ) throw ERROR_INVALID_SIGNATURE;

    // --- Post-ACCEPT: full 256-bit binding check ---
    // The 96-bit prefix could in principle collide (2^48 work). Re-verifying
    // all 43 chars against bodyHash slams that door. ~14750 gas; failure
    // throws and the wallet only loses the gas already spent on this
    // message (sub-cent), no funds.
    assert (
        verifyB64uFull256(bodyHash, challengeSlice)
    ) throw ERROR_CHALLENGE_BINDING_FULL;

    // Bump seqno BEFORE the outgoing-action so replay protection commits
    // even if the outgoing message reverts later in the transaction.
    storage.seqno = (storage.seqno + 1) as uint32;
    storage.save();
    commitContractDataAndActions();

    // --- Send the requested message ---
    val body = Body.fromCell(req.body);
    sendRawMessage(body.outMsg, body.sendMode);
}

// --- Get-methods ---

get fun seqno(): int {
    return Storage.load().seqno;
}

get fun pubkey(): slice {
    return Storage.load().pubkey as slice;
}

get fun authData(): slice {
    return Storage.load().authData as slice;
}
