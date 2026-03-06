import "auction"
import "dns-utils"
import "errors"
import "messages"
import "storage"

type AllowedItemMessage =
    | TransferOwnership
    | EditContent
    | ChangeDnsRecord
    | ProcessGovernanceDecision
    | DnsRecordRelease
    | GetStaticData

type GovernanceDecision = GovernanceTransfer | GovernanceRelease

fun onInternalMessage(in: InMessage) {
    val loadingStorage = startLoadingDnsItemStorage();

    if (!loadingStorage.isInitialized()) {
        val uninitStorage = loadingStorage.parseNotInitialized();
        assert (
            in.senderAddress == uninitStorage.collectionAddress
        ) throw ERROR_NOT_FROM_COLLECTION;

        val initData = lazy ItemInitData.fromSlice(in.body);

        val now = blockchain.now();

        val seconds = now - AUCTION_START_TIME;
        var months = seconds / ONE_MONTH;
        if (months > 12) {
            months = 12;
        }

        val duration = AUCTION_START_DURATION -
        // acton-disable-next-line divide-before-multiply
        (AUCTION_START_DURATION - AUCTION_END_DURATION) * months / 12;

        val auctionEndTime = now + duration;
        val initialContent: DnsRecords = [];

        val initStorage = ItemStorageInitialized {
            index: uninitStorage.index,
            collectionAddress: uninitStorage.collectionAddress,
            ownerAddress: null,
            content: initialContent.toCell(),
            domain: initData.domain,
            auction: AuctionState {
                maxBidAddress: initData.fromAddress,
                maxBidAmount: in.valueCoins,
                auctionEndTime,
            }.toCell(),
            lastFillUpTime: now,
        };

        initStorage.save();
        return;
    }

    var storage = loadingStorage.parseInitialized();

    if (in.senderAddress == storage.collectionAddress) {
        val initData = lazy ItemInitData.fromSlice(in.body);

        val returnMessage = createMessage({
            dest: initData.fromAddress,
            body: Op0WithQuery { queryId: blockchain.logicalTime() },
            bounce: false,
            value: 0,
        });
        returnMessage.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);

        return;
    }

    val unpackedAuction = storage.unpackAuction();
    val isAuctionNull = unpackedAuction.0;
    var auction = unpackedAuction.1;
    val isAuctionComplete = blockchain.now() > auction.auctionEndTime;

    if (in.body.isEmpty() || in.body.preloadUint(32) == 0) {
        processBidOrTopUp(
            in.senderAddress,
            in.valueCoins,
            mutate storage,
            mutate auction,
            isAuctionComplete
        );
        return;
    }

    var myBalance = contract.getOriginalBalance();

    if (isAuctionComplete && !isAuctionNull) {
        val parsedHeader = lazy MessageHeader.fromSlice(in.body);

        val balanceBeforeMsg = myBalance - in.valueCoins;

        var amountToSend = balanceBeforeMsg;
        val available = balanceBeforeMsg - MIN_TONS_FOR_STORAGE;

        if (amountToSend > available) {
            amountToSend = available;
        }

        if (amountToSend > 0) {
            val refundMsg = createMessage({
                body: FillUp { queryId: parsedHeader.queryId },
                bounce: false,
                dest: storage.collectionAddress,
                value: amountToSend,
            });
            refundMsg.send(SEND_MODE_IGNORE_ERRORS);

            // since messages are processed at action phase, we need to manage
            // balance in compute phase runtime ourselves
            myBalance -= amountToSend;
        }

        storage.ownerAddress = auction.maxBidAddress;
        storage.auction = null;
        storage.save();
    }

    var msg = lazy AllowedItemMessage.fromSlice(in.body);

    match (msg) {
        TransferOwnership => {
            assert (in.senderAddress == storage.ownerAddress!) throw ERROR_NOT_OWNER;

            applyOwnershipTransfer(
                myBalance,
                mutate storage,
                msg.queryId,
                msg.transferData,
                in.originalForwardFee
            );
        }

        EditContent => {
            assert (
                in.senderAddress == storage.ownerAddress!
            ) throw ERROR_ONLY_OWNER_CAN_EDIT_CONTENT;

            storage.content = msg.newContent;
            storage.lastFillUpTime = blockchain.now();
            storage.save();
        }

        ChangeDnsRecord => {
            assert (
                in.senderAddress == storage.ownerAddress!
            ) throw ERROR_ONLY_OWNER_CAN_CHANGE_DNS;

            var dnsRecords = storage.content.load();

            // TODO: use unpack here
            if (msg.value.remainingRefsCount() > 0) {
                dnsRecords.set(msg.key, msg.value.loadRef());
            } else {
                dnsRecords.delete(msg.key);
            }

            storage.content = dnsRecords.toCell();
            storage.lastFillUpTime = blockchain.now();
            storage.save();
        }

        ProcessGovernanceDecision => {
            // TODO: bench gas usage for isNull auction
            assert (isAuctionNull) throw ERROR_GOVERNANCE_REQUIRES_NO_AUCTION;

            val configCell = blockchain.configParam(DNS_CONFIG_ID);
            assert (configCell != null) throw ERROR_CONFIG_ENTRY_NOT_FOUND;

            val configDict = loadDnsConfigMap(configCell);

            val configValueLookup = configDict.get(storage.index);
            assert (configValueLookup.isFound) throw ERROR_CONFIG_ENTRY_NOT_FOUND;

            val configValue = configValueLookup.loadValue();
            // no need for lazy here
            val decision = GovernanceDecision.fromSlice(
                configValue,
                { throwIfOpcodeDoesNotMatch: ERROR_CONFIG_OPERATION_INVALID }
            );

            match (decision) {
                GovernanceTransfer => {
                    applyOwnershipTransfer(
                        myBalance,
                        mutate storage,
                        msg.queryId,
                        decision.transferData,
                        in.originalForwardFee
                    );
                }

                GovernanceRelease => {
                    val fillMsg = createMessage({
                        body: FillUp { queryId: msg.queryId },
                        bounce: false,
                        dest: storage.collectionAddress,
                        value: 0,
                    });
                    // SAFETY: Governance-only branch
                    fillMsg.send(SEND_MODE_CARRY_ALL_BALANCE + SEND_MODE_DESTROY);
                }
            }
        }

        DnsRecordRelease => {
            val now = blockchain.now();

            assert (
                now - storage.lastFillUpTime > ONE_YEAR && isAuctionNull
            ) throw ERROR_DNS_BALANCE_RELEASE_FORBIDDEN;

            val minPrice = getMinPrice(storage.domain.beginParse().remainingBitsCount(), now);
            assert (in.valueCoins >= minPrice) throw ERROR_BID_TOO_LOW;

            val balanceWithoutMsg = myBalance - in.valueCoins;
            val amountToSend = balanceWithoutMsg - MIN_TONS_FOR_STORAGE;

            if (amountToSend > 0) {
                val responseMsg = createMessage({
                    body: DnsRecordRelease { queryId: msg.queryId },
                    bounce: false,
                    dest: storage.ownerAddress!,
                    value: amountToSend,
                });
                responseMsg.send(SEND_MODE_IGNORE_ERRORS);
            }

            storage.ownerAddress = null;
            storage.auction = AuctionState {
                maxBidAddress: in.senderAddress,
                auctionEndTime: now + AUCTION_START_DURATION,
                maxBidAmount: in.valueCoins,
            }.toCell();
            storage.lastFillUpTime = now;

            storage.save();
        }

        GetStaticData => {
            val responseMsg = createMessage({
                body: ReportStaticData {
                    queryId: msg.queryId,
                    itemIndex: storage.index,
                    collectionAddress: storage.collectionAddress,
                },
                bounce: false,
                dest: in.senderAddress,
                value: 0,
            });
            responseMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }

        else => throw ERROR_UNKNOWN_OP,
    }
}

