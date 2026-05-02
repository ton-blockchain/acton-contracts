import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "../contracts/messages"
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
const AUTH_DATA          = "49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000001";
const CDJ_PREFIX_HEX     = "7b2274797065223a22776562617574686e2e676574222c226368616c6c656e6765223a22";
const CDJ_SUFFIX_HEX     = "222c226f726967696e223a22687474703a2f2f6c6f63616c686f73743a3532323631222c2263726f73734f726967696e223a66616c73657d";

// External-message values:
const SIGNATURE_RAW      = "dc5d862d0ab453dbe64d609c6decc59fc8e64069c5098838e009791a2622d367a08d2795fc24ed49380c9c4a4a577b98015f43b14884e492ff150df9af297048";
const CDJ_CHALLENGE_43   = "486967444848306e5f755a37664c5271794d797171764a6167624f6433787961717755733059413747636b";

// Body fields (must reproduce the cell built by gen-wallet-vector.mjs):
const BODY_SEQNO         = 0;
const BODY_VALID_UNTIL   = 4102444800;   // 2100-01-01
const BODY_SEND_MODE     = 3;
const RECEIVER_HASH      = 0;            // workchain 0, all-zero hash
const FORWARD_VALUE_NANO = 1000000;      // 0.001 TON
const EXPECTED_BODY_HASH: uint256 = 0x1e28031c7d27fee67b7cb46ac8ccaaaaf25a81b39ddf1c9aab052cd1803b19c9;

// Build the outgoing-message cell that the body wraps. Its construction must
// match @ton/core's `beginCell().storeUint(0b01_0000, 6).storeAddress(...)
// .storeCoins(...).storeUint(0, ...)` byte-for-byte so the resulting cell
// hash matches the off-chain BODY_HASH.
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

fun buildBody(): cell {
    return beginCell()
        .storeUint(BODY_SEQNO, 32)
        .storeUint(BODY_VALID_UNTIL, 32)
        .storeUint(BODY_SEND_MODE, 8)
        .storeRef(buildOutMsg())
        .endCell();
}

fun buildExternalRequest(): cell {
    return beginCell()
        .storeSlice(SIGNATURE_RAW.hexToSlice())
        .storeSlice(CDJ_CHALLENGE_43.hexToSlice())
        .storeRef(buildBody())
        .endCell();
}

fun buildStorage(): Storage {
    val pubkey   = PUBKEY_COMPRESSED.hexToSlice() as bits264;
    val authData = AUTH_DATA.hexToSlice() as bits296;
    val prefix   = beginCell().storeSlice(CDJ_PREFIX_HEX.hexToSlice()).endCell();
    val suffix   = beginCell().storeSlice(CDJ_SUFFIX_HEX.hexToSlice()).endCell();
    return Storage {
        seqno: 0,
        pubkey,
        authData,
        cdjPrefix: prefix,
        cdjSuffix: suffix,
    };
}

// ─── Sanity: the off-chain BODY_HASH must equal what TVM computes ────────
get fun `test wallet: body cell hash matches off-chain vector`() {
    val body = buildBody();
    expect(body.hash()).toEqual(EXPECTED_BODY_HASH);
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

    val receipt = wallet.sendPasskeyExternal(buildExternalRequest());
    expect(receipt).toNotEqual(null);

    // The verification path ran end-to-end: seqno was bumped before the
    // outgoing send-action, so even if the synthetic outMsg can't be routed
    // by the sandbox we still see the increment.
    expect(wallet.seqno()).toEqual(1);
}

// ─── Replay protection: the same external is rejected on a second send ──
get fun `test wallet: replay of the same external is rejected`() {
    val wallet = deployWallet();

    val ext = buildExternalRequest();
    val first = wallet.sendPasskeyExternal(ext);
    expect(first).toNotEqual(null);
    expect(wallet.seqno()).toEqual(1);

    // Re-sending the same external: post-ACCEPT the body.seqno=0 vs
    // storage.seqno=1 check throws ERROR_INVALID_SEQNO. seqno must NOT
    // advance again.
    wallet.sendPasskeyExternal(ext);
    expect(wallet.seqno()).toEqual(1);
}
