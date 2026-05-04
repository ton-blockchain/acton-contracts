import "@acton/build"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "Elector.gen"
import "../contracts/types"

fun Elector.fromConfig(
    workchain: int8 = MASTERCHAIN,
    toShard: AddressShardingOptions? = null,
): Elector {
    val storage = Storage {
        currectElections: null,
        credits: [],
        pastElections: [],
        grams: 0,
        activeId: 0,
        activeHash: 0,
    };
    val stateInit = ContractState {
        code: build("Elector"),
        data: storage.toCell(),
    };
    val address = AutoDeployAddress { stateInit, toShard, workchain }.calculateAddress();
    return Elector { address, stateInit };
}

fun Elector.deployToWorkchain(
    self,
    from: address,
    workchain: int8 = MASTERCHAIN,
    config: SendParams = {},
): SendResultList {
    if (self.stateInit == null) {
        Assert.fail("Cannot deploy a contract created with 'fromAddress' because it lacks state init for deployment");
    }
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: AutoDeployAddress {
            stateInit: self.stateInit,
            workchain,
        },
    });
    return net.send(from, genericMsg);
}
