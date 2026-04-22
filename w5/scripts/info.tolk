import "@acton/emulation/network"
import "@acton/promts/prompts"
import "utils/common"

fun main() {
    val wallet = promptW5Target();
    printW5Info(wallet, "W5");
}
