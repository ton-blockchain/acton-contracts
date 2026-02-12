import "constants"
import "errors"
import "storage"
import "messages"

fun sendMessage(
    toAddress: address,
    amount: coins,
    body: cell,
    sendMode: int,
) {
    val msg = createMessage({
        bounce: BounceMode.NoBounce,
        dest: toAddress,
        value: amount,
        body,
    });
    msg.send(sendMode);
}

fun storeItemData(
    index: uint256,
    collectionAddress: address,
    ownerAddress: address?,
    content: Cell<DnsContent>,
    domain: Cell<DomainName>,
    auction: dict,
    lastFillUpTime: int,
) {
    ItemStorageInitialized {
        index,
        collectionAddress,
        ownerAddress,
        content,
        domain,
        auction,
        lastFillUpTime: lastFillUpTime as uint64,
    }.save();
}

fun applyOwnershipTransfer(
    myBalance: coins,
    index: uint256,
    collectionAddress: address,
    ownerAddress: address?,
    content: Cell<DnsContent>,
    queryId: uint64,
    transferData: TransferOwnershipData,
    fwdFees: coins,
    domain: Cell<DomainName>,
    auction: dict,
) {
    val newOwnerAddress = transferData.newOwnerAddress;
    forceBasechain(newOwnerAddress);

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

    assert (restAmount >= 0) throw ERROR_NOT_ENOUGH_BALANCE;

    if (forwardAmount > 0) {
        sendMessage(
            newOwnerAddress,
            forwardAmount,
            OwnershipAssigned {
                queryId,
                oldOwnerAddress: ownerAddress,
                payload: transferData.forwardPayload,
            }.toCell(),
            SEND_MODE_PAY_FEES_SEPARATELY,
        );
    }

    if (needResponse) {
        forceBasechain(responseDestination!!);
        sendMessage(
            responseDestination!!,
            restAmount,
            Excesses { queryId }.toCell(),
            SEND_MODE_PAY_FEES_SEPARATELY,
        );
    }

    storeItemData(
        index,
        collectionAddress,
        newOwnerAddress,
        content,
        domain,
        auction,
        blockchain.now(),
    );
}

fun settleCompletedAuctionIfNeeded(
    mutate myBalance: coins,
    inValueCoins: coins,
    queryId: uint64,
    mutate st: ItemStorageInitialized,
): coins {
    if (st.auction == null) {
        return myBalance;
    }

    val auction = unpackAuction(st.auction);
    if (blockchain.now() <= auction.auctionEndTime) {
        return myBalance;
    }

    val balanceWithoutMsg = myBalance - inValueCoins;

    var amountToSend = auction.maxBidAmount;
    val available = balanceWithoutMsg - MIN_TONS_FOR_STORAGE;
    if (amountToSend > available) {
        amountToSend = available;
    }

    if (amountToSend > 0) {
        sendMessage(
            st.collectionAddress,
            amountToSend,
            FillUp { queryId }.toCell(),
            SEND_MODE_IGNORE_ERRORS,
        );
        myBalance -= amountToSend;
    }

    st.ownerAddress = auction.maxBidAddress;
    st.auction = null;
    st.save();

    return myBalance;
}

fun processBidOrTopUp(
    senderAddress: address,
    valueCoins: coins,
    myBalance: coins,
    st: ItemStorageInitialized,
    mutate auction: AuctionState,
    auctionComplete: bool,
) {
    if (auctionComplete) {
        assert (st.ownerAddress != null && senderAddress == st.ownerAddress!!) throw ERROR_ONLY_OWNER_CAN_FILL_UP_AFTER_AUCTION;
        storeItemData(
            st.index,
            st.collectionAddress,
            st.ownerAddress,
            st.content,
            st.domain,
            st.auction,
            blockchain.now(),
        );
        return;
    }

    assert (valueCoins >= mulDivFloor(auction.maxBidAmount, 105, 100)) throw ERROR_BID_TOO_LOW;

    var amountToSend = auction.maxBidAmount;
    val available = myBalance - MIN_TONS_FOR_STORAGE;
    if (amountToSend > available) {
        amountToSend = available;
    }

    if (amountToSend > 0) {
        assert (auction.maxBidAddress != null) throw ERROR_UNKNOWN_OP;
        sendMessage(
            auction.maxBidAddress!!,
            amountToSend,
            OutbidNotification { queryId: 999 as uint64 }.toCell(),
            SEND_MODE_PAY_FEES_SEPARATELY,
        );
    }

    auction.maxBidAmount = valueCoins;
    auction.maxBidAddress = senderAddress;

    val deltaTime = AUCTION_PROLONGATION - (auction.auctionEndTime - blockchain.now());
    if (deltaTime > 0) {
        auction.auctionEndTime += deltaTime;
    }

    storeItemData(
        st.index,
        st.collectionAddress,
        st.ownerAddress,
        st.content,
        st.domain,
        packAuction(auction.maxBidAddress, auction.maxBidAmount, auction.auctionEndTime),
        blockchain.now(),
    );
}

