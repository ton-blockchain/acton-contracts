import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"

import "../contracts/types"
import "../wrappers/Counter"

fun counterDeployValue(): coins {
    return env<coins>("COUNTER_DEPLOY_VALUE_NANOS") ?? 5000000;
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
    val deployer = scripts.wallet("deployer");
    val deployValue = counterDeployValue();
    val counterAddress = explicitCounterAddress();
    val counter = targetCounter();
    println("Deploy value: {}", deployValue);
    if (!scripts.isContractDeployed(counter.address)) {
        if (counterAddress != null) {
            println("Counter is not deployed at {}", counter.address);
            return;
        }
        counter.deploy(deployer.address, { value: deployValue }).wait();
    }

    println("Counter address: {}", counter.address);
    println("COUNTER_ADDRESS={}", counter.address);
    println("Current counter value: {}", counter.currentCounter());
}
