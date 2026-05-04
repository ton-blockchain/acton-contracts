import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/io"
import "@acton/testing/expect"
import "@acton/types/big_array"
import "../contracts/messages"
import "../contracts/passkey-verify"
import "../contracts/storage"
import "../wrappers/PasskeyWallet.gen"
import "../wrappers/utils"

// ──────────────────────────────────────────────────────────────────────────
// Test vector — produced by `node scripts/gen-wallet-vector.mjs` and pinned
// via scripts/wallet-vector.{key.pem,json}. Re-run with --regenerate to roll
// a fresh keypair, then update the constants below.
// ──────────────────────────────────────────────────────────────────────────

// Storage init values:
const PUBKEY_COMPRESSED  = "02a1cc76cf544c0a06daf6712e755eac9cb657b8fc2b6c7e818bf58ff40a2374ce";
const RP_ID_HASH         = "49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763";
const AUTH_TAIL          = "0500000001"; // flags=UP|UV, signCount=1
const CDJ_PREFIX_HEX     = "7b2274797065223a22776562617574686e2e676574222c226368616c6c656e6765223a22";
const CDJ_SUFFIX_HEX     = "222c226f726967696e223a22687474703a2f2f6c6f63616c686f73743a3532323631222c2263726f73734f726967696e223a66616c73657d";
const CDJ_PREFIX_BYTES   = 36;

// External-message values:
const SIGNATURE_RAW      = "19ec3f46fa12b2d61af5cfcc7a7f032fcd2c13bd6e065576ed924ef23aa34596e5226284ef4d5c1c29e53a172d7af3974d66fcdcac2ee4f89463030dde19ccda";
const CDJ_CHALLENGE_43   = "395774314c507547533661707a30595565645f77742d75384b58643635793459674464446d514978503863";

// v4r2-compatible payload fields (must reproduce gen-wallet-vector.mjs):
const PAYLOAD_SUBWALLET_ID = 698983191;  // v4r2 default wallet id
const PAYLOAD_SEQNO        = 0;
const PAYLOAD_VALID_UNTIL  = 4102444800; // 2100-01-01
const PAYLOAD_OP           = 0;
const PAYLOAD_SEND_MODE    = 3;
const RECEIVER_HASH      = 0;            // workchain 0, all-zero hash
const FORWARD_VALUE_NANO = 1000000;      // 0.001 TON
const EXPECTED_PAYLOAD_HASH: uint256 = 0xf56b752cfb864ba6a9cf461479dff0b7ebbc29777ae72e188037439902313fc7;

// Build the outgoing-message cell that the payload wraps. Its construction must
// match @ton/core's `beginCell().storeUint(0b01_0000, 6).storeAddress(...)
// .storeCoins(...).storeUint(0, ...)` byte-for-byte so the resulting cell
// hash matches the off-chain PAYLOAD_HASH.
fun buildOutMsg(): cell {
    val receiver: address = beginCell()
        .storeUint(0b100, 3)         // addr_std prefix + no anycast
        .storeInt(0, 8)              // workchain 0
        .storeUint(RECEIVER_HASH, 256)
        .toSlice() as address;
    return beginCell()
        .storeUint(0b01_0000, 6)     // int_msg_info, ihr_disabled=1, bounce=0, bounced=0, src=00
        .storeAddress(receiver)
        .storeCoins(FORWARD_VALUE_NANO)
        // currency_collection (1) + ihr_fee VarUInt16-empty (4) + fwd_fee VarUInt16-empty (4)
        // + created_lt (64) + created_at (32) + init? (1) + body inline (1) = 107 bits
        .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
        .endCell();
}

fun buildPayload(): cell {
    return beginCell()
        .storeUint(PAYLOAD_SUBWALLET_ID, 32)
        .storeUint(PAYLOAD_VALID_UNTIL, 32)
        .storeUint(PAYLOAD_SEQNO, 32)
        .storeUint(PAYLOAD_OP, 8)
        .storeUint(PAYLOAD_SEND_MODE, 8)
        .storeRef(buildOutMsg())
        .endCell();
}

fun buildWebAuthnWitness(): cell {
    return beginCell()
        .storeSlice(AUTH_TAIL.hexToSlice())
        .storeUint(CDJ_PREFIX_BYTES, 8)
        .storeSlice(CDJ_PREFIX_HEX.hexToSlice())
        .storeSlice(CDJ_SUFFIX_HEX.hexToSlice())
        .endCell();
}

fun buildExternalRequest(): ExternalRequest {
    return ExternalRequest {
        signature: SIGNATURE_RAW.hexToSlice() as bits512,
        challenge: CDJ_CHALLENGE_43.hexToSlice() as bits344,
        webauthn: buildWebAuthnWitness(),
        payload: buildPayload().beginParse(),
    };
}

