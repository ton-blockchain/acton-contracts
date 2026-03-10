type CreditsMap = map<uint256, coins>;

fun CreditsMap.creditTo(mutate self, addr: uint256, amount: coins) {
    val res = self.get(addr);
    if (res.isFound) {
        amount += res.loadValue();
    }
    self.set(addr, amount);
}


fun processNewStake(src: address, msgValue: int, cs: slice, queryId: int) {
    
}