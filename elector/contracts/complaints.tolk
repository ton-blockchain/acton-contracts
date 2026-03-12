import "credits"
import "messages"
import "types"
import "utils"

fun registerComplaint(msg: NewComplaint, msgValue: coins): int {
    val (srcWc, srcAddr) = InMessage.source().getWorkchainAndHash();
    if (srcWc != -1) {
        // not from masterchain
        return -1;
    }

    var storage = lazy Storage.load();
    val electionLookup = storage.pastElections.get(msg.electionId);
    if (!electionLookup.isFound) {
        // election not found
        return -2;
    }
    var pastElection = electionLookup.loadValue();
    val expireIn = pastElection.unfreezeAt - blockchain.now();
    if (expireIn <= 0) {
        // already expired
        return -4;
    }

    var complaint = Complaint.fromSlice(msg.rawComplaint);
    complaint.rewardAddr = srcAddr;
    complaint.createdAt = blockchain.now();

    // compute complaint storage/creation price
    val prices = getComplaintPrices();

    val (_, bits, refs) = msg.rawComplaint.calculateSizeStrict(4096);
    val pps = (bits + 1024) * prices.bitPrice + (refs + 2) * prices.cellPrice;
    complaint.paid = pps * expireIn + prices.deposit;

    if (msgValue < complaint.paid + (1 << 30)) {
        // not enough money
        return -5;
    }

    // re-pack modified complaint
    val complaintCell = complaint.toCell();

    // check validator exists in frozen dict
    val frozenLookup = pastElection.frozenDict.get(complaint.validatorPubkey);
    if (!frozenLookup.isFound) {
        // no such validator, cannot complain
        return -6;
    }
    val validator = frozenLookup.loadValue();
    val fine = complaint.suggestedFine + mulDivFloor(validator.stake, complaint.suggestedFinePart, 1 << 32);
    if (fine > validator.stake) {
        // validator's stake is less than suggested fine
        return -7;
    }
    if (fine <= complaint.paid) {
        // fine is less than money paid for creating complaint
        return -8;
    }
    val cstatus = ComplaintStatus {
        complaint: complaintCell,
        voters: [],
        vsetId: 0,
        weightRemaining: 0,
    };
    // check complaint doesn't already exist
    val cplId = complaintCell.hash();
    val wasThere = pastElection.complaints.addOrGetExisting(cplId, cstatus);
    if (wasThere.isFound) {
        // complaint already exists
        return -9;
    }
    storage.pastElections.set(msg.electionId, pastElection);
    storage.save();
    return complaint.paid;
}


struct VoteRegustrationStatus {
    complaint: Complaint?;
    status: int;
}

fun Complaints.registerVote(mutate self, chash: uint256, idx: uint16, weight: int): VoteRegustrationStatus {
    val lookupComplaint = self.get(chash);
    if (!lookupComplaint.isFound) {
        return VoteRegustrationStatus {
            complaint: null,
            status: -1,
        }
    }
    val (rawVset, curVset) = getCurrentVset();
    val curVsetId = rawVset.hash();
    var cstatus = lookupComplaint.loadValue();
    val isVsetOld = (cstatus.vsetId != curVsetId);
    if (cstatus.weightRemaining < 0 && isVsetOld) {
        return VoteRegustrationStatus {
            complaint: null,
            status: -3,
        }
    }

    if (isVsetOld) {
        cstatus.vsetId = curVsetId;
        cstatus.voters = [];
        cstatus.weightRemaining = mulDivFloor(curVset.totalWeight, 2, 3);
    }

    val lookupVote = cstatus.voters.get(idx);
    if (lookupVote.isFound) {
        // Already voted for this proposal
        return VoteRegustrationStatus {
            complaint: null,
            status: 0,
        }
    }

    cstatus.voters.set(idx, blockchain.now());

    var oldWr = cstatus.weightRemaining;
    cstatus.weightRemaining -= weight;
    oldWr ^= cstatus.weightRemaining;

    self.set(chash, cstatus);

    if (oldWr >= 0) {
        return VoteRegustrationStatus {
            complaint: null,
            status: 1,
        }
    }

    return VoteRegustrationStatus {
        complaint: cstatus.complaint.load(),
        status: 2,
    }
}

fun proceedRegisterVote(electionId: uint32, chash: uint256, idx: int, weight: uint64): int {
    var storage = Storage.load();
    val electLookup = storage.pastElections.get(electionId);
    if (!electLookup.isFound) {
        return -2;
    }
    var pastElection = electLookup.loadValue();
    val res = pastElection.complaints.registerVote(chash, idx, weight);
    if (res.status <= 0) {
        return res.status;
    }
    if (res.complaint != null) {
        // Complaint was accepted
        val punishRes = storage.credits.punish(pastElection.frozenDict, res.complaint);
        storage.grams += punishRes.fineUnalloc;
        pastElection.totalStake -= punishRes.fineCollected;
    }
    storage.pastElections.set(electionId, pastElection);
    storage.save();
    return res.status;
}