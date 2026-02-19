import "dns-utils"
import "errors"
import "messages"
import "storage"

fun processBidOrTopUp(
    senderAddress: address,
    valueCoins: coins,
    mutate st: ItemStorageInitialized,
    mutate auction: AuctionState,
    auctionComplete: bool,
) {
    if (auctionComplete) {
        assert (senderAddress == st.ownerAddress!) throw ERROR_ONLY_OWNER_CAN_FILL_UP_AFTER_AUCTION;

        st.lastFillUpTime = blockchain.now();
        st.save();
    } else {
        // 5% greater than previous bid
        assert (valueCoins >= mulDivFloor(auction.maxBidAmount, 105, 100)) throw ERROR_BID_TOO_LOW;

        val myBalance = contract.getOriginalBalance();

        var amountToSend = auction.maxBidAmount;
        val available = myBalance - MIN_TONS_FOR_STORAGE;

        if (amountToSend > available) {
            amountToSend = available;
        }

        if (amountToSend > 0) {
            val outbidMsg = createMessage({
                body: OutbidNotification { queryId: blockchain.logicalTime() },
                bounce: false,
                dest: auction.maxBidAddress!, // safe null cast since previous bid exists
                value: amountToSend,
            });
            outbidMsg.send(SEND_MODE_PAY_FEES_SEPARATELY);
        }

        auction.maxBidAmount = valueCoins;
        auction.maxBidAddress = senderAddress;

        val deltaTime = AUCTION_PROLONGATION - (auction.auctionEndTime - blockchain.now());
        if (deltaTime > 0) {
            auction.auctionEndTime += deltaTime;
        }

        st.auction = auction.toCell();
        st.lastFillUpTime = blockchain.now();
        st.save();
    }
}

fun address.forceBasechain(self) {
    assert (self.getWorkchain() == BASECHAIN) throw ERROR_WRONG_WORKCHAIN;
}

fun applyOwnershipTransfer(
    myBalance: coins,
    mutate storage: ItemStorageInitialized,
    queryId: uint64,
    transferData: TransferOwnershipData,
    fwdFees: coins,
) {
    // TODO: load storage in-place
    val newOwnerAddress = transferData.newOwnerAddress;
    newOwnerAddress.forceBasechain();

    val responseDestination = transferData.responseDestination;
    val forwardAmount = transferData.forwardAmount;

    var restAmount = myBalance - MIN_TONS_FOR_STORAGE;
    if (forwardAmount > 0) {
        restAmount -= (forwardAmount + fwdFees);
    }

    val needResponse = responseDestination != null;
    if (needResponse) {
        restAmount -= fwdFees;
    }

    // all Tolk numeric types are int at runtime
    // so even when type is coins, this assert is not useless
    assert (restAmount >= 0) throw ERROR_NOT_ENOUGH_BALANCE;

    if (forwardAmount > 0) {
        val responseMsg = createMessage({
            body: OwnershipAssigned {
                queryId,
                oldOwnerAddress: storage.ownerAddress,
                payload: transferData.forwardPayload,
            },
            bounce: false,
            dest: newOwnerAddress,
            value: forwardAmount,
        });
        responseMsg.send(SEND_MODE_PAY_FEES_SEPARATELY);
    }

    if (needResponse) {
        // TODO: smartcast?
        responseDestination!.forceBasechain();

        val excessesMsg = createMessage({
            body: Excesses { queryId },
            bounce: false,
            dest: responseDestination!,
            value: restAmount,
        });
        excessesMsg.send(SEND_MODE_PAY_FEES_SEPARATELY);
    }

    storage.ownerAddress = newOwnerAddress;
    storage.lastFillUpTime = blockchain.now();
    storage.save();
}
