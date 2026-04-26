import "@stdlib/strings"
import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "../contracts/storage"
import "../tests/test-utils"
import "../wrappers/DnsItem"

fun main() {
    val deployer = scripts.wallet("deployer-2");

    val itemAddress: address? = env("ITEM_ADDRESS");
    val dnsNameValue: string? = env("DNS_NAME_VALUE");
    val walletRecordAddress: address? = env("DNS_WALLET_ADDRESS");
    val newOwner: address? = env("DNS_NEW_OWNER");

    if (itemAddress == null) {
        println("Set ITEM_ADDRESS before running this script.");
        return;
    }

    val item = NftItemContract.fromAddress(itemAddress!);
    if (!scripts.isContractDeployed(item.address)) {
        println("Item is not deployed in the current execution context: {}", item.address);
        return;
    }

    println("Using wallet: deployer-2");
    println("Managing item: {}", item.address);

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

            if (editResult.waitForFirstTransaction() == null) {
                println("Name record update was not confirmed");
                return;
            }
            println("Updated dns_name record to {}", dnsNameValue!);
        }

        if (walletRecordAddress != null) {
            val changeRecord = item.sendChangeDnsRecord(
                deployer.address,
                2,
                "wallet".toBase256(),
                beginCell().storeRef(makeWalletRecord(walletRecordAddress!)).endCell().beginParse(),
                { value: ton("0.1"), bounce: true },
            );

            if (changeRecord.waitForFirstTransaction() == null) {
                println("Wallet record update was not confirmed");
                return;
            }
            println("Updated wallet record to {}", walletRecordAddress!);
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
            if (transferResult.waitForFirstTransaction() == null) {
                println("Ownership transfer was not confirmed");
                return;
            }
            println("Transferred ownership to {}", newOwner!);
        }
    }

    val data = item.getNftData();

    println("Item address: {}", item.address);
    println("Initialized: {}", data.isInitialized);
    println("Owner: {}", data.ownerAddress);

    if (data.isInitialized) {
        println("Editor: {}", item.getEditor());
        println("Last fill up time: {}", item.getLastFillUpTime());
        println(
            "Wallet record present: {}",
            item.dnsresolve(makeDotSlice(), "wallet".toBase256()).resolvedRecord != null,
        );
    }
}
