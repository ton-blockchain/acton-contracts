import "@stdlib/strings"
import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "../contracts/storage"
import "../tests/test_utils"
import "../tests/wrappers/DnsItem"

fun main() {
    val deployer = net.wallet("deployer-2");

    val itemAddress: address? = env("ITEM_ADDRESS");
    val dnsNameValue: string? = env("DNS_NAME_VALUE");
    val walletRecordAddress: address? = env("DNS_WALLET_ADDRESS");
    val newOwner: address? = env("DNS_NEW_OWNER");

    if (itemAddress == null) {
        println("Set ITEM_ADDRESS before running this script.");
        return;
    }

    val item = NftItemContract.fromAddress(itemAddress!);
    if (!net.isDeployed(item.address)) {
        println1("Item is not deployed in the current execution context: {}", item.address);
        return;
    }

    println("Using wallet: deployer-2");
    println1("Managing item: {}", item.address);

    if (dnsNameValue == null && walletRecordAddress == null && newOwner == null) {
        println("No changes requested. Set DNS_NAME_VALUE, DNS_WALLET_ADDRESS, or DNS_NEW_OWNER.");
    } else {
        if (dnsNameValue != null) {
            var records: DnsRecords = [];

            records.set("dns_name".toBase256(), dnsNameValue!.prefixWith00().toCell());

            val editResult = item.sendEditContent(
                deployer.address,
                1,
                records,
                { value: ton("0.1"), bounce: true },
            );

            if (!editResult.wait()) {
                println("Name record update was not confirmed");
                return;
            }
            println1("Updated dns_name record to {}", dnsNameValue!);
        }

        if (walletRecordAddress != null) {
            val changeRecord = item.sendChangeDnsRecord(
                deployer.address,
                2,
                "wallet".toBase256(),
                beginCell().storeRef(makeWalletRecord(walletRecordAddress!)).endCell().beginParse(),
                { value: ton("0.1"), bounce: true },
            );

            if (!changeRecord.wait()) {
                println("Wallet record update was not confirmed");
                return;
            }
            println1("Updated wallet record to {}", walletRecordAddress!);
        }

        if (newOwner != null) {
            val transferResult = item.sendTransferOwnership(
                deployer.address,
                3,
                {
                    newOwnerAddress: newOwner!,
                    responseDestination: null,
                    customPayload: null,
                    forwardAmount: 0,
                    forwardPayload: createEmptyCell().beginParse(),
                },
                { value: ton("0.2"), bounce: true },
            );
            if (!transferResult.wait()) {
                println("Ownership transfer was not confirmed");
                return;
            }
            println1("Transferred ownership to {}", newOwner!);
        }
    }

    val data = item.getNftData();

    println1("Item address: {}", item.address);
    println1("Initialized: {}", data.isInitialized);
    println1("Owner: {}", data.ownerAddress);

    if (data.isInitialized) {
        println1("Editor: {}", item.getEditor());
        println1("Last fill up time: {}", item.getLastFillUpTime());
        println1(
            "Wallet record present: {}",
            item.dnsresolve(makeDotSlice(), "wallet".toBase256()).resolvedRecord != null,
        );
    }
}
