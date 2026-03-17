import "@stdlib/gas-payments"
import "@stdlib/lisp-lists"
import "@stdlib/tvm-lowlevel"
import "complaints"
import "credits"
import "messages"
import "types"
import "utils"

fun processNewStake(msg: NewStakeMessage): void {
    val srcWcAndHash = InMessage.source().getWorkchainAndHash();
    var storage = Storage.load();
    if ((storage.currectElections == null) || (srcWcAndHash.0 != -1)) {
        return returnStake(InMessage.source(), msg.queryId, StakeReason.Ok);
    }

    val dataCell = StakeSubmit {
        stakeAt: msg.stakeAt,
        maxFactor: msg.maxFactor,
        srcAddr: srcWcAndHash.1,
        adnlAddr: msg.adnlAddr,
    }.toCell();
    if (!isSignatureValid(dataCell.hash(), msg.signature.load() as slice, msg.validatorPubkey)) {
        return returnStake(InMessage.source(), msg.queryId, StakeReason.InvalidSignature);
    }

    if (msg.maxFactor < 0x10000) {
        return returnStake(InMessage.source(), msg.queryId, StakeReason.LowFactor);
    }

    var elect = storage.currectElections.load();
    var msgValue = InMessage.value() - ton("1"); // Deduct 1 ton for sending confirmation
    if ((msgValue << 12) < elect.totalStake) {
        return returnStake(InMessage.source(), msg.queryId, StakeReason.StakeTooSmall);
    }

    elect.totalStake += msgValue;
    if (msg.stakeAt != elect.electionsAt) {
        return returnStake(InMessage.source(), msg.queryId, StakeReason.WrongElection);
    }

    if (elect.isFinished) {
        return returnStake(InMessage.source(), msg.queryId, StakeReason.Ok);
    }

    var memberLookupRes = elect.members.get(msg.validatorPubkey);
    if (memberLookupRes.isFound) {
        val member = memberLookupRes.loadValue();
        msgValue += member.msgValue;
        memberLookupRes.isFound = (srcWcAndHash.1 != member.srcAddr);
    }

    if (memberLookupRes.isFound) {
        return returnStake(InMessage.source(), msg.queryId, StakeReason.DuplicateKey);
    }

    if (msgValue < elect.minStake) {
        return returnStake(InMessage.source(), msg.queryId, StakeReason.BelowMinStake);
    }

    assert (msgValue != 0) throw 44;
    // Actually we are "accepting" internal message here. It is equal to SETGASLIMIT *max gas limit*
    // in asm it is ACCEPT
    setGasLimitToMaximum();
    // Store stake in the dictionary
    elect
        .members
        .set(
            msg.validatorPubkey,
            MemberParams {
                msgValue,
                timestamp: blockchain.now(),
                maxFactor: msg.maxFactor,
                srcAddr: srcWcAndHash.1,
                adnlAddr: msg.adnlAddr,
            },
        );

    elect.isFailed = false;
    elect.isFinished = false;

    storage.currectElections = elect.toCell();
    storage.save();

    if (msg.queryId) {
        sendConfirmation(InMessage.source(), msg.queryId, StakeReason.Ok);
    }
}

fun configSetConfirmed(queryId: uint64, ok: bool) {
    val srcWcAndHash = InMessage.source().getWorkchainAndHash();
    val configAddr = blockchain.configParam(0)!.beginParse().preloadUint(256);
    var storage = Storage.load();
    if (
        (storage.currectElections == null) || (srcWcAndHash.0 != -1) ||
        (srcWcAndHash.1 != configAddr)
    ) {
        // not from config smc, somebody's joke?
        // or no elections active (or just completed)
        return;
    }
    val elect = storage.currectElections.load();
    if (elect.electionsAt != queryId || (!elect.isFinished)) {
        // not these elections, or elections not finished yet
        return;
    }
    setGasLimitToMaximum();
    if (!ok) {
        // Cancel elections, return stakes
        val (pastElections, unusedPrizes) = storage
            .credits
            .unfreezeAll(storage.pastElections, elect.electionsAt);
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
        storage.grams += InMessage.value();
    } else {
        var election = electionLookup.loadValue();
        election.bonuses += InMessage.value();
        storage.pastElections.set(storage.activeId, election);
    }
    storage.save();
}

