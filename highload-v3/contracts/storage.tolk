import "bitmap"

const INTERNAL_TRANSFER_BODY_BITS = 32 + 64

struct HighloadWalletStorage {
    publicKey: uint256
    subwalletId: uint32
    oldQueries: QueryBitmapMap
    queries: QueryBitmapMap
    lastCleanTime: uint64
    timeout: uint22
}

fun HighloadWalletStorage.load() {
    return HighloadWalletStorage.fromCell(contract.getData());
}

fun HighloadWalletStorage.save(self) {
    contract.setData(self.toCell());
}

fun HighloadWalletStorage.cleanupQueryWindows(mutate self, now: int) {
    val timeout = self.timeout;
    val lastCleanTime = self.lastCleanTime;

    if (lastCleanTime < (now - timeout)) {
        self.oldQueries = self.queries;
        self.queries = [];

        if (lastCleanTime < (now - (timeout * 2))) {
            self.oldQueries = [];
        }

        self.lastCleanTime = now;
    }
}
