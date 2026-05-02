import "@acton/io"
import "@stdlib/gas-payments"
import "errors"
import "messages"
import "passkey-verify"
import "storage"

contract PasskeyWallet {
    author: "Acton passkey wallet (v0.1)"
    version: "0.1.0"
    description: "P-256 / WebAuthn-backed wallet. External-only — no internal logic."
    incomingMessages: NoIncomingMessages
    storage: Storage
}

// We don't accept any internal messages by design (see user spec). The Acton
// framework requires `incomingMessages` to be set, so this is a never-sent
// dummy struct; the internal handler below silently drops anything that
// arrives (e.g., plain TON top-ups bounce or stay).
struct (0xFFFFFFFF) NoIncomingMessages { }

@on_bounced_policy("manual")
fun onInternalMessage(in: InMessage) {
    // Silently accept TON deposits / ignore unknown bodies. No state mutation.
}

fun onExternalMessage(inBody: slice) {
    println("[passkey] onExternalMessage start");
    val req = ExternalRequest.fromSlice(inBody);
    println("[passkey] parsed external request");
    var storage = lazy Storage.load();
    println("[passkey] storage loaded");

    val bodyHash: uint256 = req.body.hash();
    val challengeSlice: slice = (req.challenge as slice);
    println("[passkey] body hash:", bodyHash);

    // ─── Pre-ACCEPT (must fit in TVM gas-credit, default 10000) ──────────
    // 1. Cheap binding: top 96 bits of bodyHash must base64url-encode to the
    //    first 16 chars of the on-chain challenge slice. ~5143 gas.
    val pre = verifyB64uPrefix96(bodyHash, challengeSlice);
    println("[passkey] prefix check:", pre);
    assert (pre) throw ERROR_CHALLENGE_BINDING_PRE;

    // 2. Reconstruct sha256(clientDataJSON) over prefix‖challenge‖suffix.
    val cdjHash: uint256 = sha256ThreeSlices(
        storage.cdjPrefix.beginParse(),
        challengeSlice,
        storage.cdjSuffix.beginParse(),
    );

    // 3. Build the WebAuthn signed message (authData ‖ sha256(cdj)) and
    //    ECDSA-P256-verify the user's signature. ~3526 gas.
    val signedMessage: slice = beginCell()
        .storeSlice(storage.authData as slice)
        .storeUint(cdjHash, 256)
        .endCell()
        .beginParse();
    assert (
        p256ChkSignS(signedMessage, req.signature as slice, storage.pubkey as slice)
    ) throw ERROR_INVALID_SIGNATURE;

    // ─── ACCEPT ──────────────────────────────────────────────────────────
    // Pre-ACCEPT path consumed roughly 9.8k gas; we now switch to the
    // wallet's own gas budget for the rest.
    acceptExternalMessage();

    // ─── Post-ACCEPT: full 256-bit binding check ─────────────────────────
    // The 96-bit prefix could in principle collide (2^48 work). Re-verifying
    // the remaining 27 chars of the challenge against bodyHash slams that
    // door. ~14750 gas; failure throws and the wallet only loses the gas it
    // already spent on this message (sub-cent), nothing else.
    assert (
        verifyB64uFull256(bodyHash, challengeSlice)
    ) throw ERROR_CHALLENGE_BINDING_FULL;

    // ─── Body parsing + replay/expiry checks ─────────────────────────────
    val body = Body.fromCell(req.body);
    assert (body.seqno == storage.seqno) throw ERROR_INVALID_SEQNO;
    assert (body.validUntil > blockchain.now()) throw ERROR_EXPIRED;

    // Bump seqno BEFORE actions — ensures replay protection even if the
    // outgoing message reverts later in the transaction.
    storage.seqno = (storage.seqno + 1) as uint32;
    storage.save();
    commitContractDataAndActions();

    // ─── Send the requested message ──────────────────────────────────────
    sendRawMessage(body.outMsg, body.sendMode);
}

// ─── Get-methods ─────────────────────────────────────────────────────────

get fun seqno(): int {
    return Storage.load().seqno;
}

get fun pubkey(): slice {
    return Storage.load().pubkey as slice;
}

get fun authData(): slice {
    return Storage.load().authData as slice;
}
