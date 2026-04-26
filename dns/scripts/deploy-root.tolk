import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "../contracts/storage"
import "../tests/test-utils"
import "../wrappers/DnsRoot"

fun main() {
    val deployer = scripts.wallet("deployer-2");
    val root = RootDnsContract.fromStorage(RootDnsStorage {
        tonAddress: env("ROOT_TON_RESOLVER") ?? rootTonResolverAddress(),
        tMeAddress: env("ROOT_TME_RESOLVER") ?? rootTMeResolverAddress(),
        tonWwwAddress: env("ROOT_TON_WWW_RESOLVER") ?? rootTonWwwResolverAddress(),
    });

    println("Using wallet: deployer-2");
    println("Prepared root address: {}", root.address);

    val res = root.deploy(deployer.address, { value: ton("0.01"), bounce: false });
    if (res.waitForFirstTransaction() == null) {
        println("Root deployment was not confirmed");
        return;
    }

    println("Root deployed at {}", root.address);
    println("ROOT_ADDRESS={}", root.address);

    val ton = root.dnsresolve(makeTonDomainSlice(), 0);
    val tonWww = root.dnsresolve(makeTonWwwDomainSlice(), 0);
    val tMe = root.dnsresolve(makeTMeDomainSlice(), 0);

    println(
        ".ton resolver: {}",
        ton.resolvedRecord == null ? null : parseNextResolverCell(ton.resolvedRecord!),
    );
    println(
        ".ton.www resolver: {}",
        tonWww.resolvedRecord == null ? null : parseNextResolverCell(tonWww.resolvedRecord!),
    );
    println(
        ".t.me resolver: {}",
        tMe.resolvedRecord == null ? null : parseNextResolverCell(tMe.resolvedRecord!),
    );
}