fun onInternalMessage(in: InMessage) {
    var myBalance = contract.getOriginalBalance();

    val loading = startLoadingItemStorage();
    if (!loading.isInitialized()) {
        if (in.body.isEmpty()) {
            // Compatibility for Acton wrapper deploy messages.
            return;
        }

        val st = loading.parseNotInitialized();
        assert (in.senderAddress == st.collectionAddress) throw ERROR_NOT_FROM_COLLECTION;

        val initData = ItemInitData.fromSlice(in.body);

        val initialContent: DnsContent = createEmptyMap();

        val seconds = blockchain.now() - AUCTION_START_TIME;
        var months = seconds / ONE_MONTH;
        if (months > 12) {
            months = 12;
        }

        val duration =
            AUCTION_START_DURATION
            - (AUCTION_START_DURATION - AUCTION_END_DURATION) * months / 12;

        val auctionEndTime = blockchain.now() + duration;

        storeItemData(
            st.index,
            st.collectionAddress,
            zeroAddress(),
            initialContent.toCell(),
            initData.domain,
            packAuction(initData.fromAddress, in.valueCoins, auctionEndTime),
            blockchain.now(),
        );

        return;
    }

    var st = loading.parseInitialized();

    if (in.senderAddress == st.collectionAddress) {
        val initData = ItemInitData.fromSlice(in.body);
        sendMessage(
            initData.fromAddress,
            0,
            Op0WithQuery { queryId: blockchain.logicalTime() as uint64 }.toCell(),
            SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE,
        );
        return;
    }

    var auction = unpackAuction(st.auction);
    val auctionComplete = blockchain.now() > auction.auctionEndTime;

    if (in.body.isEmpty()) {
        processBidOrTopUp(in.senderAddress, in.valueCoins, myBalance, st, mutate auction, auctionComplete);
        return;
    }

    val msg = lazy AllowedItemMessage.fromSlice(in.body);

    match (msg) {
        ItemBidOrTopUp => {
            processBidOrTopUp(in.senderAddress, in.valueCoins, myBalance, st, mutate auction, auctionComplete);
        }

        TransferOwnership => {
            myBalance = settleCompletedAuctionIfNeeded(mutate myBalance, in.valueCoins, msg.queryId, mutate st);
            assert (st.ownerAddress != null && in.senderAddress == st.ownerAddress!!) throw ERROR_NOT_OWNER;
            applyOwnershipTransfer(
                myBalance,
                st.index,
                st.collectionAddress,
                st.ownerAddress,
                st.content,
                msg.queryId,
                msg.transferData,
                in.originalForwardFee,
                st.domain,
                st.auction,
            );
        }

        EditContent => {
            myBalance = settleCompletedAuctionIfNeeded(mutate myBalance, in.valueCoins, msg.queryId, mutate st);
            assert (st.ownerAddress != null && in.senderAddress == st.ownerAddress!!) throw ERROR_ONLY_OWNER_CAN_EDIT_CONTENT;
            st.content = msg.newContent;
            st.lastFillUpTime = blockchain.now();
            st.save();
        }

        ChangeDnsRecord => {
            myBalance = settleCompletedAuctionIfNeeded(mutate myBalance, in.valueCoins, msg.queryId, mutate st);
            assert (st.ownerAddress != null && in.senderAddress == st.ownerAddress!!) throw ERROR_ONLY_OWNER_CAN_CHANGE_DNS;

            var keyvalueMap = st.content.load();

            if (msg.value != null) {
                keyvalueMap.set(msg.key, msg.value!!);
            } else {
                keyvalueMap.delete(msg.key);
            }

            st.content = keyvalueMap.toCell();
            st.lastFillUpTime = blockchain.now();
            st.save();
        }

        ProcessGovernanceDecision => {
            myBalance = settleCompletedAuctionIfNeeded(mutate myBalance, in.valueCoins, msg.queryId, mutate st);
            assert (st.auction == null) throw ERROR_GOVERNANCE_REQUIRES_NO_AUCTION;

            val configCell = blockchain.configParam(DNS_CONFIG_ID);
            assert (configCell != null) throw ERROR_CONFIG_ENTRY_NOT_FOUND;

            val configDict = loadDnsConfigMap(configCell!!);

            val configValueLookup = configDict.get(st.index);
            assert (configValueLookup.isFound) throw ERROR_CONFIG_ENTRY_NOT_FOUND;

            val configValue = configValueLookup.loadValue();
            val decision = lazy GovernanceDecision.fromSlice(configValue, {
                throwIfOpcodeDoesNotMatch: ERROR_CONFIG_OPERATION_INVALID
            });

            match (decision) {
                GovernanceTransfer => {
                    applyOwnershipTransfer(
                        myBalance,
                        st.index,
                        st.collectionAddress,
                        st.ownerAddress,
                        st.content,
                        msg.queryId,
                        decision.transferData,
                        in.originalForwardFee,
                        st.domain,
                        st.auction,
                    );
                }

                GovernanceRelease => {
                    sendMessage(
                        st.collectionAddress,
                        0,
                        FillUp { queryId: msg.queryId }.toCell(),
                        SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_DESTROY,
                    );
                }

                else => throw ERROR_CONFIG_OPERATION_INVALID
            }
        }

        DnsBalanceRelease => {
            myBalance = settleCompletedAuctionIfNeeded(mutate myBalance, in.valueCoins, msg.queryId, mutate st);
            assert (
                blockchain.now() - st.lastFillUpTime > ONE_YEAR
                && st.auction == null
            ) throw ERROR_DNS_BALANCE_RELEASE_FORBIDDEN;

            val minPrice = getMinPrice(st.domain.load().remainingBitsCount(), blockchain.now());
            assert (in.valueCoins >= minPrice) throw ERROR_BID_TOO_LOW;

            val balanceWithoutMsg = myBalance - in.valueCoins;
            val amountToSend = balanceWithoutMsg - MIN_TONS_FOR_STORAGE;

            if (amountToSend > 0) {
                assert (st.ownerAddress != null) throw ERROR_DNS_BALANCE_RELEASE_FORBIDDEN;
                sendMessage(
                    st.ownerAddress!!,
                    amountToSend,
                    DnsBalanceRelease { queryId: msg.queryId }.toCell(),
                    SEND_MODE_IGNORE_ERRORS,
                );
            }

            st.ownerAddress = zeroAddress();
            st.auction = packAuction(
                in.senderAddress,
                in.valueCoins,
                blockchain.now() + AUCTION_START_DURATION,
            );
            st.lastFillUpTime = blockchain.now();
            st.save();
        }

        GetStaticData => {
            myBalance = settleCompletedAuctionIfNeeded(mutate myBalance, in.valueCoins, msg.queryId, mutate st);
            sendMessage(
                in.senderAddress,
                0,
                ReportStaticData {
                    queryId: msg.queryId,
                    itemIndex: st.index,
                    collectionAddress: st.collectionAddress,
                }.toCell(),
                SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE,
            );
        }

        else => throw ERROR_UNKNOWN_OP
    }
}

