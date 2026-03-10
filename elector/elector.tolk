import "@stdlib/gas-payments"
import "finance"
import "messages"
import "types"
import "utils"

type AllowedMessages = NewStakeMessage;

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

struct FreezeValue {
    addr: uint256;
    weight: uint64;
    stake: coins;
    isBanned: bool;
}

type FrozenDict = map<uint256, FreezeValue>;

fun unfreezeWithoutBonuces(credits: CreditsMap, freezeDict: FrozenDict, totalStakes: int) {
    var total = 0;
    var recovered = 0;
    var pubkey = -1;
    do {
        val freezeLookup = freezeDict.findKeyGreater(pubkey);
        if (freezeLookup.isFound) {
            val freezeVal = freezeLookup.loadValue();
            pubkey = freezeLookup.getKey();
            if (freezeVal.isBanned) {
                recovered += freezeVal.stake;
            } else {
                credits.creditTo(freezeVal.addr, freezeVal.stake);
            }
            total += freezeVal.stake;
        }
    } while (freezeLookup.isFound);

    assert (total == totalStakes) throw 59;
    return (credits, recovered);
}

fun unfreezeWithBonuces(credits: CreditsMap, freezeDict: FrozenDict, totalStakes: int, totalBonuses: int) {
    var total = 0;
    var recovered = 0;
    var returnedBonuces = 0;
    var pubkey = -1;
    do {
        val freezeLookup = freezeDict.findKeyGreater(pubkey);
        if (freezeLookup.isFound) {
            val freezeVal = freezeLookup.loadValue();
            pubkey = freezeLookup.getKey();
            if (freezeVal.isBanned) {
                recovered += freezeVal.stake;
            } else {
                val bonus = mulDivFloor(totalBonuses, freezeVal.stake, totalStakes);
                returnedBonuces += bonus;
                credits.creditTo(freezeVal.addr, freezeVal.stake + bonus);
            }
            total += freezeVal.stake;
        }
    } while (freezeLookup.isFound);

    assert ((total == totalStakes) && (returnedBonuces <= totalBonuses)) throw 59;

    return (credits, recovered + totalBonuses - returnedBonuces);
}

fun stakesSum(frozenDict: FrozenDict) {
    var total = 0;
    var pubkey = -1;
    do {
        val freezeLookup = frozenDict.findKeyGreater(pubkey);
        if (freezeLookup.isFound) {
            val freezeVal = lazy freezeLookup.loadValue();
            pubkey = freezeLookup.getKey();
            total += freezeVal.stake;
        }
    } while (freezeLookup.isFound);
    return total;
}


fun unfreezeAll(credits: CreditsMap, pastElections: map<uint32, PastElection>, electionId: uint32) {
    val res = pastElections.deleteAndGetDeleted(electionId);
    if (!res.isFound) {
        return (credits, pastElections, 0);
    }
    val pastElection = res.loadValue();
    // TODO
    // totalStakes = fdict.stakes_sup() WTF
}

fun onInternalMessage(in: InMessage) {

}