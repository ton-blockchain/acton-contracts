import "@stdlib/gas-payments"
import "credits"
import "complaints"
import "messages"
import "types"
import "utils"
import "@stdlib/tvm-lowlevel"


struct(0x654c5074) StakeSubmit {
    stakeAt: uint32;
    maxFactor: uint32;
    srcAddr: uint256;
    adnlAddr: uint256;
}

fun processNewStake(msg: NewStakeMessage): void {
    val srcWcAndHash = InMessage.source().getWorkchainAndHash();
    val storage = Storage.load();
    if ((storage.currectElections == null) || (srcWcAndHash.0 == -1)) {
        returnStake(InMessage.source(), msg.queryId, 0);
        return;
    }

    if (!isSliceSignatureValid(beginCell().storeAny(StakeSubmit {
        stakeAt: msg.stakeAt,
        maxFactor: msg.maxFactor,
        srcAddr: srcWcAndHash.1,
        adnlAddr: msg.adnlAddr,
    }).toSlice(), msg.signature.load() as slice, msg.validatorPubkey)) {
        // incorrect signature, return stake
        returnStake(InMessage.source(), msg.queryId, 1);
        return;
    }

    if (msg.maxFactor < 0x10000) {
        // factor must be >= 1. = 65536/65536
        returnStake(InMessage.source(), msg.queryId, 6);
        return;
    }

    var elect = storage.currectElections.load();
    var msgValue = InMessage.value() - ton("1"); // Deduct 1 ton for sending confirmation
    if ((msgValue << 12) < elect.totalStake) {
        // stake smaller than 1/4096 of the total accumulated stakes, return
        returnStake(InMessage.source(), msg.queryId, 2);
        return;
    }

    elect.totalStake += msgValue;
    if (msg.stakeAt != elect.electionsAt) {
        returnStake(InMessage.source(), msg.queryId, 3);
        return;
    }

    if (elect.isFinished) {
        returnStake(InMessage.source(), msg.queryId, 0);
        return;
    }

    var memberLookupRes = elect.members.get(msg.validatorPubkey);
    if (memberLookupRes.isFound) {
        val member = memberLookupRes.loadValue();
        msgValue += member.msgValue;
        memberLookupRes.isFound = (srcWcAndHash.1 != member.srcAddr);
    }

    if (memberLookupRes.isFound) {
        // can make stakes for a public key from one address only
        returnStake(InMessage.source(), msg.queryId, 4);
        return;
    }


    if (msgValue < elect.minStake) {
        returnStake(InMessage.source(), msg.queryId, 5);
        return;
    }

    assert (msgValue != 0) throw 44;
    // Actually we are "accepting" internal message here. It is equal to SETGASLIMIT *max gas limit*
    // in asm it is ACCEPT
    setGasLimitToMaximum();
    // Store stake in the dictionary
    elect.members.set(msg.validatorPubkey, MemberParams {
        msgValue,
        timestamp: blockchain.now(),
        maxFactor: msg.maxFactor,
        srcAddr: srcWcAndHash.1,
        adnlAddr: msg.adnlAddr,
    });

    elect.isFailed = false;
    elect.isFinished = false;

    storage.save();

    if (msg.queryId) {
        sendConfirmation(InMessage.source(), msg.queryId, 0);
    }
}

fun configSetConfirmed(queryId: uint64, ok: bool) {
    val srcWcAndHash = InMessage.source().getWorkchainAndHash();
    val configAddr = blockchain.configParam(0)!.beginParse().preloadUint(256);
    var storage = Storage.load();
    if ((storage.currectElections == null) || (srcWcAndHash.0 == -1) || (srcWcAndHash.1 != configAddr)) {
        // not from config smc, somebody's joke?
        // or no elections active (or just completed)
        return;
    }
    val elect = storage.currectElections.load();
    if (elect.electionsAt != queryId || (!elect.isFinished)) {
        // not these elections, or elections not finished yet
    }
    setGasLimitToMaximum();
    if(!ok) {
        // Cancel elections, return stakes
        val (pastElections, unusedPrizes) = storage.credits.unfreezeAll(storage.pastElections, elect.electionsAt);
        storage.currectElections = null;
        storage.pastElections = pastElections;
        storage.grams += unusedPrizes;
        storage.save();
    }
    // ... do not remove elect until we see this set as the next elected validator set
}

fun processSimpleTransfer() {
    var storage = lazy Storage.load();
    val (srcWc, srcHashPart) = InMessage.source().getWorkchainAndHash();
    if (srcHashPart == 0 || srcWc != -1 || storage.activeId == 0) {
        storage.grams += InMessage.value();
        storage.save();
        return;
    }
    val electionLookup = storage.pastElections.get(storage.activeId);
    if (!electionLookup.isFound) {
        storage.grams != InMessage.value();
    } else {
        var election = electionLookup.loadValue();
        election.bonuses += InMessage.value();
        storage.pastElections.set(storage.activeId, election);
    }
    storage.save();
}

const RECOVER_STAKE_OPCODE: uint32 = 0x47657424;

