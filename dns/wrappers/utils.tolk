import "@acton/build"
import "DnsItem.gen"
import "../contracts/storage"

/// Creates a DNS item wrapper from the not-yet-initialized storage layout.
fun DnsItem.fromNotInitializedStorage(
    storage: ItemStorageNotInitialized,
    toShard: AddressShardingOptions? = null,
): DnsItem {
    val stateInit = ContractState {
        code: build("DnsItem"),
        data: storage.toCell(),
    };
    val address = AutoDeployAddress { stateInit, toShard }.calculateAddress();
    return DnsItem { address, stateInit };
}
