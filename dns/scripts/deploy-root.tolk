import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "../contracts/storage"
import "../tests/test_utils"
import "../tests/wrappers/DnsRoot"

fun main() {
    val deployer = net.wallet("deployer-2");
    val root = RootDnsContract.fromStorage(RootDnsStorage {
        tonAddress: env("ROOT_TON_RESOLVER") ?? rootTonResolverAddress(),
        tMeAddress: env("ROOT_TME_RESOLVER") ?? rootTMeResolverAddress(),
        tonWwwAddress: env("ROOT_TON_WWW_RESOLVER") ?? rootTonWwwResolverAddress(),
    });

    println("Using wallet: deployer-2");
    println1("Prepared root address: {}", root.address);

    val res = root.deploy(deployer.address, { value: ton("0.01"), bounce: false });
    if (!res.wait()) {
        println("Root deployment was not confirmed");
        return;
    }

    println1("Root deployed at {}", root.address);
    println1("ROOT_ADDRESS={}", root.address);

    val ton = root.dnsresolve(makeTonDomainSlice(), 0);
    val tonWww = root.dnsresolve(makeTonWwwDomainSlice(), 0);
    val tMe = root.dnsresolve(makeTMeDomainSlice(), 0);

    println1(
        ".ton resolver: {}",
        ton.resolvedRecord == null ? null : parseNextResolverCell(ton.resolvedRecord!),
    );
    println1(
        ".ton.www resolver: {}",
        tonWww.resolvedRecord == null ? null : parseNextResolverCell(tonWww.resolvedRecord!),
    );
    println1(
        ".t.me resolver: {}",
        tMe.resolvedRecord == null ? null : parseNextResolverCell(tMe.resolvedRecord!),
    );
}
