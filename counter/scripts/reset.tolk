import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"

import "../contracts/types"
import "../tests/wrappers/Counter"

fun counterDeployValue(): coins {
    return envOr("COUNTER_DEPLOY_VALUE_NANOS", 5000000);
}

fun explicitCounterAddress(): address? {
    return env("COUNTER_ADDRESS");
}

fun targetCounter(): Counter {
    val expected = Counter.fromStorage(Storage {
        id: 0,
        counter: 0,
    });
    val counterAddress = explicitCounterAddress();
    if (counterAddress == null) {
        return expected;
    }
    return Counter {
        address: counterAddress!,
        init: expected.init,
    };
}

fun main() {
    val deployer = net.wallet("deployer");
    val deployValue = counterDeployValue();
    val counterAddress = explicitCounterAddress();
    val counter = targetCounter();
    println1("Deploy value: {}", deployValue);
    if (!net.isDeployed(counter.address)) {
        if (counterAddress != null) {
            println1("Counter is not deployed at {}", counter.address);
            return;
        }
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
