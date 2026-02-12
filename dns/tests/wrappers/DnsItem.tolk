import "@stdlib/gas-payments"
import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "@acton/testing/expect"
import "@acton/types/message"
import "../../contracts/storage"
import "../../contracts/messages"

struct NftItemContract {
    address: address
    stateInit: ContractState? = null
}

/// Creates a contract wrapper instance from the storage data
fun NftItemContract.fromStorage(storage: ItemStorageNotInitialized, toShard: AddressShardingOptions? = null) {
    val stateInit = ContractState {
        code: build("dns_item"),
        data: storage.toCell(),
    };
    val address = toShard == null
        ? AutoDeployAddress { stateInit }.calculateAddress()
        : AutoDeployAddress { stateInit, toShard }.calculateAddress();
    return NftItemContract { address, stateInit }
}

/// Creates a contract wrapper instance from the address
fun NftItemContract.fromAddress(address: address) {
    return NftItemContract { address }
}

/// Deploys the contract to the blockchain
fun NftItemContract.deploy(self, from: address, config: SendParams = {}): SendResultList {
    if (self.stateInit == null) {
        Assert.fail("Cannot deploy a contract created with 'fromAddress' because it lacks state init for deployment");
    }
    val msg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: {
            stateInit: self.stateInit,
        },
    });
    return net.send(from, msg, SEND_MODE_PAY_FEES_SEPARATELY)
}

/// Send message to the contract with a custom body cell
fun NftItemContract.sendAny(self, from: address, body: cell, config: SendParams = {}): SendResultList {
    val msg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body,
    });
    return net.send(from, msg, SEND_MODE_PAY_FEES_SEPARATELY)
}

fun NftItemContract.get_nft_data(self): tuple {
    return net.runGetMethod(self.address, "get_nft_data")
}

fun NftItemContract.get_editor(self): address? {
    return net.runGetMethod(self.address, "get_editor")
}

fun NftItemContract.get_domain(self): slice {
    return net.runGetMethod(self.address, "get_domain")
}

fun NftItemContract.get_auction_info(self): (address?, coins, int) {
    return net.runGetMethod(self.address, "get_auction_info")
}

fun NftItemContract.get_last_fill_up_time(self): int {
    return net.runGetMethod(self.address, "get_last_fill_up_time")
}

fun NftItemContract.dnsresolve(self, subdomain: slice, category: int): (int, cell?) {
    return net.runGetMethod(self.address, "dnsresolve", [subdomain, category] as tuple)
}
