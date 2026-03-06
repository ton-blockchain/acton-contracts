struct Storage {
    currectElections: cell;
    credits: cell;
    pastElections: cell;
    grams: coins;
    activeId: uint32;
    activeHash: uint256;
}


struct Elections {
    electionsAt: uint32;
    electionsCloseAt: uint32;
    minStake: coins;
    totalStake: coins;
    members: cell;
    isFailed: bool;
    isFinished: bool;
}