import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/tlb/maybe"
import "@acton/types/transaction"
import "test-utils"
import "../contracts/dns-utils"
import "../contracts/errors"
import "../wrappers/DnsCollection"

get fun `test collection: validates domain format and minimum bid rules`() {
    val (collection, _, user) = deployCollectionContract();

    testing.setNow((AUCTION_START_TIME - 1));
    val beforeStart = collection.sendAny(
        user.address,
        makeDeployBody("appl"),
        { value: ton("1000"), bounce: true },
    );
    expect(beforeStart).toHaveFailedTx({
        to: collection.address,
        exitCode: ERROR_AUCTION_NOT_STARTED,
    });

    testing.setNow((AUCTION_START_TIME + 1));

    val tooShort = collection.sendAny(
        user.address,
        makeDeployBody("bob"),
        { value: ton("1000"), bounce: true },
    );
    expect(tooShort).toHaveFailedTx({ to: collection.address, exitCode: ERROR_DOMAIN_TOO_SHORT });

    val tooLong = collection.sendAny(
        user.address,
        makeDeployBodyFromDomain(repeatAsciiChar(97, 127)),
        { value: ton("1000"), bounce: true },
    );
    expect(tooLong).toHaveFailedTx({ to: collection.address, exitCode: ERROR_DOMAIN_TOO_LONG });

    val nonByteAligned = beginCell()
        .storeUint(0, 32)
        .storeSlice("alice".beginParse())
        .storeUint(1, 1)
        .endCell();
    val badBits = collection.sendAny(
        user.address,
        nonByteAligned,
        { value: ton("1000"), bounce: true },
    );
    expect(badBits).toHaveFailedTx({
        to: collection.address,
        exitCode: ERROR_DOMAIN_FORMAT_INVALID,
    });

    val invalidChar = collection.sendAny(
        user.address,
        makeDeployBody("aLice"),
        { value: ton("1000"), bounce: true },
    );
    expect(invalidChar).toHaveFailedTx({
        to: collection.address,
        exitCode: ERROR_DOMAIN_HAS_INVALID_CHARS,
    });

    val lowBid = collection.sendAny(
        user.address,
        makeDeployBody("appl"),
        { value: ton("999"), bounce: true },
    );
    expect(lowBid).toHaveFailedTx({ to: collection.address, exitCode: ERROR_BID_BELOW_MIN_PRICE });

    val atMinBid = collection.sendAny(
        user.address,
        makeDeployBody("appl"),
        { value: ton("1000"), bounce: true },
    );
    expect(atMinBid).toHaveSuccessfulTx({ to: collection.address });

    val deployedItem = atMinBid.findTransaction({ from: collection.address, deploy: true });
    expect(deployedItem).toBeNotNull();

    val expectedAddress = collection.getNftAddressByIndex(domainIndex("appl"));
    expect(deployedItem!.getAccountAddress()).toEqual(expectedAddress);
}

