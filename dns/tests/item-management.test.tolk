import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/tlb/maybe"
import "@acton/types/transaction"
import "test-utils"
import "../contracts/dns-utils"
import "../contracts/errors"
import "../contracts/messages"
import "../wrappers/DnsItem"

fun setupCompletedItem() {
    val (item, collection, owner, bidder) = deployItemThroughCollection();

    val complete = completeAuction(item, owner.address, 1);
    expect(complete).toHaveSuccessfulTx<FillUp>({ from: item.address, to: collection.address });

    return (item, collection, owner, bidder);
}

fun setupGovernanceReadyItem() {
    val (item, collection, owner, bidder) = deployItemThroughCollection();

    val higherBid = item.sendAny(
        bidder.address,
        createEmptyCell(),
        { value: ton("1050"), bounce: true },
    );
    expect(higherBid).toHaveSuccessfulTx<OutbidNotification>({
        from: item.address,
        to: owner.address,
    });

    val complete = completeAuction(item, bidder.address, 2);
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

get fun `test item management: ownership transfer covers payout branches and rejects invalid params`() {
    val (item, _, owner, _) = setupCompletedItem();
    val newOwner = newActor("item_transfer_branch_owner", ton("100"));
    val responseDestination = newActor("item_transfer_response_destination", ton("100"));

    val transferWithPayouts = item.sendTransferOwnership(
        owner.address,
        321,
        makeTransferData(
            newOwner.address,
            responseDestination.address,
            ton("0.5"),
            createEmptyCell().beginParse(),
        ),
        { value: ton("5"), bounce: true },
    );
    expect(transferWithPayouts).toHaveSuccessfulTx<OwnershipAssigned>({
        from: item.address,
        to: newOwner.address,
    });
    expect(transferWithPayouts).toHaveSuccessfulTx<Excesses>({
        from: item.address,
        to: responseDestination.address,
    });

    val assignedTx = transferWithPayouts.findTransaction<OwnershipAssigned>({
        from: item.address,
        to: newOwner.address,
        success: true,
    });
    expect(assignedTx).toBeNotNull();
    val assignedTxValue = assignedTx!.loadInMsg<OwnershipAssigned>();
    val assignedBody = assignedTx!.loadBody<OwnershipAssigned>();
    expect(assignedBody.queryId).toEqual(321);
    expect(assignedBody.oldOwnerAddress).toEqual(owner.address);
    expect(assignedTxValue.info.toInternal().value.grams).toEqual(ton("0.5"));

    val excessTx = transferWithPayouts.findTransaction<Excesses>({
        from: item.address,
        to: responseDestination.address,
        success: true,
    });
    expect(excessTx).toBeNotNull();
    val excessTxValue = excessTx!.loadInMsg<Excesses>();
    val excessBody = excessTx!.loadBody<Excesses>();
    expect(excessBody.queryId).toEqual(321);
    expect(excessTxValue.info.toInternal().value.grams).toBeGreater(0);

    expect(item.getEditor()).toEqual(newOwner.address);

    val invalidNewOwner = masterchainAddressOf(newActor("item_transfer_master_owner").address);
    val wrongOwnerTransfer = item.sendTransferOwnership(
        newOwner.address,
        322,
        makeTransferData(invalidNewOwner, null, 0, createEmptyCell().beginParse()),
        { value: ton("1"), bounce: true },
    );
    expect(wrongOwnerTransfer).toHaveFailedTx({
        from: newOwner.address,
        to: item.address,
        exitCode: ERROR_WRONG_WORKCHAIN,
    });

    val invalidResponseDestination = masterchainAddressOf(
        newActor("item_transfer_master_response").address,
    );
    val wrongResponseTransfer = item.sendTransferOwnership(
        newOwner.address,
        323,
        makeTransferData(
            owner.address,
            invalidResponseDestination,
            0,
            createEmptyCell().beginParse(),
        ),
        { value: ton("1"), bounce: true },
    );
    expect(wrongResponseTransfer).toHaveFailedTx({
        from: newOwner.address,
        to: item.address,
        exitCode: ERROR_WRONG_WORKCHAIN,
    });

    val insufficientBalance = item.sendTransferOwnership(
        newOwner.address,
        324,
        makeTransferData(
            owner.address,
            responseDestination.address,
            ton("10000"),
            createEmptyCell().beginParse(),
        ),
        { value: ton("1"), bounce: true },
    );
    expect(insufficientBalance).toHaveFailedTx({
        from: newOwner.address,
        to: item.address,
        exitCode: ERROR_NOT_ENOUGH_BALANCE,
    });

    expect(item.getEditor()).toEqual(newOwner.address);
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

get fun `test item management: governance is blocked while auction is active`() {
    val (item, _, _, caller) = deployItemThroughCollection();
    expect(testing.isDeployed(item.address)).toEqual(true);

    val governanceDuringAuction = item.sendProcessGovernanceDecision(
        caller.address,
        900,
        { value: ton("1"), bounce: true },
    );
    expect(governanceDuringAuction).toHaveFailedTx({
        from: caller.address,
        to: item.address,
        exitCode: ERROR_GOVERNANCE_REQUIRES_NO_AUCTION,
    });
}

get fun `test item management: governance requires an existing config entry`() {
    val (item, _, owner, _) = setupGovernanceReadyItem();
    val caller = newActor("item_governance_missing_entry_caller", ton("100000"));

    setGovernanceDecision(
        domainIndex("othergov"),
        GovernanceTransfer {
            transferData: makeTransferData(owner.address, null, 0, createEmptyCell().beginParse()),
        }.toCell()
            .beginParse(),
    );

    val missingEntry = item.sendProcessGovernanceDecision(
        caller.address,
        901,
        { value: ton("1"), bounce: true },
    );
    expect(missingEntry).toHaveFailedTx({
        from: caller.address,
        to: item.address,
        exitCode: ERROR_CONFIG_ENTRY_NOT_FOUND,
    });
}

get fun `test item management: governance release destroys the item and refunds collection`() {
    val (item, collection, _, _) = setupGovernanceReadyItem();
    val caller = newActor("item_governance_release_caller", ton("100000"));

    val collectionBalanceBefore = testing.getAccountBalance(collection.address);
    val nftData = item.getNftData();
    setGovernanceDecision(nftData.index, GovernanceRelease {}.toCell().beginParse());

    val governanceRelease = item.sendProcessGovernanceDecision(
        caller.address,
        902,
        { value: ton("1"), bounce: true },
    );
    expect(governanceRelease).toHaveSuccessfulTx<ProcessGovernanceDecision>({
        from: caller.address,
        to: item.address,
    });
    expect(governanceRelease).toHaveSuccessfulTx<FillUp>({
        from: item.address,
        to: collection.address,
    });

    val collectionFillUpTx = governanceRelease.findTransaction<FillUp>({
        from: item.address,
        to: collection.address,
        success: true,
    });
    expect(collectionFillUpTx).toBeNotNull();
    val collectionFillUp = collectionFillUpTx!.loadInMsg<FillUp>();
    expect(collectionFillUp.info.toInternal().value.grams).toBeGreater(0);
    expect(testing.getAccountBalance(collection.address)).toBeGreater(collectionBalanceBefore);
    expect(testing.isDeployed(item.address)).toEqual(false);
}

get fun `test item management: release boundaries, refunds, and unknown op handling`() {
    val (item, _, owner, bidder) = setupCompletedItem();

    val unknownOp = item.sendAny(
        owner.address,
        beginCell().storeUint(0x7FFFFFFF, 32).storeUint(1, 64).endCell(),
        { value: ton("1"), bounce: true },
    );
    expect(unknownOp).toHaveFailedTx({
        from: owner.address,
        to: item.address,
        exitCode: ERROR_UNKNOWN_OP,
    });

    val ownerTopUp = item.sendAny(
        owner.address,
        createEmptyCell(),
        { value: ton("2"), bounce: true },
    );
    expect(ownerTopUp).toHaveSuccessfulTx({ from: owner.address, to: item.address });

    val lastFillUp = item.getLastFillUpTime();
    testing.setNow((lastFillUp + ONE_YEAR));

    val releaseAtExactYear = item.sendDnsRecordRelease(
        bidder.address,
        700,
        { value: ton("20000"), bounce: true },
    );
    expect(releaseAtExactYear).toHaveFailedTx({
        from: bidder.address,
        to: item.address,
        exitCode: ERROR_DNS_BALANCE_RELEASE_FORBIDDEN,
    });

    testing.setNow((lastFillUp + ONE_YEAR + 1));
    val minReleaseBid = getMinPrice(item.getDomain().remainingBitsCount(), testing.getNow());

    val releaseBelowMin = item.sendDnsRecordRelease(
        bidder.address,
        701,
        { value: (minReleaseBid - 1), bounce: true },
    );
    expect(releaseBelowMin).toHaveFailedTx({
        from: bidder.address,
        to: item.address,
        exitCode: ERROR_BID_TOO_LOW,
    });

    val balanceBeforeRelease = testing.getAccountBalance(item.address);
    val releaseAtMin = item.sendDnsRecordRelease(
        bidder.address,
        702,
        { value: minReleaseBid, bounce: true },
    );
    expect(releaseAtMin).toHaveSuccessfulTx<DnsRecordRelease>({
        from: bidder.address,
        to: item.address,
    });

    val releaseRefundTx = releaseAtMin.findTransaction<DnsRecordRelease>({
        from: item.address,
        to: owner.address,
        success: true,
    });
    expect(releaseRefundTx).toBeNotNull();
    val releaseRefund = releaseRefundTx!.loadInMsg<DnsRecordRelease>();
    val maxReleaseRefund = balanceBeforeRelease - MIN_TONS_FOR_STORAGE;
    val releaseRefundInfo = releaseRefund.info.toInternal();
    expect(releaseRefundInfo.value.grams).toBeGreater(0);
    expect(releaseRefundInfo.value.grams).toBeLessOrEqual(maxReleaseRefund);

    expect(item.getEditor()).toBeNull();
    val restartedAuction = item.getAuctionInfo();
    expect(restartedAuction.maxBidAddress).toEqual(bidder.address);
    expect(restartedAuction.maxBidAmount).toEqual(minReleaseBid);
    expect(restartedAuction.auctionEndTime).toEqual((testing.getNow() + AUCTION_START_DURATION));
}

get fun `test item management: uninitialized getters expose default nft data`() {
    val (uninitItem, uninitCollection, _, _) = deployItemThroughCollection("ghost");
    setActiveDataCell(
        uninitItem.address,
        makeItemStorageNonInit(uninitCollection.address, "ghost").toCell(),
    );
    val uninitializedData = uninitItem.getNftData();
    expect(uninitializedData.isInitialized).toEqual(false);
    expect(uninitializedData.index).toEqual(domainIndex("ghost"));
    expect(uninitializedData.collectionAddress).toEqual(uninitCollection.address);
    expect(uninitializedData.ownerAddress).toBeNull();
    expect(uninitializedData.content).toBeNull();
    expect(uninitItem.getEditor()).toBeNull();
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
    expect(reportTx).toBeNotNull();

    val reportBody = reportTx!.loadBody<ReportStaticData>();
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
    testing.setNow((lastFillUp + ONE_YEAR + 1));

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
    expect(restartedAuction.auctionEndTime).toEqual((testing.getNow() + AUCTION_START_DURATION));
}
