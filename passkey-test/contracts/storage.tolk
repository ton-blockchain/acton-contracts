struct Storage {
    seqno: uint32        // replay counter, incremented per accepted external
    subwalletId: uint32  // v4r2-compatible payload field
    pubkey: bits264      // SEC1 compressed P-256 public key (33 bytes)
}

fun Storage.load() {
    return Storage.fromCell(contract.getData());
}

fun Storage.save(self) {
    contract.setData(self.toCell());
}