struct NftDataReply {
    isInitialized: bool
    index: uint256
    collectionAddress: address
    ownerAddress: address?
    content: Cell<DnsRecords>?
}

get fun get_nft_data(): NftDataReply {
    val loading = startLoadingDnsItemStorage();

    if (!loading.isInitialized()) {
        val st = loading.parseNotInitialized();

        return {
            isInitialized: false,
            index: st.index,
            collectionAddress: st.collectionAddress,
            ownerAddress: null,
            content: null,
        };
    }

    val st = loading.parseInitialized();
    return {
        isInitialized: true,
        index: st.index,
        collectionAddress: st.collectionAddress,
        ownerAddress: st.ownerAddress,
        content: st.content,
    };
}

get fun get_editor(): address? {
    val loading = startLoadingDnsItemStorage();

    if (!loading.isInitialized()) {
        return null;
    }

    val st = loading.parseInitialized();
    return st.ownerAddress;
}

get fun get_domain(): slice {
    // this will panic if storage is not init, but so does FunC impl
    val st = startLoadingDnsItemStorage().parseInitialized();
    return st.domain.beginParse();
}

get fun get_auction_info(): AuctionState {
    val st = startLoadingDnsItemStorage().parseInitialized();

    return st.unpackAuction().1;
}

get fun get_last_fill_up_time(): int {
    val st = startLoadingDnsItemStorage().parseInitialized();
    return st.lastFillUpTime;
}

get fun dnsresolve(subdomain: slice, category: uint256): DnsResolveResponse {
    val subdomainBits = subdomain.remainingBitsCount();
    assert (subdomainBits % BYTE_SIZE == 0) throw ERROR_DNS_INVALID_SUBDOMAIN_BITS;

    val st = startLoadingDnsItemStorage().parseInitialized();

    val dnsRecord = st.content.load();

    val startsWithZeroByte = subdomain.preloadInt(BYTE_SIZE) == 0;
    // TODO: why we reuse this error here?
    assert (startsWithZeroByte) throw ERROR_GOVERNANCE_REQUIRES_NO_AUCTION;

    if (subdomainBits > BYTE_SIZE) {
        category = "dns_next_resolver".toBase256();
    }

    if (category == 0) {
        return { resolvedPrefixLengthBits: BYTE_SIZE, resolvedRecord: dnsRecord.toLowLevelDict() };
    }

    val value = dnsRecord.get(category);
    if (!value.isFound) {
        return { resolvedPrefixLengthBits: BYTE_SIZE, resolvedRecord: null };
    }

    return { resolvedPrefixLengthBits: BYTE_SIZE, resolvedRecord: value.loadValue() };
}
