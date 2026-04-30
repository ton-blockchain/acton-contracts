import "@acton/env"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"
import "../contracts/storage"
import "../wrappers/Config.gen"

fun main() {
    val sender = promptConfigWallet("CONFIG_CUSTOM_ADMIN", "Select Custom-Param Admin ActonWallet");
    val contract = promptConfigContract("Enter Config contract address");

    val paramId = promptConfigInt(
        "CONFIG_CUSTOM_PARAM_ID",
        "Enter custom param id (-1024 = slot 1, -1025 = slot 2)",
        CONFIG_DEFAULT_PARAM_ID,
    ) as int32;

    val receiver = promptConfigAddress(
        "CONFIG_CUSTOM_RECEIVER",
        "Enter receiver address for confirmation",
        sender.address,
    );

    val value = promptConfigCellRequired(
        "CONFIG_CUSTOM_VALUE",
        "BoC value to write into the custom slot",
    );

    val queryId = promptConfigInt("CONFIG_QUERY_ID", "Enter query id", CONFIG_DEFAULT_QUERY_ID);
    val msgValue = promptConfigCoins(
        "CONFIG_CUSTOM_VALUE_TON",
        "Enter message value",
        CONFIG_DEFAULT_CUSTOM_VALUE,
    );

    println("CONFIG CUSTOM_ADMIN={}", sender.address);
    println("CONFIG ADMIN_EXPECTED={}", ADMIN_ADDRESS_FOR_CUSTOM_PARAMS);
    if (sender.address != ADMIN_ADDRESS_FOR_CUSTOM_PARAMS) {
        println("CONFIG WARNING=sender does not match the hardcoded custom-params admin; the contract will reject the message");
    }

    val res = contract.sendSetCustomParamRequest(
        sender.address,
        queryId,
        paramId,
        receiver,
        value,
        { value: msgValue, bounce: true },
    );
    res.waitForFirstTransaction();

    printConfigInfo(contract, "CONFIG");
}
