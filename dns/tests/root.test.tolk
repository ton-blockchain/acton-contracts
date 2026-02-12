import "test_utils"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "../contracts/constants"

get fun `test root: accepts plain top-up internal messages`() {
    val (root, _) = deployRootContract();
    val user = newActor("root_topup_user");

    val res = root.sendAny(user, createEmptyCell(), { value: ton("10"), bounce: true });
    expect(res).toHaveSuccessfulTx({ from: user, to: root.address });
}

get fun `test root: resolves .ton, .t.me, and ton\\0www`() {
    val (root, _) = deployRootContract();

    val (consumedTon, cellTon) = root.dnsresolve(makeTonDomainSlice(), 0);
    expect(consumedTon).toEqual(3 * 8);
    expect(cellTon).toNotEqual(null);
    val (prefixTon, resolverTon) = parseNextResolver(cellTon!!);
    expect(prefixTon).toEqual(DNS_NEXT_RESOLVER_PREFIX);
    expect(resolverTon).toEqual(collectionAddress1());

    val (consumedTMe, cellTMe) = root.dnsresolve(makeTMeDomainSlice(), 0);
    expect(consumedTMe).toEqual(4 * 8);
    expect(cellTMe).toNotEqual(null);
    val (prefixTMe, resolverTMe) = parseNextResolver(cellTMe!!);
    expect(prefixTMe).toEqual(DNS_NEXT_RESOLVER_PREFIX);
    expect(resolverTMe).toEqual(collectionAddress2());

    val (consumedWww, cellWww) = root.dnsresolve(makeTonWwwDomainSlice(), 0);
    expect(consumedWww).toEqual(7 * 8);
    expect(cellWww).toNotEqual(null);
    val (prefixWww, resolverWww) = parseNextResolver(cellWww!!);
    expect(prefixWww).toEqual(DNS_NEXT_RESOLVER_PREFIX);
    expect(resolverWww).toEqual(collectionAddress3());
}

get fun `test root: leading dot and unknown domains`() {
    val (root, _) = deployRootContract();

    val (consumedDot, dotCell) = root.dnsresolve(makeDotSlice(), 0);
    expect(consumedDot).toEqual(8);
    expect(dotCell).toEqual(null);

    val (consumedLeadingDotTon, cellLeadingDotTon) = root.dnsresolve(
        makeLeadingDot(makeTonDomainSlice()),
        0,
    );
    expect(consumedLeadingDotTon).toEqual(4 * 8);
    expect(cellLeadingDotTon).toNotEqual(null);

    val unknown = beginCell().storeSlice("vip".literalSlice()).storeUint(0, 8).endCell().beginParse();
    val (consumedUnknown, unknownCell) = root.dnsresolve(unknown, 0);
    expect(consumedUnknown).toEqual(0);
    expect(unknownCell).toEqual(null);
}
