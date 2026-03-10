import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "wrappers/DnsItem"
import "../contracts/dns-utils"
import "../contracts/errors"
import "../contracts/messages"

get fun `test item auction: initializes only from collection and handles repeated init`() {
    val collection = newActor("item_init_collection");
    val owner = newActor("item_init_owner", ton("100000"));
    val outsider = newActor("item_init_outsider", ton("100000"));

    net.setNow((AUCTION_START_TIME + 1) as uint32);
    val itemTemplate = NftItemContract.fromStorage(makeItemStorageNonInit(collection.address));
    expect(itemTemplate.stateInit).toBeNotNull();
    val initBody = makeItemInitBody(owner.address, DEFAULT_DOMAIN);

    val invalidDeploy = net.send(
        outsider.address,
        createMessage({
            bounce: true,
            value: ton("1000"),
            dest: { stateInit: itemTemplate.stateInit! },
            body: initBody,
        }),
    );
    expect(invalidDeploy).toHaveFailedTx({
        from: outsider.address,
        to: itemTemplate.address,
        exitCode: ERROR_NOT_FROM_COLLECTION,
    });

    val okDeploy = net.send(
        collection.address,
        createMessage({
            bounce: true,
            value: ton("1000"),
            dest: { stateInit: itemTemplate.stateInit! },
            body: initBody,
        }),
    );
    expect(okDeploy).toHaveSuccessfulTx({ from: collection.address, to: itemTemplate.address });

    val item = NftItemContract.fromAddress(itemTemplate.address);

    val nftData = item.getNftData();
    expect(nftData.isInitialized).toEqual(true);
    expect(nftData.index).toEqual(domainIndex(DEFAULT_DOMAIN));
    expect(item.getEditor()).toBeNull();

    val auctionInfo = item.getAuctionInfo();
    expect(auctionInfo.maxBidAddress).toEqual(owner.address);
    expect(auctionInfo.maxBidAmount).toEqual(ton("1000"));
    expect(auctionInfo.auctionEndTime).toEqual(
        (AUCTION_START_TIME + 1 + expectedAuctionDurationAt(AUCTION_START_TIME + 1)) as uint64,
    );

    val repeatedInit = item.sendAny(
        collection.address,
        initBody,
        { value: ton("1"), bounce: true },
    );
    expect(repeatedInit).toHaveSuccessfulTx({ from: collection.address, to: item.address });

    val auctionAfterRepeat = item.getAuctionInfo();
    expect(auctionAfterRepeat.maxBidAddress).toEqual(owner.address);
    expect(auctionAfterRepeat.maxBidAmount).toEqual(ton("1000"));
}

get fun `test item auction: bids require 5 percent and notify previous bidder`() {
    val (item, _, owner, bidder) = deployItemThroughCollection();

    val lowBid = item.sendAny(
        bidder.address,
        createEmptyCell(),
        { value: ton("1000"), bounce: true },
    );
    expect(lowBid).toHaveFailedTx({
        from: bidder.address,
        to: item.address,
        exitCode: ERROR_BID_TOO_LOW,
    });

    val validBid = item.sendAny(
        bidder.address,
        createEmptyCell(),
        { value: ton("1050"), bounce: true },
    );
    expect(validBid).toHaveSuccessfulTx<OutbidNotification>({
        from: item.address,
        to: owner.address,
    });

    val auctionAfterBid = item.getAuctionInfo();
    expect(auctionAfterBid.maxBidAddress).toEqual(bidder.address);
    expect(auctionAfterBid.maxBidAmount).toEqual(ton("1050"));
}

get fun `test item auction: prolongs end time when bid arrives in prolongation window`() {
    val (item, _, owner, bidder) = deployItemThroughCollection();

    val auctionBefore = item.getAuctionInfo();
    val nowAt = auctionBefore.auctionEndTime - AUCTION_PROLONGATION / 2;
    net.setNow(nowAt as uint32);

    val bid = item.sendAny(bidder.address, createEmptyCell(), { value: ton("2000"), bounce: true });
    expect(bid).toHaveSuccessfulTx<OutbidNotification>({ from: item.address, to: owner.address });

    val auctionAfter = item.getAuctionInfo();
    expect(auctionAfter.auctionEndTime).toEqual((net.now() + AUCTION_PROLONGATION) as uint64);
}

get fun `test item auction: completion sets owner and enforces top-up permissions`() {
    val (item, collection, owner, outsider) = deployItemThroughCollection();

    val complete = completeAuction(item, owner.address, 77);
    expect(complete).toHaveSuccessfulTx<FillUp>({ from: item.address, to: collection.address });

    expect(item.getEditor()).toEqual(owner.address);

    val ownerTopUp = item.sendAny(
        owner.address,
        createEmptyCell(),
        { value: ton("1"), bounce: true },
    );
    expect(ownerTopUp).toHaveSuccessfulTx({ from: owner.address, to: item.address });

    val outsiderTopUp = item.sendAny(
        outsider.address,
        createEmptyCell(),
        { value: ton("1"), bounce: true },
    );
    expect(outsiderTopUp).toHaveFailedTx({
        from: outsider.address,
        to: item.address,
        exitCode: ERROR_ONLY_OWNER_CAN_FILL_UP_AFTER_AUCTION,
    });
}
