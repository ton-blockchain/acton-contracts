import "test_utils"
import "wrappers/DnsCollection"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "../contracts/dns-utils"
import "../contracts/errors"

get fun `test collection: validates domain format and minimum bid rules`() {
    val (collection, _, user) = deployCollectionContract();

    net.setNow((AUCTION_START_TIME - 1) as uint32);
    val beforeStart = collection.sendAny(
        user.address,
        makeDeployBody("appl"),
        { value: ton("1000"), bounce: true }
    );
    expect(beforeStart).toHaveFailedTx({
        to: collection.address,
        exitCode: ERROR_AUCTION_NOT_STARTED,
    });

    net.setNow((AUCTION_START_TIME + 1) as uint32);

    val tooShort = collection.sendAny(
        user.address,
        makeDeployBody("bob"),
        { value: ton("1000"), bounce: true }
    );
    expect(tooShort).toHaveFailedTx({ to: collection.address, exitCode: ERROR_DOMAIN_TOO_SHORT });

    val tooLong = collection.sendAny(
        user.address,
        makeDeployBodyFromDomain(repeatAsciiChar(97, 127)),
        { value: ton("1000"), bounce: true }
    );
    expect(tooLong).toHaveFailedTx({ to: collection.address, exitCode: ERROR_DOMAIN_TOO_LONG });

    val nonByteAligned = beginCell().storeUint(0, 32).storeSlice("alice".beginParse()).storeUint(
        1,
        1
    )
        .endCell();
    val badBits = collection.sendAny(
        user.address,
        nonByteAligned,
        { value: ton("1000"), bounce: true }
    );
    expect(badBits).toHaveFailedTx({ to: collection.address, exitCode: ERROR_DOMAIN_FORMAT_INVALID });

    val invalidChar = collection.sendAny(
        user.address,
        makeDeployBody("aLice"),
        { value: ton("1000"), bounce: true }
    );
    expect(invalidChar).toHaveFailedTx({
        to: collection.address,
        exitCode: ERROR_DOMAIN_HAS_INVALID_CHARS,
    });

    val lowBid = collection.sendAny(
        user.address,
        makeDeployBody("appl"),
        { value: ton("999"), bounce: true }
    );
    expect(lowBid).toHaveFailedTx({ to: collection.address, exitCode: ERROR_BID_BELOW_MIN_PRICE });

    val atMinBid = collection.sendAny(
        user.address,
        makeDeployBody("appl"),
        { value: ton("1000"), bounce: true }
    );
    expect(atMinBid).toHaveSuccessfulTx({ to: collection.address });

    val deployedItem = atMinBid.findTransaction({ from: collection.address, deploy: true });
    expect(deployedItem).toBeDefined();

    val expectedAddress = collection.getNftAddressByIndex(domainIndex("appl") as int);
    expect(deployedItem.unwrap().getAccountAddress()).toEqual(expectedAddress);
}

get fun `test collection: denies deployment for blacklisted domains via config param 80`() {
    val (collection, _, user) = deployCollectionContract();
    net.setNow((AUCTION_START_TIME + 1) as uint32);

    val blockedDomain = "evil";
    setDnsBlacklist(domainIndex(blockedDomain));

    val res = collection.sendAny(
        user.address,
        makeDeployBody(blockedDomain),
        { value: ton("1000"), bounce: true }
    );
    expect(res).toHaveFailedTx({ to: collection.address, exitCode: ERROR_DOMAIN_IS_BLACKLISTED });
}

get fun `test collection: dnsresolve returns next-resolver for top label and dot handling`() {
    val (collection, _, _) = deployCollectionContract();

    val dotResolved = collection.dnsresolve(makeDotSlice(), 0);
    expect(dotResolved.resolvedPrefixLengthBits).toEqual(BYTE_SIZE);
    expect(dotResolved.resolvedRecord).toBeNull();

    val expectedItem = collection.getNftAddressByIndex(domainIndex("alice") as int);

    val aliceResolved = collection.dnsresolve(makeLabelDomainSlice("alice"), 1234);
    expect(aliceResolved.resolvedPrefixLengthBits).toEqual(5 * BYTE_SIZE);
    expect(aliceResolved.resolvedRecord).toBeNotNull();
    expect(parseNextResolverCell(aliceResolved.resolvedRecord!)).toEqual(expectedItem);

    val aliceTailResolved = collection.dnsresolve(makeLabelAndTailSlice("alice", "sub"), 0);
    expect(aliceTailResolved.resolvedPrefixLengthBits).toEqual(5 * BYTE_SIZE);
    expect(aliceTailResolved.resolvedRecord).toBeNotNull();
    expect(parseNextResolverCell(aliceTailResolved.resolvedRecord!)).toEqual(expectedItem);

    val leadingResolved = collection.dnsresolve(makeLeadingZero(makeLabelDomainSlice("alice")), 0);
    expect(leadingResolved.resolvedPrefixLengthBits).toEqual(6 * BYTE_SIZE);
    expect(leadingResolved.resolvedRecord).toBeNotNull();
    expect(parseNextResolverCell(leadingResolved.resolvedRecord!)).toEqual(expectedItem);
}

get fun `test collection: getters are stable and content getter is pass-through`() {
    val (collection, _, _) = deployCollectionContract();

    val data = collection.getCollectionData();
    expect(data.nextItemIndex).toEqual(-1);
    expect(data.ownerAddress).toBeNull();
    expect(data.content.hash()).toEqual(makeCollectionContentCell().hash());

    val idx = domainIndex("alice") as int;
    val addr1 = collection.getNftAddressByIndex(idx);
    val addr2 = collection.getNftAddressByIndex(idx);
    expect(addr1).toEqual(addr2);

    val sampleContent = makeDnsTextRecord("pass-through");
    val passthrough = collection.getNftContent(0, sampleContent);
    expect(passthrough.hash()).toEqual(sampleContent.hash());
}
