import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"

import "../contracts/types"
import "../tests/wrappers/Counter"

fun counterDeployValue(): coins {
    return envOr<int>("COUNTER_DEPLOY_VALUE_NANOS", 5000000) as coins;
}

fun targetCounter(): Counter {
    val expected = Counter.fromStorage(Storage {
        id: 0,
        counter: 0,
    });
    val counterAddress = env<address>("COUNTER_ADDRESS");
    if (counterAddress == null) {
        return expected;
    }
    return Counter {
        address: counterAddress!,
        init: expected.init,
    };
}

fun main() {
    val delta = envOr<int>("COUNTER_DELTA", 1);
    val deployer = net.wallet("deployer");
    val deployValue = counterDeployValue();
    val counter = targetCounter();
    println1("Deploy value: {}", deployValue);
    if (!net.isDeployed(counter.address)) {
        counter.deploy(deployer.address, { value: deployValue }).wait();
    }

    println1("Increasing counter by {}", delta);
    val res = counter.sendIncreaseCounter(deployer.address, delta as uint32);
    res.wait();

    println1("Counter address: {}", counter.address);
    println1("COUNTER_ADDRESS={}", counter.address);
    println1("Current counter value: {}", counter.currentCounter());
}