const RECOVER_STAKE_OPCODE: uint32 = 0x47657424

fun recoverStake(queryId: uint64) {
    val (srcWc, srcHashPart) = InMessage.source().getWorkchainAndHash();
    if (srcWc != -1) {
        // not from masterchain, return error
        return sendMessageBack(
            InMessage.source(),
            0xfffffffe,
            queryId,
            RECOVER_STAKE_OPCODE,
            0,
            SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE,
        );
    }
    var storage = Storage.load();
    val deleteRes = storage.credits.deleteAndGetDeleted(srcHashPart);
    if (!deleteRes.isFound) {
        // no credit for sender, return error
        return sendMessageBack(
            InMessage.source(),
            0xfffffffe,
            queryId,
            RECOVER_STAKE_OPCODE,
            0,
            SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE,
        );
    }
    val amount: coins = deleteRes.loadValue();

    storage.save();

    val recoverStakeMsg = createMessage({
        dest: InMessage.source(),
        bounce: BounceMode.Only256BitsOfBody,
        value: amount,
        body: PayStake { queryId },
    });
    recoverStakeMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

@method_id(1666)
fun afterCodeUpgrade(queryId: uint64) {
    val op = 0x4e436f64;
    return sendMessageBack(
        InMessage.source(),
        0xce436f64,
        queryId,
        op,
        0,
        SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE,
    );
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
    if (!msg.remaining.isEmpty()) {
        // SAFETY: This is safe as sender is validated
        setTvmRegisterC3(transformSliceToContinuation(msg.newCode.beginParse()));
        afterCodeUpgrade(msg.queryId);
        throw 0;
    }
    return true;
}

type AllowedMessages =
    | SimpleTransfer
    | NewStakeMessage
    | RecoverStakeRequest
    | UpgradeCode
    | ConfigConfirmed
    | ConfigConfirmedAlt
    | NewComplaint
    | SignedVoteForComplaint
    | FallbackMessage

fun onInternalMessage(in: InMessage) {
    // Special case with empty body
    if (in.body.isEmpty()) {
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
            sendMessageBack(
                InMessage.source(),
                ok ? 0xce436f64 : 0xffffffff,
                msg.queryId,
                UpgradeCode.getDeclaredPackPrefix(),
                0,
                SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE,
            );
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
                price = ComplaintError.CellTooDeep as int;
            } else {
                price = registerComplaint(msg, InMessage.value());
            }
            var mode = SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE;
            var ansTag = -price;
            if (price >= 0) {
                // ok, debit price
                reserveToncoinsOnBalance(price, RESERVE_MODE_INCREASE_BY_ORIGINAL_BALANCE);
                ansTag = 0;
                mode = SEND_MODE_CARRY_ALL_BALANCE;
            }
            sendMessageBack(
                InMessage.source(),
                ansTag + 0xf2676350,
                msg.queryId,
                NewComplaint.getDeclaredPackPrefix(),
                0,
                mode,
            );
            return;
        }
        SignedVoteForComplaint => {
            val vote = VoteForComplaint.fromSlice(msg.vote);
            assert (vote.signTag == 0x56744350) throw 37;
            val vDescr = getValidatorDescr(vote.idx);
            assert (
                isSignatureValid(
                    msg.vote.hash(),
                    msg.signature as slice,
                    vDescr.this.validatorPubkey,
                )
            ) throw 34;
            val res = proceedRegisterVote(
                vote.electId,
                vote.chash,
                vote.idx,
                vDescr.this.validatorWeight,
            );
            sendMessageBack(
                InMessage.source(),
                (res as int + 0xd6745240) as uint32,
                msg.queryId,
                SignedVoteForComplaint.getDeclaredPackPrefix(),
                0,
                SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE,
            );
            return;
        }
        FallbackMessage => {
            sendMessageBack(
                InMessage.source(),
                0xffffffff,
                msg.queryId,
                msg.opcodeBits as uint32,
                0,
                SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE,
            );
            return;
        }
        else => {
            // Ignore message
            return;
        }
    }
}

fun onBouncedMessage(_in: InMessageBounced) {
    // Elector sends some bounceable messages, but don't handle them
}

// Sorting key for election: orders by stake ascending, then time descending, then pubkey
struct SortKey {
    stake: uint128
    negTime: int32
    pubkey: uint256
}

