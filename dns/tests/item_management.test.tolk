import "test_utils"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "../contracts/messages"
import "../contracts/constants"

fun setupCompletedItem() {
    val (item, collection, owner, _) = deployItemThroughCollection();

    val completeRes = completeAuction(item, owner, 1);
    expect(completeRes).toHaveSuccessfulTx<FillUp>({ from: item.address, to: collection.address });

    return (item, collection, owner);
}

get fun `test item: transfer ownership after auction completion`() {
    val (item, _, owner) = setupCompletedItem();
    val newOwner = newActor("item_transfer_new_owner");

    val transfer = item.sendAny(
        owner,
        makeTransferBody(123, newOwner, null, ton("0.5")),
        { value: ton("1"), bounce: true },
    );

    expect(transfer).toHaveSuccessfulTx<OwnershipAssigned>({
        from: item.address,
        to: newOwner,
    });

    expect(item.get_editor()).toEqual(newOwner);
}

get fun `test item: reports static data after auction completion`() {
    val (item, _, owner) = setupCompletedItem();
    val requester = newActor("item_static_requester");

    val staticData = item.sendAny(
        requester,
        makeGetStaticDataBody(77),
        { value: ton("1"), bounce: true },
    );
    expect(staticData).toHaveSuccessfulTx<ReportStaticData>({
        from: item.address,
        to: requester,
    });

    val (maxBidder, maxBidAmount, _) = item.get_auction_info();
    expect(maxBidder).toEqual(null);
    expect(maxBidAmount).toEqual(0);
}
