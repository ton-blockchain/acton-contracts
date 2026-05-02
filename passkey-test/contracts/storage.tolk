struct Storage {
    seqno: uint32        // replay counter, incremented per accepted external
    pubkey: bits264      // SEC1 compressed P-256 public key (33 bytes)
    authData: bits296    // WebAuthn authenticatorData: rpIdHash(32) || flags(1) || signCount(4) = 37 bytes
    cdjPrefix: cell      // bytes of `{"type":"webauthn.get","challenge":"`              (36 bytes)
    cdjSuffix: cell      // bytes of `","origin":"<origin>","crossOrigin":false}`        (~56 bytes)
}

fun Storage.load() {
    return Storage.fromCell(contract.getData());
}

fun Storage.save(self) {
    contract.setData(self.toCell());
}
