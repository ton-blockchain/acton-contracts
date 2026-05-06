import "types"

fun CreditsMap.creditTo(mutate self, addr: uint256, amount: coins) {
    val res = self.get(addr);
    if (res.isFound) {
        amount += res.loadValue();
    }
    self.set(addr, amount);
}

fun CreditsMap.unfreezeWithoutBonuces(mutate self, freezeDict: FrozenDict, totalStakes: int): int {
    var total = 0;
    var recovered = 0;
    var pubkey = -1;
    var freezeFound = true;
    do {
        val freezeLookup = freezeDict.findKeyGreater(pubkey);
        freezeFound = freezeLookup.isFound;
        if (freezeFound) {
            val freezeVal = freezeLookup.loadValue();
            pubkey = freezeLookup.getKey();
            if (freezeVal.isBanned) {
                recovered += freezeVal.stake;
            } else {
                self.creditTo(freezeVal.addr, freezeVal.stake);
            }
            total += freezeVal.stake;
        }
    } while (freezeFound);

    assert (total == totalStakes) throw 59;
    return (recovered);
}

fun CreditsMap.unfreezeWithBonuces(
    mutate self,
    freezeDict: FrozenDict,
    totalStakes: int,
    totalBonuses: int,
): int {
    var total = 0;
    var recovered = 0;
    var returnedBonuces = 0;
    var pubkey = -1;
    var freezeFound = true;
    do {
        val freezeLookup = freezeDict.findKeyGreater(pubkey);
        freezeFound = freezeLookup.isFound;
        if (freezeFound) {
            val freezeVal = freezeLookup.loadValue();
            pubkey = freezeLookup.getKey();
            if (freezeVal.isBanned) {
                recovered += freezeVal.stake;
            } else {
                val bonus = mulDivFloor(totalBonuses, freezeVal.stake, totalStakes);
                returnedBonuces += bonus;
                self.creditTo(freezeVal.addr, freezeVal.stake + bonus);
            }
            total += freezeVal.stake;
        }
    } while (freezeFound);

    assert ((total == totalStakes) && (returnedBonuces <= totalBonuses)) throw 59;

    return (recovered + totalBonuses - returnedBonuces);
}

fun stakesSum(frozenDict: FrozenDict): int {
    var total = 0;
    var pubkey = -1;
    var freezeFound = true;
    do {
        val freezeLookup = frozenDict.findKeyGreater(pubkey);
        freezeFound = freezeLookup.isFound;
        if (freezeFound) {
            val freezeVal = freezeLookup.loadValue();
            pubkey = freezeLookup.getKey();
            total += freezeVal.stake;
        }
    } while (freezeFound);
    return total;
}

fun CreditsMap.unfreezeAll(
    mutate self,
    pastElections: map<uint32, PastElection>,
    electionId: uint32,
): (map<uint32, PastElection>, int) {
    val res = pastElections.deleteAndGetDeleted(electionId);
    if (!res.isFound) {
        return (pastElections, 0);
    }
    val pastElection = res.loadValue();
    // TODO
    // totalStakes = fdict.stakes_sup() WTF
    val unusedPrizes = (pastElection.bonuses > 0)
        ? self.unfreezeWithBonuces(
            pastElection.frozenDict,
            pastElection.totalStake,
            pastElection.bonuses,
        )
        : self.unfreezeWithoutBonuces(pastElection.frozenDict, pastElection.totalStake);
    return (pastElections, unusedPrizes);
}

struct PunishResult {
    frozenDict: FrozenDict
    fineUnalloc: int
    fineCollected: int
}

fun CreditsMap.punish(mutate self, frozen: FrozenDict, complaint: Complaint): PunishResult {
    val lookupFrozen = frozen.get(complaint.validatorPubkey);
    if (!lookupFrozen.isFound) {
        return PunishResult {
            frozenDict: frozen,
            fineUnalloc: 0,
            fineCollected: 0,
        };
    }

    var frozenValue = lookupFrozen.loadValue();
    val fine = min(
        frozenValue.stake,
        complaint.suggestedFine +
        mulDivFloor(frozenValue.stake, complaint.suggestedFinePart, 1 << 32),
    );
    frozenValue.stake -= fine;
    frozen.set(complaint.validatorPubkey, frozenValue);
    val reward = min(fine >> 3, complaint.paid * 8);
    self.creditTo(complaint.rewardAddr, reward);
    return PunishResult {
        frozenDict: frozen,
        fineUnalloc: fine - reward,
        fineCollected: fine,
    };
}
