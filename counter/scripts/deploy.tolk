import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"
import "../wrappers/Counter.gen"

fun main() {
    val deployer = scripts.wallet("deployer");

    val counter = targetCounter(deployer.address);
    val deployValue = counterDeployValue();
    println("Deploy value: {}", deployValue);
    if (!scripts.isContractDeployed(counter.address)) {
        if (explicitCounterAddress() != null) {
            println("Counter is not deployed at {}", counter.address);
            return;
        }
        val res = counter.deploy(deployer.address, { value: deployValue });
        println(res.waitForTrace());
    }

    println("Deployed counter to {}", counter.address);
    println("COUNTER_ADDRESS={}", counter.address);
    println("Counter owner is {}", counter.owner());
    println("Counter value is {}", counter.currentCounter());
}