fun onBouncedMessage(in: InMessageBounced) {
    // Ignore bounced messages.
}

struct NftDataReply {
    initialized: int
    index: uint256
    collectionAddress: address
    ownerAddress: address?
    content: Cell<DnsContent>?
}

get fun get_nft_data(): NftDataReply {
    val loading = startLoadingItemStorage();
    if (!loading.isInitialized()) {
        val st = loading.parseNotInitialized();
        return {
            initialized: 0,
            index: st.index,
            collectionAddress: st.collectionAddress,
            ownerAddress: zeroAddress(),
            content: null,
        };
    }

    val st = loading.parseInitialized();
    return {
        initialized: -1,
        index: st.index,
        collectionAddress: st.collectionAddress,
        ownerAddress: st.ownerAddress,
        content: st.content,
    };
}

get fun get_editor(): address? {
    val loading = startLoadingItemStorage();
    if (!loading.isInitialized()) {
        return zeroAddress();
    }

    val st = loading.parseInitialized();
    return st.ownerAddress;
}

get fun get_domain(): slice {
    val st = startLoadingItemStorage().parseInitialized();
    return st.domain.load();
}

get fun get_auction_info(): (address?, coins, int) {
    val st = startLoadingItemStorage().parseInitialized();
    val auction = unpackAuction(st.auction);
    return (auction.maxBidAddress, auction.maxBidAmount, auction.auctionEndTime);
}

get fun get_last_fill_up_time(): int {
    val st = startLoadingItemStorage().parseInitialized();
    return st.lastFillUpTime;
}

get fun dnsresolve(subdomain: slice, category: int): (int, cell?) {
    val subdomainBits = subdomain.remainingBitsCount();
    assert (subdomainBits % 8 == 0) throw ERROR_DNS_INVALID_SUBDOMAIN_BITS;

    val st = startLoadingItemStorage().parseInitialized();

    val keyvalueMap = st.content.load();

    val startsWithZeroByte = subdomain.preloadInt(8) == 0;
    assert (startsWithZeroByte) throw ERROR_GOVERNANCE_REQUIRES_NO_AUCTION;

    if (subdomainBits > 8) {
        category = "dns_next_resolver".toBase256();
    }

    if (category == 0) {
        return (8, keyvalueMap.toLowLevelDict());
    }

    val value = keyvalueMap.get(category as uint256);
    if (!value.isFound) {
        return (8, null);
    }

    return (8, value.loadValue());
}
