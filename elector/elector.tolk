import "@stdlib/gas-payments"
import "@stdlib/lisp-lists"
import "@stdlib/tvm-dicts"
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

const SORT_KEY_LEN = 128 + 32 + 256;

fun computeTotalStake(l: lisp_list<array<int>>, n: int, mStake: int): int {
    var totStake = 0;
    var ptr = l;
    repeat (n) {
        val head = ptr.popHead();
        val stake = head.get(0);
        val maxF = head.get(1);
        totStake += min(stake, (maxF * mStake) >> 16);
    }
    return totStake;
}

struct ElectionResult {
    vset: dict;
    totalWeight: int;
    frozen: FrozenDict;
    totalStakes: coins;
    count: int;
}

fun tryElect(mutate credits: CreditsMap, members: map<uint256, MemberParams>, minStake: coins, maxStake: coins, minTotalStake: coins, maxStakeFactor: uint32): ElectionResult {
    val limits = getValidatorLimits();
    val minValidators = max(limits.minValidators, 1);

    // Build sorted dict: key = stake(128) + negTime(32) + pubkey(256)
    var n = 0;
    var sdict = createEmptyDict();
    var pubkey = -1;
    do {
        val memberLookup = members.findKeyGreater(pubkey);
        if (memberLookup.isFound) {
            val member = memberLookup.loadValue();
            pubkey = memberLookup.getKey();
            val key = beginCell()
                .storeUint(member.msgValue, 128)
                .storeInt(-member.timestamp, 32)
                .storeUint(pubkey, 256)
                .endCell().beginParse();
            sdict.sDictSetBuilder(SORT_KEY_LEN, key, beginCell()
                .storeUint(min(member.maxFactor, maxStakeFactor), 32)
                .storeUint(member.srcAddr, 256)
                .storeUint(member.adnlAddr, 256));
            n += 1;
        }
    } while (memberLookup.isFound);

    n = min(n, limits.maxValidators);
    if (n < minValidators) {
        return ElectionResult {
            vset: createEmptyDict(),
            totalWeight: 0,
            frozen: [],
            totalStakes: 0,
            count: 0,
        };
    }

    // Extract all entries from sorted dict into a list (descending stake order)
    // dict_delete_get_min extracts ascending; prependHead reverses → descending
    var l: lisp_list<array<int>> = [];
    do {
        var (keySlice, valSlice, found) = sdict.sDictDeleteFirstAndGet(SORT_KEY_LEN);
        if (found) {
            var ks = keySlice!;
            var vs = valSlice!;
            val stake = min(ks.loadUint(128), maxStake);
            ks.skipBits(32); // skip negTime
            val entryPubkey = ks.preloadUint(256);
            val maxF = vs.loadUint(32);
            vs.skipBits(256); // skip addr
            val adnlAddr = vs.preloadUint(256);
            l.prependHead([stake, maxF, entryPubkey, adnlAddr]);
        }
    } while (found);
    // l is now in descending stake order

    // Find optimal validator count
    var i = minValidators - 1;
    var l1 = l;
    repeat (i) {
        l1 = l1.getTail();
    }
    var bestStake = 0;
    var m = 0;
    do {
        val head = l1.popHead();
        val stake = head.get(0);
        i += 1;
        if (stake >= minStake) {
            val totStake = computeTotalStake(l, i, stake);
            if (totStake > bestStake) {
                bestStake = totStake;
                m = i;
            }
        }
    } while (i < n);

    if ((m == 0) | (bestStake < minTotalStake)) {
        return ElectionResult {
            vset: createEmptyDict(),
            totalWeight: 0,
            frozen: [],
            totalStakes: 0,
            count: 0,
        };
    }

    // Find minimum stake for the selected set (m-th largest)
    l1 = l;
    repeat (m - 1) {
        l1 = l1.getTail();
    }
    val mStake = l1.getHead().get(0);

    // Build validator set and frozen dict
    var ii = 0;
    var totStake = 0;
    var totWeight = 0;
    var vset = createEmptyDict();
    var frozen: FrozenDict = [];
    while (!l.isEmpty()) {
        val head = l.popHead();
        val entryStake = head.get(0);
        val maxF = head.get(1);
        val entryPubkey = head.get(2);
        val adnlAddr = head.get(3);

        // lookup source address from members
        val memberLookup = members.get(entryPubkey);
        assert (memberLookup.isFound) throw 61;
        val member = memberLookup.loadValue();

        var remainingStake = entryStake;
        if (ii < m) {
            val trueStake = min(entryStake, (maxF * mStake) >> 16);
            remainingStake = entryStake - trueStake;
            val weight = (trueStake << 60) / bestStake;
            totStake += trueStake;
            totWeight += weight;

            // TODO: ValidatorDescr struct only covers 0x53 tag (without adnl_addr).
            // The 0x73 tag (with adnl_addr) needs a separate struct or union type.
            var vinfo = beginCell()
                .storeUint(adnlAddr ? 0x73 : 0x53, 8)
                .storeUint(0x8e81278a, 32)
                .storeUint(entryPubkey, 256)
                .storeUint(weight, 64);
            if (adnlAddr) {
                vinfo = vinfo.storeUint(adnlAddr, 256);
            }
            vset.uDictSetBuilder(16, ii, vinfo);

            frozen.set(entryPubkey, ValidatorInRound {
                addr: member.srcAddr,
                weight,
                stake: trueStake,
                isBanned: false,
            });
        }

        if (remainingStake) {
            // credit unused portion of stake
            credits.creditTo(member.srcAddr, remainingStake);
        }
        ii += 1;
    }

    assert (totStake == bestStake) throw 49;

    return ElectionResult {
        vset,
        totalWeight: totWeight,
        frozen,
        totalStakes: totStake,
        count: m,
    };
}