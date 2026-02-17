import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "../../contracts/storage"

struct RootDnsContract {
    address: address
    stateInit: ContractState? = null
}

/// Creates a contract wrapper instance from the storage data
fun RootDnsContract.fromStorage(storage: RootDnsStorage, toShard: AddressShardingOptions? = null) {
    val stateInit = ContractState {
        code: build("dns_root"),
        data: storage.toCell(),
    };
    val address = toShard == null
        ? AutoDeployAddress { stateInit }.calculateAddress()
        : AutoDeployAddress { stateInit, toShard }.calculateAddress();
    return RootDnsContract { address, stateInit }
}

/// Creates a contract wrapper instance from the address
fun RootDnsContract.fromAddress(address: address) {
    return RootDnsContract { address }
}

/// Deploys the contract to the blockchain
fun RootDnsContract.deploy(self, from: address, config: SendParams = {}): SendResultList {
    if (self.stateInit == null) {
        Assert.fail("Cannot deploy a contract created with 'fromAddress' because it lacks state init for deployment");
    }
    val outMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: {
            stateInit: self.stateInit,
        },
    });
    return net.send(from, outMessage)
}

/// Send outMessage to the contract with a custom body cell
fun RootDnsContract.sendAny(self, from: address, body: cell, config: SendParams = {}): SendResultList {
    val outMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body,
    });
    return net.send(from, outMessage)
}

fun RootDnsContract.dnsresolve(self, subdomain: slice, category: int): DnsResolveResponse {
    return net.runGetMethod(self.address, "dnsresolve", [subdomain, category] as tuple)
}