get fun `test collection: covers exact launch, max-length, hyphen, and decay boundaries`() {
    val (collection, _, user) = deployCollectionContract();

    testing.setNow(AUCTION_START_TIME);
    val exactStart = collection.sendAny(
        user.address,
        makeDeployBody("edge"),
        { value: ton("1000"), bounce: true },
    );
    expect(exactStart).toHaveFailedTx({
        to: collection.address,
        exitCode: ERROR_AUCTION_NOT_STARTED,
    });

    testing.setNow((AUCTION_START_TIME + 1));

    val maxLengthDeploy = collection.sendAny(
        user.address,
        makeDeployBodyFromDomain(repeatAsciiChar(97, 126)),
        { value: ton("10"), bounce: true },
    );
    expect(maxLengthDeploy).toHaveSuccessfulTx({ from: user.address, to: collection.address });
    expect(
        maxLengthDeploy.findTransaction({ from: collection.address, deploy: true }),
    ).toBeNotNull();

    val hyphenValid = collection.sendAny(
        user.address,
        makeDeployBody("ab-c"),
        { value: ton("1000"), bounce: true },
    );
    expect(hyphenValid).toHaveSuccessfulTx({ from: user.address, to: collection.address });

    val hyphenAtStart = collection.sendAny(
        user.address,
        makeDeployBody("-abc"),
        { value: ton("1000"), bounce: true },
    );
    expect(hyphenAtStart).toHaveFailedTx({
        from: user.address,
        to: collection.address,
        exitCode: ERROR_DOMAIN_HAS_INVALID_CHARS,
    });

    val hyphenAtEnd = collection.sendAny(
        user.address,
        makeDeployBody("abc-"),
        { value: ton("1000"), bounce: true },
    );
    expect(hyphenAtEnd).toHaveFailedTx({
        from: user.address,
        to: collection.address,
        exitCode: ERROR_DOMAIN_HAS_INVALID_CHARS,
    });

    testing.setNow((AUCTION_START_TIME + ONE_MONTH + 1));

    val monthBoundaryLow = collection.sendAny(
        user.address,
        makeDeployBody("month"),
        { value: ton("449"), bounce: true },
    );
    expect(monthBoundaryLow).toHaveFailedTx({
        to: collection.address,
        exitCode: ERROR_BID_BELOW_MIN_PRICE,
    });

    val monthBoundaryExact = collection.sendAny(
        user.address,
        makeDeployBody("month"),
        { value: ton("450"), bounce: true },
    );
    expect(monthBoundaryExact).toHaveSuccessfulTx({ from: user.address, to: collection.address });

    testing.setNow((AUCTION_START_TIME + 24 * ONE_MONTH));

    val floorBoundaryLow = collection.sendAny(
        user.address,
        makeDeployBody("floor"),
        { value: ton("49"), bounce: true },
    );
    expect(floorBoundaryLow).toHaveFailedTx({
        to: collection.address,
        exitCode: ERROR_BID_BELOW_MIN_PRICE,
    });

    val floorBoundaryExact = collection.sendAny(
        user.address,
        makeDeployBody("floor"),
        { value: ton("50"), bounce: true },
    );
    expect(floorBoundaryExact).toHaveSuccessfulTx({ from: user.address, to: collection.address });
}

get fun `test collection: rejects malformed snake payloads and unknown opcodes`() {
    val (collection, _, user) = deployCollectionContract();
    testing.setNow((AUCTION_START_TIME + 1));

    val malformedSnakeBody = beginCell()
        .storeUint(0, 32)
        .storeSlice("ab".beginParse())
        .storeRef(beginCell().storeSlice("cd".beginParse()).endCell())
        .storeRef(beginCell().storeSlice("ef".beginParse()).endCell())
        .endCell();
    val malformedSnake = collection.sendAny(
        user.address,
        malformedSnakeBody,
        { value: ton("1000"), bounce: true },
    );
    expect(malformedSnake).toHaveFailedTx({
        from: user.address,
        to: collection.address,
        exitCode: ERROR_DOMAIN_FORMAT_INVALID,
    });

    val unknownOp = collection.sendAny(
        user.address,
        beginCell().storeUint(0x7FFFFFFF, 32).storeUint(1, 64).endCell(),
        { value: ton("1"), bounce: true },
    );
    expect(unknownOp).toHaveFailedTx({
        from: user.address,
        to: collection.address,
        exitCode: ERROR_UNKNOWN_OP,
    });
}

get fun `test collection: denies deployment for blacklisted domains via config param 80`() {
    val (collection, _, user) = deployCollectionContract();
    testing.setNow((AUCTION_START_TIME + 1));

    val blockedDomain = "evil";
    setDnsBlacklist(domainIndex(blockedDomain));

    val res = collection.sendAny(
        user.address,
        makeDeployBody(blockedDomain),
        { value: ton("1000"), bounce: true },
    );
    expect(res).toHaveFailedTx({ to: collection.address, exitCode: ERROR_DOMAIN_IS_BLACKLISTED });
}

get fun `test collection: dnsresolve returns next-resolver for top label and dot handling`() {
    val (collection, _, _) = deployCollectionContract();

    val dotResolved = collection.dnsresolve(makeDotSlice(), 0);
    expect(dotResolved.resolvedPrefixLengthBits).toEqual(BYTE_SIZE);
    expect(dotResolved.resolvedRecord).toBeNull();

    val expectedItem = collection.getNftAddressByIndex(domainIndex("alice"));

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

    val idx = domainIndex("alice");
    val addr1 = collection.getNftAddressByIndex(idx);
    val addr2 = collection.getNftAddressByIndex(idx);
    expect(addr1).toEqual(addr2);

    val sampleContent = makeDnsTextRecord("pass-through");
    val passthrough = collection.getNftContent(0, sampleContent);
    expect(passthrough.hash()).toEqual(sampleContent.hash());
}