struct SortValue {
    maxFactor: uint32
    addr: uint256
    adnlAddr: uint256
}

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
    vset: map<uint16, AnyValidatorDescr>
    totalWeight: int
    frozen: FrozenDict
    totalStakes: coins
    count: int
}

fun tryElect(
    mutate credits: CreditsMap,
    members: map<uint256, MemberParams>,
    minStake: coins,
    maxStake: coins,
    minTotalStake: coins,
    maxStakeFactor: uint32,
): ElectionResult {
    val limits = getValidatorLimits();
    val minValidators = max(limits.minValidators, 1);

    // Build sorted dict: key = (stake, negTime, pubkey) for ascending order
    var n = 0;
    var sdict: map<SortKey, SortValue> = [];
    var pubkey = -1;
    do {
        val memberLookup = members.findKeyGreater(pubkey);
        if (memberLookup.isFound) {
            val member = memberLookup.loadValue();
            pubkey = memberLookup.getKey();
            sdict.set(
                SortKey {
                    stake: member.msgValue as uint128,
                    negTime: -member.timestamp,
                    pubkey,
                },
                SortValue {
                    maxFactor: min(member.maxFactor, maxStakeFactor),
                    addr: member.srcAddr,
                    adnlAddr: member.adnlAddr,
                },
            );
            n += 1;
        }
    } while (memberLookup.isFound);

    n = min(n, limits.maxValidators);
    if (n < minValidators) {
        return ElectionResult {
            vset: [],
            totalWeight: 0,
            frozen: [],
            totalStakes: 0,
            count: 0,
        };
    }

    // Extract all entries from sorted dict into a list (descending stake order)
    // findKeyGreater iterates ascending; prependHead reverses → descending
    var l: lisp_list<array<int>> = [];
    var prevKey = SortKey {
        stake: 0,
        negTime: -1,
        pubkey: 0,
    };
    var iterFound = true;
    do {
        val lookup = sdict.findKeyGreater(prevKey);
        iterFound = lookup.isFound;
        if (iterFound) {
            prevKey = lookup.getKey();
            val sv = lookup.loadValue();
            // TODO: If validator sends more than maxStake, then the diff will be lost. This is the implementation detail from original funC implementation
            val stake = min(prevKey.stake, maxStake);
            l.prependHead([stake, sv.maxFactor, prevKey.pubkey, sv.adnlAddr]);
        }
    } while (iterFound);
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
            vset: [],
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
    var vset: map<uint16, AnyValidatorDescr> = [];
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

            if (adnlAddr) {
                vset.set(
                    ii,
                    ValidatorDescrWithAdnlAddr {
                        validatorPubkey: entryPubkey,
                        validatorWeight: weight,
                        adnlAddr,
                    },
                );
            } else {
                vset.set(
                    ii,
                    ValidatorDescr {
                        validatorPubkey: entryPubkey,
                        validatorWeight: weight,
                    },
                );
            }

            frozen.set(
                entryPubkey,
                ValidatorInRound {
                    addr: member.srcAddr,
                    weight,
                    stake: trueStake,
                    isBanned: false,
                },
            );
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

fun postponeElections(): bool {
    return false;
}

fun conductElections(mutate storage: Storage): bool {
    if (storage.currectElections == null) {
        return false;
    }
    var elect = storage.currectElections.load();
    if (blockchain.now() < elect.electionsCloseAt) {
        // elections not finished yet
        return false;
    }
    if (blockchain.configParam(0) == null) {
        // no configuration smart contract to send result to
        return postponeElections();
    }
    val stakeLimits = getStakeLimits();
    if (elect.totalStake < stakeLimits.minTotalStake) {
        // insufficient total stake, postpone elections
        return postponeElections();
    }
    if (elect.isFailed) {
        // do not retry failed elections until new stakes arrive
        return postponeElections();
    }
    if (elect.isFinished) {
        // elections finished
        return false;
    }

    val res = tryElect(
        mutate storage.credits,
        elect.members,
        stakeLimits.minStake,
        stakeLimits.maxStake,
        stakeLimits.minTotalStake,
        stakeLimits.maxStakeFactor,
    );

    // if count==0, set failed=true, finished=false
    elect.isFailed = (res.count == 0);
    elect.isFinished = !elect.isFailed;
    storage.currectElections = elect.toCell();

    if (res.count == 0) {
        // elections failed
        storage.save();
        return postponeElections();
    }

    // serialize a query to the configuration smart contract
    // to install the computed validator set as the next validator set
    val validatorConf = getValidatorConf();
    val start = max(blockchain.now() + validatorConf.electionsEndBefore - 60, elect.electionsAt);
    val limits = getValidatorLimits();

    val vset = VSet {
        utimeSince: start,
        utimeUntil: start + validatorConf.electedFor,
        _total: res.count,
        _main: min(res.count, limits.maxMainValidators),
        totalWeight: res.totalWeight,
        dict: res.vset,
    };

    val configAddr = blockchain.configParam(0)!.beginParse().preloadUint(256);
    sendValidatorSetToConfig(configAddr, vset, elect.electionsAt as uint64);

    // add frozen to the dictionary of past elections
    storage
        .pastElections
        .set(
            elect.electionsAt,
            PastElection {
                unfreezeAt: start + validatorConf.electedFor + validatorConf.stakeHeldFor,
                stakeHeld: validatorConf.stakeHeldFor,
                vsetHash: vset.toCell().hash(),
                frozenDict: res.frozen,
                totalStake: res.totalStakes,
                bonuses: 0,
                complaints: [],
            },
        );

    storage.save();
    return true;
}

fun updateActiveVsetId(mutate storage: Storage): bool {
    val curHash = blockchain.configParam(34)!.hash();
    if (curHash == storage.activeHash) {
        // validator set unchanged
        return false;
    }
    if (storage.activeId != 0) {
        // active_id becomes inactive
        val pastLookup = storage.pastElections.get(storage.activeId);
        if (pastLookup.isFound) {
            var pastElection = pastLookup.loadValue();
            assert (pastElection.vsetHash == storage.activeHash) throw 57;
            pastElection.unfreezeAt = blockchain.now() + pastElection.stakeHeld;
            storage.pastElections.set(storage.activeId, pastElection);
        }
    }
    // look up new active_id by hash
    var newId: uint32 = 0;
    var prevKey = -1;
    var searching = true;
    do {
        val lookup = storage.pastElections.findKeyGreater(prevKey);
        searching = lookup.isFound;
        if (searching) {
            prevKey = lookup.getKey();
            var pastElection = lookup.loadValue();
            if (pastElection.vsetHash == curHash) {
                // transfer 1/8 of accumulated everybody's grams to this validator set as bonuses
                val amount = storage.grams >> 3;
                storage.grams -= amount;
                pastElection.bonuses += amount;
                storage.pastElections.set(prevKey, pastElection);
                newId = prevKey;
                searching = false;
            }
        }
    } while (searching);
    storage.activeId = newId;
    storage.activeHash = curHash;
    storage.save();
    return true;
}

fun cellHashEq(vset: cell?, expectedHash: uint256): bool {
    if (vset == null) {
        return false;
    }
    return vset.hash() == expectedHash;
}

fun validatorSetInstalled(mutate storage: Storage): bool {
    // This is checked in onTickTock
    val elect = storage.currectElections!.load();
    if (!elect.isFinished) {
        // elections not finished yet
        return false;
    }
    val pastLookup = storage.pastElections.get(elect.electionsAt);
    if (!pastLookup.isFound) {
        // no election data in dictionary
        return false;
    }
    val pastElection = pastLookup.loadValue();
    val vsetHash = pastElection.vsetHash;
    if (
        cellHashEq(blockchain.configParam(34), vsetHash) |
        cellHashEq(blockchain.configParam(36), vsetHash)
    ) {
        // this validator set has been installed, forget elections
        storage.currectElections = null;
        storage.save();
        updateActiveVsetId(mutate storage);
        return true;
    }
    return false;
}

fun checkUnfreeze(mutate storage: Storage): bool {
    var prevId = -1;
    var searching = true;
    do {
        val lookup = storage.pastElections.findKeyGreater(prevId);
        searching = lookup.isFound;
        if (searching) {
            prevId = lookup.getKey();
            val pastElection = lookup.loadValue();
            if ((pastElection.unfreezeAt <= blockchain.now()) & (prevId != storage.activeId)) {
                // unfreeze!
                val (pastElections, unusedPrizes) = storage
                    .credits
                    .unfreezeAll(storage.pastElections, prevId);
                storage.pastElections = pastElections;
                storage.grams += unusedPrizes;
                // unfreeze only one at time, exit loop
                storage.save();
                searching = false;
            }
        }
    } while (searching);
    return prevId >= 0;
}

fun announceNewElections(mutate storage: Storage): bool {
    val nextVset = blockchain.configParam(36);
    if (nextVset != null) {
        // next validator set exists, no elections needed
        return false;
    }
    val electorAddr = blockchain.configParam(1)!.beginParse().preloadUint(256);
    val (myWc, myAddr) = contract.getAddress().getWorkchainAndHash();
    if ((myWc != -1) | (myAddr != electorAddr)) {
        // this smart contract is not the elections smart contract anymore
        return false;
    }
    val curVset = blockchain.configParam(34);
    if (curVset == null) {
        return false;
    }
    val validatorConf = getValidatorConf();
    val curValidUntil = curVset.beginParse().skipBits(8 + 32).preloadUint(32);
    var t = blockchain.now();
    val t0 = curValidUntil - validatorConf.electionsBeginBefore;
    if (t < t0) {
        // too early for the next elections
        return false;
    }
    if (t - t0 < 60) {
        // pretend that the elections started at t0
        t = t0;
    }
    // get stake parameters
    val stakeLimits = getStakeLimits();
    // announce new elections
    val electAt = t + validatorConf.electionsBeginBefore;
    val electClose = electAt - validatorConf.electionsEndBefore;
    storage.currectElections = Elections {
        electionsAt: electAt,
        electionsCloseAt: electClose,
        minStake: stakeLimits.minStake,
        totalStake: 0,
        members: [],
        isFailed: false,
        isFinished: false,
    }.toCell();
    storage.save();
    return true;
}

fun onRunTickTock(_isTock: bool) {
    setGasLimitToMaximum();
    var storage = Storage.load();
    if (storage.currectElections != null) {
        if (conductElections(mutate storage)) {
            return;
        }
        if (validatorSetInstalled(mutate storage)) {
            return;
        }
    } else {
        if (announceNewElections(mutate storage)) {
            return;
        }
    }
    if (updateActiveVsetId(mutate storage)) {
        return;
    }
    checkUnfreeze(mutate storage);
}

// checks whether a public key participates in current elections
get fun participates_in(validatorPubkey: uint256): int {
    val storage = Storage.load();
    if (storage.currectElections == null) {
        return 0;
    }
    val elect = storage.currectElections.load();
    val memberLookup = elect.members.get(validatorPubkey);
    return memberLookup.isFound ? memberLookup.loadValue().msgValue : 0;
}

// returns the list of all participants of current elections with their stakes
get fun participant_list(): lisp_list<array<int>> {
    val storage = Storage.load();
    if (storage.currectElections == null) {
        return [];
    }
    val elect = storage.currectElections.load();
    var l: lisp_list<array<int>> = [];
    var entry = elect.members.findLast();
    while (entry.isFound) {
        l.prependHead([entry.getKey(), entry.loadValue().msgValue]);
        entry = elect.members.iteratePrev(entry);
    }
    return l;
}

// returns the list of all participants of current elections with their data
// fmt-ignore
get fun participant_list_extended(): (int, int, coins, coins, lisp_list<ParticipantExtEntry>, bool, bool) {
    val storage = Storage.load();
    if (storage.currectElections == null) {
        return (
            0,
            0,
            0,
            0,
            [],
            false,
            false,
        );
    }
    val elect = storage.currectElections.load();
    var l: lisp_list<ParticipantExtEntry> = [];
    var entry = elect.members.findLast();
    while (entry.isFound) {
        val key = entry.getKey();
        val member = entry.loadValue();
        l.prependHead(ParticipantExtEntry {
            pubkey: key,
            data: [member.msgValue, member.maxFactor, member.srcAddr, member.adnlAddr],
        });
        entry = elect.members.iteratePrev(entry);
    }
    return (
        elect.electionsAt,
        elect.electionsCloseAt,
        elect.minStake,
        elect.totalStake,
        l,
        elect.isFailed,
        elect.isFinished,
    );
}

// computes the return stake
get fun compute_returned_stake(walletAddr: uint256): int {
    val storage = Storage.load();
    val lookup = storage.credits.get(walletAddr);
    return lookup.isFound ? lookup.loadValue() : 0;
}

// returns the list of past election ids
get fun past_election_ids(): lisp_list<int> {
    val storage = Storage.load();
    var l: lisp_list<int> = [];
    var entry = storage.pastElections.findLast();
    while (entry.isFound) {
        l.prependHead(entry.getKey());
        entry = storage.pastElections.iteratePrev(entry);
    }
    return l;
}

// returns the list of past elections with full data
get fun past_elections(): lisp_list<PastElectionFullEntry> {
    val storage = Storage.load();
    var l: lisp_list<PastElectionFullEntry> = [];
    var entry = storage.pastElections.findLast();
    while (entry.isFound) {
        val id = entry.getKey();
        val pe = entry.loadValue();
        l.prependHead(PastElectionFullEntry {
            id,
            unfreezeAt: pe.unfreezeAt,
            stakeHeld: pe.stakeHeld,
            vsetHash: pe.vsetHash,
            frozenDict: pe.frozenDict,
            totalStake: pe.totalStake,
            bonuses: pe.bonuses,
            complaints: pe.complaints,
        });
        entry = storage.pastElections.iteratePrev(entry);
    }
    return l;
}

// returns the list of past elections with summary data
get fun past_elections_list(): lisp_list<array<int>> {
    val storage = Storage.load();
    var l: lisp_list<array<int>> = [];
    var entry = storage.pastElections.findLast();
    while (entry.isFound) {
        val id = entry.getKey();
        val pe = entry.loadValue();
        l.prependHead([id, pe.unfreezeAt, pe.vsetHash, pe.stakeHeld]);
        entry = storage.pastElections.iteratePrev(entry);
    }
    return l;
}

fun completeUnpackComplaint(cstatus: ComplaintStatus): ComplaintFullInfo {
    val complaint = cstatus.complaint.load();
    var votersList: lisp_list<int> = [];
    var vEntry = cstatus.voters.findLast();
    while (vEntry.isFound) {
        votersList.prependHead(vEntry.getKey());
        vEntry = cstatus.voters.iteratePrev(vEntry);
    }
    return ComplaintFullInfo {
        complaint: ComplaintUnpacked {
            validatorPubkey: complaint.validatorPubkey,
            description: complaint.description,
            createdAt: complaint.createdAt,
            severity: complaint.severity,
            rewardAddr: complaint.rewardAddr,
            paid: complaint.paid,
            suggestedFine: complaint.suggestedFine,
            suggestedFinePart: complaint.suggestedFinePart,
        },
        voters: votersList,
        vsetId: cstatus.vsetId,
        weightRemaining: cstatus.weightRemaining,
    };
}

get fun get_past_complaints(electionId: uint32): Complaints {
    val storage = Storage.load();
    val pastLookup = storage.pastElections.get(electionId);
    if (!pastLookup.isFound) {
        return [];
    }
    val pastElection = pastLookup.loadValue();
    return pastElection.complaints;
}

get fun show_complaint(electionId: uint32, chash: uint256): ComplaintFullInfo? {
    val complaints = get_past_complaints(electionId);
    val lookup = complaints.get(chash);
    if (!lookup.isFound) {
        return null;
    }
    val cstatus = lookup.loadValue();
    return completeUnpackComplaint(cstatus);
}

get fun list_complaints(electionId: uint32): lisp_list<ComplaintListEntry> {
    val complaints = get_past_complaints(electionId);
    var l: lisp_list<ComplaintListEntry> = [];
    var entry = complaints.findLast();
    while (entry.isFound) {
        val key = entry.getKey();
        val cstatus = entry.loadValue();
        l.prependHead(ComplaintListEntry {
            id: key,
            info: completeUnpackComplaint(cstatus),
        });
        entry = complaints.iteratePrev(entry);
    }
    return l;
}

get fun complaint_storage_price(bits: int, refs: int, expireIn: int): int {
    val prices = getComplaintPrices();
    val pps = (bits + 1024) * prices.bitPrice + (refs + 2) * prices.cellPrice;
    val paid = pps * expireIn + prices.deposit;
    return paid + (1 << 30);
}
