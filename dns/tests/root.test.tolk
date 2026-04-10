import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test-utils"
import "../contracts/dns-utils"
import "../wrappers/DnsRoot"

get fun `test root: accepts plain top-up messages`() {
    val (root, _) = deployRootContract();
    val user = newActor("root_topup_user");

    val res = root.sendAny(user.address, createEmptyCell(), { value: ton("10"), bounce: true });
    expect(res).toHaveSuccessfulTx({ from: user.address, to: root.address });
}

get fun `test root: resolves ton, t.me, and ton.www according to resolver mapping`() {
    val (root, _) = deployRootContract();

    val tonResolved = root.dnsresolve(makeTonDomainSlice(), 0);
    expect(tonResolved.resolvedPrefixLengthBits).toEqual(3 * BYTE_SIZE);
    expect(tonResolved.resolvedRecord).toBeNotNull();
    expect(parseNextResolverCell(tonResolved.resolvedRecord!)).toEqual(rootTonResolverAddress());

    val tonLeadingResolved = root.dnsresolve(makeLeadingZero(makeTonDomainSlice()), 777);
    expect(tonLeadingResolved.resolvedPrefixLengthBits).toEqual(4 * BYTE_SIZE);
    expect(tonLeadingResolved.resolvedRecord).toBeNotNull();
    expect(parseNextResolverCell(tonLeadingResolved.resolvedRecord!)).toEqual(
        rootTonResolverAddress(),
    );

    val tonWithTailResolved = root.dnsresolve(makeLabelAndTailSlice("ton", "alice"), 123456);
    expect(tonWithTailResolved.resolvedPrefixLengthBits).toEqual(3 * BYTE_SIZE);
    expect(tonWithTailResolved.resolvedRecord).toBeNotNull();
    expect(parseNextResolverCell(tonWithTailResolved.resolvedRecord!)).toEqual(
        rootTonResolverAddress(),
    );

    val tMeResolved = root.dnsresolve(makeTMeDomainSlice(), 0);
    expect(tMeResolved.resolvedPrefixLengthBits).toEqual(4 * BYTE_SIZE);
    expect(tMeResolved.resolvedRecord).toBeNotNull();
    expect(parseNextResolverCell(tMeResolved.resolvedRecord!)).toEqual(rootTMeResolverAddress());

    val tonWwwResolved = root.dnsresolve(makeTonWwwDomainSlice(), 0);
    expect(tonWwwResolved.resolvedPrefixLengthBits).toEqual(7 * BYTE_SIZE);
    expect(tonWwwResolved.resolvedRecord).toBeNotNull();
    expect(parseNextResolverCell(tonWwwResolved.resolvedRecord!)).toEqual(
        rootTonWwwResolverAddress(),
    );
}

get fun `test root: keeps short and shape-mismatched domains unresolved`() {
    val (root, _) = deployRootContract();

    val shortPlain = root.dnsresolve(makeLabelDomainSlice("a"), 0);
    expect(shortPlain.resolvedPrefixLengthBits).toEqual(0);
    expect(shortPlain.resolvedRecord).toBeNull();

    val shortLeading = root.dnsresolve(makeLeadingZero(makeLabelDomainSlice("a")), 0);
    expect(shortLeading.resolvedPrefixLengthBits).toEqual(0);
    expect(shortLeading.resolvedRecord).toBeNull();

    val fakeTelegram = root.dnsresolve(makeLabelAndTailSlice("me", "x"), 0);
    expect(fakeTelegram.resolvedPrefixLengthBits).toEqual(0);
    expect(fakeTelegram.resolvedRecord).toBeNull();
}

get fun `test root: resolves dot and unknown domains per TEP-81 behavior`() {
    val (root, _) = deployRootContract();

    val dotResolved = root.dnsresolve(makeDotSlice(), 0);
    expect(dotResolved.resolvedPrefixLengthBits).toEqual(BYTE_SIZE);
    expect(dotResolved.resolvedRecord).toBeNull();

    val unknown = makeLabelDomainSlice("vip");
    val unknownResolved = root.dnsresolve(unknown, 0);
    expect(unknownResolved.resolvedPrefixLengthBits).toEqual(0);
    expect(unknownResolved.resolvedRecord).toBeNull();
}