struct(0xf96f7324) PayStake {
    queryId: uint64;
}

fun recoverStake(queryId: uint64) {
    val (srcWc, srcHashPart) = InMessage.source().getWorkchainAndHash();
    if (srcWc != -1) {
        // not from masterchain, return error
        return sendMessageBack(InMessage.source(), 0xfffffffe, queryId, RECOVER_STAKE_OPCODE, 0, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
    }
    var storage = Storage.load();
    val deleteRes = storage.credits.deleteAndGetDeleted(srcHashPart);
    if (!deleteRes.isFound) {
        // no credit for sender, return error
        return sendMessageBack(InMessage.source(), 0xfffffffe, queryId, RECOVER_STAKE_OPCODE, 0, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
    }
    val amount: coins = deleteRes.loadValue();

    storage.save();

    val recoverStakeMsg = createMessage({
        dest: InMessage.source(),
        bounce: BounceMode.Only256BitsOfBody,
        value: amount,
        body: PayStake {
            queryId,
        },
    });
    recoverStakeMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

@method_id(1666)
fun afterCodeUpgrade(queryId: uint64) {
    val op = 0x4e436f64;
    return sendMessageBack(InMessage.source(), 0xce436f64, queryId, op, 0, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

fun upgradeCode(msg: UpgradeCode): bool {
    val cAddr = blockchain.configParam(0);
    if (cAddr == null) {
        // no configuration smart contract known
        return false;
    }
    val configAddr = cAddr.beginParse().preloadUint(256);
    val (srcWc, srcHashPart) = InMessage.source().getWorkchainAndHash();
    if ((srcWc != -1) | (srcHashPart != configAddr)) {
        // not from configuration smart contract
        return false;
    }
    setGasLimitToMaximum();
    contract.setCodePostponed(msg.newCode);
    if(!msg.remaining.isEmpty()) {
        // SAFETY: This is safe as sender is validated
        setTvmRegisterC3(transformSliceToContinuation(msg.newCode.beginParse()));
        afterCodeUpgrade(msg.queryId);
        throw 0;
    }
    return true;
}

type AllowedMessages = SimpleTransfer | NewStakeMessage | RecoverStakeRequest | UpgradeCode | ConfigConfirmed | ConfigConfirmedAlt | NewComplaint | SignedVoteForComplaint | FallbackMessage;


fun onInternalMessage(in: InMessage) {
    // Special case with empty body
    if(in.body.isEmpty()) {
        processSimpleTransfer();
        return;
    }
    val msg = lazy AllowedMessages.fromSlice(in.body);
    match (msg) {
        SimpleTransfer => {
            processSimpleTransfer();
            return;
        }
        NewStakeMessage => {
            processNewStake(msg);
            return;
        }
        RecoverStakeRequest => {
            recoverStake(msg.queryId);
            return;
        }
        UpgradeCode => {
            // Accepted only from config contract
            val ok = upgradeCode(msg);
            sendMessageBack(InMessage.source(), ok ? 0xce436f64 : 0xffffffff, msg.queryId, UpgradeCode.getDeclaredPackPrefix(), 0, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
            return;
        }
        ConfigConfirmed => {
            configSetConfirmed(msg.queryId, true);
            return;
        }
        ConfigConfirmedAlt => {
            configSetConfirmed(msg.queryId, false);
            return;
        }
        NewComplaint => {
            var price = 0;
            // Changed from FunC original src. This if statement was inside the `registerComplaint()`
            if (in.body.depth() >= 128) {
                // Invalid complaint
                price = -3;
            }
            price = registerComplaint(msg, InMessage.value());
            var mode = SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE;
            var ansTag = -price;
            if (price >= 0) {
                // ok, debit price
                reserveToncoinsOnBalance(price, RESERVE_MODE_INCREASE_BY_ORIGINAL_BALANCE);
                ansTag = 0;
                mode = SEND_MODE_CARRY_ALL_BALANCE;
            }
            sendMessageBack(InMessage.source(), ansTag + 0xf2676350, msg.queryId, NewComplaint.getDeclaredPackPrefix(), 0, mode);
            return;
        }
        SignedVoteForComplaint => {
            val vote = VoteForComplaint.fromSlice(msg.vote);
            assert (vote.signTag == 0x56744350) throw 37;
            val vDescr = getValidatorDescr(vote.idx);
            assert (isSliceSignatureValid(msg.vote, msg.signature as slice, vDescr.this.validatorPubkey)) throw 34;
            val res = proceedRegisterVote(vote.electId, vote.chash, vote.idx, vDescr.this.validatorWeight);
            sendMessageBack(InMessage.source(), res + 0xd6745240, msg.queryId, SignedVoteForComplaint.getDeclaredPackPrefix(), 0, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
            return;
        }
        FallbackMessage => {
            sendMessageBack(InMessage.source(), 0xffffffff, msg.queryId, msg.opcodeBits as uint32, 0, SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
            return;
        }
        else => {
            // Ignore message
            return;
        }
    }
}