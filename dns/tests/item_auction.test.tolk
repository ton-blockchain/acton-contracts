import "test_utils"
import "wrappers/DnsItem"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "../contracts/errors"
import "../contracts/messages"
import "../contracts/constants"

get fun `test item: initializes only from collection and responds to repeated init`() {
    val collectionSender = newActor("item_collection_sender");
    val owner = newActor("item_owner_sender");

    val item = NftItemContract.fromStorage(makeItemStorageNonInit(collectionSender));
    val deployRes = item.deploy(owner, { value: ton("1"), bounce: true });
    expect(deployRes).toHaveSuccessfulDeploy({ to: item.address });

    val initBody = makeItemInitBody(owner, "alice");

    val invalidInit = item.sendAny(
        owner,
        initBody,
        { value: ton("1000"), bounce: true },
    );
    expect(invalidInit).toHaveFailedTx({
        from: owner,
        to: item.address,
        exitCode: ERROR_NOT_FROM_COLLECTION,
    });

    val okInit = item.sendAny(
        collectionSender,
        initBody,
        { value: ton("1000"), bounce: true },
    );
    expect(okInit).toHaveSuccessfulTx({
        from: collectionSender,
        to: item.address,
    });

    val (maxBidder, maxBidAmount, auctionEndTime) = item.get_auction_info();
    expect(maxBidder).toEqual(owner);
    expect(maxBidAmount).toEqual(ton("1000"));
    expect(auctionEndTime > 0).toEqual(true);

    val repeatedInit = item.sendAny(
        collectionSender,
        initBody,
        { value: ton("1"), bounce: true },
    );
    expect(repeatedInit).toHaveSuccessfulTx<Op0WithQuery>({
        from: item.address,
        to: owner,
    });
}

get fun `test item: bids require +5 percent and emit outbid notifications`() {
    val (item, _, owner, bidder) = deployItemThroughCollection();

    val lowBid = item.sendAny(bidder, createEmptyCell(), { value: ton("1000"), bounce: true });
    expect(lowBid).toHaveFailedTx({
        from: bidder,
        to: item.address,
        exitCode: ERROR_BID_TOO_LOW,
    });

    val firstBid = item.sendAny(bidder, createEmptyCell(), { value: ton("2000"), bounce: true });
    expect(firstBid).toHaveSuccessfulTx<OutbidNotification>({
        from: item.address,
        to: owner,
    });

    val (maxBidder, maxBidAmount, _) = item.get_auction_info();
    expect(maxBidder).toEqual(bidder);
    expect(maxBidAmount).toEqual(ton("2000"));
}