fun buildStorage(): Storage {
    val pubkey   = PUBKEY_COMPRESSED.hexToSlice() as bits264;
    return Storage {
        seqno: 0,
        subwalletId: PAYLOAD_SUBWALLET_ID,
        pubkey,
    };
}

// ─── Sanity: the off-chain PAYLOAD_HASH must equal what TVM computes ─────
get fun `test wallet: payload cell hash matches off-chain vector`() {
    expect(buildPayload().hash()).toEqual(EXPECTED_PAYLOAD_HASH);
}

// ─── Sanity: verifyB64uPrefix114 accepts our test vector ─────────────────
get fun `test wallet: prefix114 verify accepts the precomputed vector`() {
    val payloadHash = EXPECTED_PAYLOAD_HASH;
    val challenge = CDJ_CHALLENGE_43.hexToSlice();
    val ok = verifyB64uPrefix114(payloadHash, challenge);
    expect(ok).toBeTrue();
}

// ─── Sanity: round-trip ExternalRequest serialization ────────────────────
get fun `test wallet: ExternalRequest fromSlice round-trips`() {
    val ext = buildExternalRequest();
    val slice = ext.toCell().beginParse();
    val req = ExternalRequest.fromSlice(slice);
    val payloadSlice = req.payload as slice;
    expect(payloadSlice.hash()).toEqual(EXPECTED_PAYLOAD_HASH);
    expect(req.webauthn.hash()).toEqual(buildWebAuthnWitness().hash());
    val challengeSlice = req.challenge as slice;
    expect(challengeSlice.bitsHash())
        .toEqual(CDJ_CHALLENGE_43.hexToSlice().bitsHash());
}

// ─── Sanity: full pre-ACCEPT verification chain ──────────────────────────
get fun `test wallet: full pre-ACCEPT verification (HASHEXT + P256) accepts vector`() {
    val ext = buildExternalRequest();
    var inBodyMut = ext.toCell().beginParse();
    val storage = buildStorage();

    val signatureSlice: slice = inBodyMut.loadBits(512);
    val challengeSlice: slice = inBodyMut.loadBits(344);
    var webauthn = inBodyMut.loadRef().beginParse();
    val payloadHash = inBodyMut.hash();

    expect(verifyB64uPrefix114(payloadHash, challengeSlice)).toBeTrue();

    val authTail = webauthn.loadBits(40);
    val cdjPrefixBytes = webauthn.loadUint(8);
    val cdjPrefix = webauthn.loadBits(cdjPrefixBytes * 8);
    val cdjHash = sha256ThreeSlices(
        cdjPrefix,
        challengeSlice,
        webauthn,
    );
    val signedMessage = beginCell()
        .storeSlice(RP_ID_HASH.hexToSlice())
        .storeSlice(authTail)
        .storeUint(cdjHash, 256)
        .toSlice();
    val sigOk = p256ChkSignS(signedMessage, signatureSlice, storage.pubkey as slice);
    expect(sigOk).toBeTrue();
}

fun deployWallet(): PasskeyWallet {
    val deployer = testing.treasury("deployer");
    val wallet = PasskeyWallet.fromStorage(buildStorage());
    val deployResult = wallet.deploy(deployer.address, { value: ton("5"), bounce: false });
    expect(deployResult).toHaveSuccessfulDeploy({ to: wallet.address });
    return wallet;
}

// ─── End-to-end: deploy + sign + verify ──────────────────────────────────
get fun `test wallet: passkey-signed external is accepted, seqno bumps`() {
    val wallet = deployWallet();
    expect(wallet.seqno()).toEqual(0);
    expect(wallet.getSubwalletId()).toEqual(PAYLOAD_SUBWALLET_ID);
    expect(wallet.pubkey().bitsHash()).toEqual(PUBKEY_COMPRESSED.hexToSlice().bitsHash());

    val ext = buildExternalRequest();
    val receipt = wallet.sendPasskeyExternal(ext);
    if (receipt == null) {
        println("[test] sendPasskeyExternal returned null");
    } else {
        println("[test] sendPasskeyExternal succeeded, txs:", receipt.size());
        println("[test] wallet external tx gas:", receipt.at(0).gasUsed);
    }
    expect(receipt).toNotEqual(null);
    expect(wallet.seqno()).toEqual(1);
}

// ─── Replay protection: the same external is rejected on a second send ──
get fun `test wallet: replay of the same external is rejected`() {
    val wallet = deployWallet();

    val ext = buildExternalRequest();
    val first = wallet.sendPasskeyExternal(ext);
    expect(first).toNotEqual(null);
    expect(wallet.seqno()).toEqual(1);

    // Re-sending the same external: post-ACCEPT the payload seqno=0 vs
    // storage.seqno=1 check throws ERROR_INVALID_SEQNO. seqno must NOT
    // advance again.
    wallet.sendPasskeyExternal(ext);
    expect(wallet.seqno()).toEqual(1);
}
