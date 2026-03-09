import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "../contracts/dns-utils"
import "../contracts/errors"
import "../contracts/messages"
import "test_utils"

fun setupCompletedItem() {
    val (item, collection, owner, bidder) = deployItemThroughCollection();

    val complete = completeAuction(item, owner.address, 1);
    expect(complete).toHaveSuccessfulTx<FillUp>({ from: item.address, to: collection.address });

    return (item, collection, owner, bidder);
}

get fun `test item management: ownership transfer updates editor and blocks old owner`() {
    val (item, _, owner, outsider) = setupCompletedItem();
    val newOwner = newActor("item_transfer_new_owner", ton("100"));

    val transfer = item.sendTransferOwnership(
        owner.address,
        123,
        makeTransferData(newOwner.address, null, ton("0.5"), createEmptyCell().beginParse()),
        { value: ton("5"), bounce: true },
    );
    expect(transfer).toHaveSuccessfulTx<OwnershipAssigned>({
        from: item.address,
        to: newOwner.address,
    });

    expect(item.getEditor()).toEqual(newOwner.address);

    val oldOwnerAttempt = item.sendTransferOwnership(
        owner.address,
        124,
        makeTransferData(outsider.address, null, 0, createEmptyCell().beginParse()),
        { value: ton("1"), bounce: true },
    );
    expect(oldOwnerAttempt).toHaveFailedTx({
        from: owner.address,
        to: item.address,
        exitCode: ERROR_NOT_OWNER,
    });
}

get fun `test item management: owner can edit content and mutate DNS records`() {
    val (item, _, owner, outsider) = setupCompletedItem();

    val edited = makeRecordMapWithName("alice-edited.ton");
    val editTx = item.sendEditContent(owner.address, 1, edited, { value: ton("1"), bounce: true });
    expect(editTx).toHaveSuccessfulTx({ from: owner.address, to: item.address });

    val nftData = item.getNftData();
    expect(nftData.content).toBeNotNull();
    expect(nftData.content!.hash()).toEqual(edited.toCell().hash());

    val forbiddenEdit = item.sendEditContent(
        outsider.address,
        2,
        edited,
        { value: ton("1"), bounce: true },
    );
    expect(forbiddenEdit).toHaveFailedTx({
        from: outsider.address,
        to: item.address,
        exitCode: ERROR_ONLY_OWNER_CAN_EDIT_CONTENT,
    });

    val wallet = newActor("item_wallet_record");
    val walletRecord = makeWalletRecord(wallet.address);

    val addRecord = item.sendChangeDnsRecord(
        owner.address,
        3,
        DNS_WALLET_CATEGORY,
        beginCell().storeRef(walletRecord).endCell().beginParse(),
        { value: ton("1"), bounce: true },
    );
    expect(addRecord).toHaveSuccessfulTx({ from: owner.address, to: item.address });

    val walletResolved = item.dnsresolve(makeDotSlice(), DNS_WALLET_CATEGORY);
    expect(walletResolved.resolvedPrefixLengthBits).toEqual(BYTE_SIZE);
    expect(walletResolved.resolvedRecord).toBeNotNull();
    expect(walletResolved.resolvedRecord!.hash()).toEqual(walletRecord.hash());

    val removeRecord = item.sendChangeDnsRecord(
        owner.address,
        4,
        DNS_WALLET_CATEGORY,
        createEmptyCell().beginParse(),
        { value: ton("1"), bounce: true },
    );
    expect(removeRecord).toHaveSuccessfulTx({ from: owner.address, to: item.address });

    val removedWallet = item.dnsresolve(makeDotSlice(), DNS_WALLET_CATEGORY);
    expect(removedWallet.resolvedRecord).toBeNull();

    val forbiddenChange = item.sendChangeDnsRecord(
        outsider.address,
        5,
        DNS_WALLET_CATEGORY,
        beginCell().storeRef(walletRecord).endCell().beginParse(),
        { value: ton("1"), bounce: true },
    );
    expect(forbiddenChange).toHaveFailedTx({
        from: outsider.address,
        to: item.address,
        exitCode: ERROR_ONLY_OWNER_CAN_CHANGE_DNS,
    });
}

