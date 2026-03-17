import "credits"
import "messages"
import "types"
import "utils"

fun registerComplaint(msg: NewComplaint, msgValue: coins): int {
    val (srcWc, srcAddr) = InMessage.source().getWorkchainAndHash();
    if (srcWc != -1) {
        return ComplaintError.NotMasterchain as int;
    }

    var storage = lazy Storage.load();
    val electionLookup = storage.pastElections.get(msg.electionId);
    if (!electionLookup.isFound) {
        return ComplaintError.ElectionNotFound as int;
    }
    var pastElection = electionLookup.loadValue();
    val expireIn = pastElection.unfreezeAt - blockchain.now();
    if (expireIn <= 0) {
        return ComplaintError.AlreadyExpired as int;
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
        return ComplaintError.NotEnoughMoney as int;
    }

    // re-pack modified complaint
    val complaintCell = complaint.toCell();

    // check validator exists in frozen dict
    val frozenLookup = pastElection.frozenDict.get(complaint.validatorPubkey);
    if (!frozenLookup.isFound) {
        return ComplaintError.ValidatorNotFound as int;
    }
    val validator = frozenLookup.loadValue();
    val fine = complaint.suggestedFine + mulDivFloor(validator.stake, complaint.suggestedFinePart, 1 << 32);
    if (fine > validator.stake) {
        return ComplaintError.FineTooLarge as int;
    }
    if (fine <= complaint.paid) {
        return ComplaintError.PaidMoreThanFine as int;
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
        return ComplaintError.DuplicateComplaint as int;
    }
    storage.pastElections.set(msg.electionId, pastElection);
    storage.save();
    return complaint.paid;
}


struct VoteRegustrationStatus {
    complaint: Complaint?;
    status: VoteStatus;
}

fun Complaints.registerVote(mutate self, chash: uint256, idx: uint16, weight: int): VoteRegustrationStatus {
    val lookupComplaint = self.get(chash);
    if (!lookupComplaint.isFound) {
        return VoteRegustrationStatus {
            complaint: null,
            status: VoteStatus.ComplaintNotFound,
        }
    }
    val (rawVset, curVset) = getCurrentVset();
    val curVsetId = rawVset.hash();
    var cstatus = lookupComplaint.loadValue();
    val isVsetOld = (cstatus.vsetId != curVsetId);
    if (cstatus.weightRemaining < 0 && isVsetOld) {
        return VoteRegustrationStatus {
            complaint: null,
            status: VoteStatus.OldVset,
        }
    }

    if (isVsetOld) {
        cstatus.vsetId = curVsetId;
        cstatus.voters = [];
        cstatus.weightRemaining = mulDivFloor(curVset.totalWeight, 2, 3);
    }

    val lookupVote = cstatus.voters.get(idx);
    if (lookupVote.isFound) {
        return VoteRegustrationStatus {
            complaint: null,
            status: VoteStatus.AlreadyVoted,
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
            status: VoteStatus.Accepted,
        }
    }

    return VoteRegustrationStatus {
        complaint: cstatus.complaint.load(),
        status: VoteStatus.Finished,
    }
}

fun proceedRegisterVote(electionId: uint32, chash: uint256, idx: int, weight: uint64): VoteStatus {
    var storage = Storage.load();
    val electLookup = storage.pastElections.get(electionId);
    if (!electLookup.isFound) {
        return VoteStatus.ElectionNotFound;
    }
    var pastElection = electLookup.loadValue();
    val res = pastElection.complaints.registerVote(chash, idx, weight);
    if (res.status as int <= 0) {
        return res.status;
    }
    if (res.complaint != null) {
        // Complaint was accepted
        val punishRes = storage.credits.punish(pastElection.frozenDict, res.complaint);
        storage.grams += punishRes.fineUnalloc;
        pastElection.totalStake -= punishRes.fineCollected;
        pastElection.frozenDict = punishRes.frozenDict;
    }
    storage.pastElections.set(electionId, pastElection);
    storage.save();
    return res.status;
}
