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
    val deployer = net.wallet("deployer-1");
    val deployValue = counterDeployValue();
    val counter = targetCounter();
    println1("Deploy value: {}", deployValue);
    if (!net.isDeployed(counter.address)) {
        counter.deploy(deployer.address, { value: deployValue }).wait();
    }

    val inc = counter.sendIncreaseCounter(deployer.address, 7);
    inc.wait();

    println1("Counter before reset: {}", counter.currentCounter());
    val res = counter.sendResetCounter(deployer.address);
    res.wait();

    println1("Counter address: {}", counter.address);
    println1("COUNTER_ADDRESS={}", counter.address);
    println1("Counter after reset: {}", counter.currentCounter());
}