get fun `test item management: dnsresolve follows TEP-81 category and next-resolver rules`() {
    val (item, _, owner, _) = setupCompletedItem();
    val nextResolver = newActor("item_next_resolver");
    val nextResolverCell = DnsNextResolver { resolver: nextResolver.address }.toCell();

    val setNextResolver = item.sendChangeDnsRecord(
        owner.address,
        11,
        DNS_NEXT_RESOLVER_CATEGORY,
        beginCell().storeRef(nextResolverCell).endCell().beginParse(),
        { value: ton("1"), bounce: true },
    );
    expect(setNextResolver).toHaveSuccessfulTx({ from: owner.address, to: item.address });

    val allRecords = item.dnsresolve(makeDotSlice(), 0);
    expect(allRecords.resolvedPrefixLengthBits).toEqual(BYTE_SIZE);
    expect(allRecords.resolvedRecord).toBeNotNull();

    val subResolved = item.dnsresolve(makeRelativeSubdomainSlice("child"), 0x123456);
    expect(subResolved.resolvedPrefixLengthBits).toEqual(BYTE_SIZE);
    expect(subResolved.resolvedRecord).toBeNotNull();
    expect(subResolved.resolvedRecord!.hash()).toEqual(nextResolverCell.hash());

    val missing = item.dnsresolve(makeDotSlice(), "site".toBase256());
    expect(missing.resolvedRecord).toBeNull();
}

get fun `test item management: static data, governance guard, and release flow invariants`() {
    val (item, _, _owner, _) = setupCompletedItem();
    val requester = newActor("item_static_requester");

    val staticData = item.sendGetStaticData(
        requester.address,
        555,
        { value: ton("1"), bounce: true },
    );
    expect(staticData).toHaveSuccessfulTx<ReportStaticData>({
        from: item.address,
        to: requester.address,
    });

    val reportTx = staticData.findTransaction<ReportStaticData>({
        from: item.address,
        to: requester.address,
        success: true,
        exitCode: 0,
    });
    expect(reportTx).toBeDefined();

    val reportBody = reportTx.unwrap().loadBody<ReportStaticData>();
    val nftData = item.getNftData();
    expect(reportBody.itemIndex).toEqual(nftData.index);
    expect(reportBody.collectionAddress).toEqual(nftData.collectionAddress);

    val governance = item.sendProcessGovernanceDecision(
        requester.address,
        42,
        { value: ton("1"), bounce: true },
    );
    expect(governance).toHaveFailedTx({
        from: requester.address,
        to: item.address,
        exitCode: ERROR_CONFIG_ENTRY_NOT_FOUND,
    });

    val bidder = newActor("item_release_bidder", ton("100000"));

    val earlyRelease = item.sendDnsRecordRelease(
        bidder.address,
        1,
        { value: ton("20000"), bounce: true },
    );
    expect(earlyRelease).toHaveFailedTx({
        from: bidder.address,
        to: item.address,
        exitCode: ERROR_DNS_BALANCE_RELEASE_FORBIDDEN,
    });

    val lastFillUp = item.getLastFillUpTime();
    net.setNow((lastFillUp + ONE_YEAR + 1) as uint32);

    val release = item.sendDnsRecordRelease(
        bidder.address,
        2,
        { value: ton("20000"), bounce: true },
    );
    expect(release).toHaveSuccessfulTx<DnsRecordRelease>({
        from: bidder.address,
        to: item.address,
    });

    expect(item.getEditor()).toBeNull();

    val restartedAuction = item.getAuctionInfo();
    expect(restartedAuction.maxBidAddress).toEqual(bidder.address);
    expect(restartedAuction.maxBidAmount).toEqual(ton("20000"));
    expect(restartedAuction.auctionEndTime).toEqual((net.now() + AUCTION_START_DURATION) as uint64);
}
