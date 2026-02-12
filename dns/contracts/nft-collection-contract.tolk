import "constants"
import "errors"
import "storage"
import "messages"

fun calculateNftItemStateData(itemIndex: uint256): cell {
    return ItemStorageNotInitialized {
        index: itemIndex,
        collectionAddress: contract.getAddress(),
    }.toCell();
}

fun calculateNftItemAddress(itemIndex: uint256, nftItemCode: cell): address {
    val deployed: AutoDeployAddress = {
        stateInit: {
            code: nftItemCode,
            data: calculateNftItemStateData(itemIndex),
        },
    };
    return deployed.calculateAddress();
}

fun deployNftItem(itemIndex: uint256, nftItemCode: cell, nftContent: Cell<ItemInitData>) {
    val deployed: AutoDeployAddress = {
        stateInit: {
            code: nftItemCode,
            data: calculateNftItemStateData(itemIndex),
        },
    };

    val msg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        dest: deployed,
        value: 0,
        body: nftContent,
    });
    msg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

fun onInternalMessage(in: InMessage) {
    if (in.body.isEmpty()) {
        // Compatibility for Acton wrapper deploy messages.
        return;
    }

    val msg = lazy AllowedCollectionMessage.fromSlice(in.body);
    val st = CollectionStorage.load();

    match (msg) {
        DeployDnsDomain => {
            val nowTime = blockchain.now();
            assert (nowTime > AUCTION_START_TIME) throw ERROR_AUCTION_NOT_STARTED;

            var payload = msg.payload;
            var domain = readDomainFromComment(mutate payload);
            val len = domain.remainingBitsCount();

            assert (len > 3 * 8) throw ERROR_DOMAIN_TOO_SHORT;
            assert (len <= 126 * 8) throw ERROR_DOMAIN_TOO_LONG;
            assert (len % 8 == 0) throw ERROR_DOMAIN_FORMAT_INVALID;
            assert (checkDomainString(mutate domain)) throw ERROR_DOMAIN_HAS_INVALID_CHARS;

            val minPrice = getMinPrice(len, nowTime);
            assert (in.valueCoins >= minPrice) throw ERROR_BID_BELOW_MIN_PRICE;

            val itemIndex = domain.hash();

            val configCell = blockchain.configParam(DNS_CONFIG_ID);
            if (configCell != null) {
                val configDict = loadDnsConfigMap(configCell!!);
                val found = configDict.exists(itemIndex);
                assert (!found) throw ERROR_DOMAIN_IS_BLACKLISTED;
            }

            val domainName: DomainName = domain;
            val nftContent = ItemInitData {
                fromAddress: in.senderAddress,
                domain: domainName.toCell(),
            }.toCell();

            deployNftItem(itemIndex, st.nftItemCode, nftContent);
        }

        FillUp => {
            // Top up balance.
        }

        else => throw ERROR_UNKNOWN_OP
    }
}

fun onBouncedMessage(in: InMessageBounced) {
    // Ignore bounced messages.
}

struct CollectionDataReply {
    nextItemIndex: int
    content: cell
    ownerAddress: address?
}

get fun get_collection_data(): CollectionDataReply {
    val st = CollectionStorage.load();
    return {
        nextItemIndex: -1,
        content: st.content,
        ownerAddress: zeroAddress(),
    };
}

get fun get_nft_address_by_index(index: int): address {
    val st = CollectionStorage.load();
    return calculateNftItemAddress(index, st.nftItemCode);
}

get fun get_nft_content(index: int, individualNftContent: cell): cell {
    return individualNftContent;
}

get fun dnsresolve(subdomain: slice, category: int): (int, cell?) {
    assert (subdomain.remainingBitsCount() % 8 == 0) throw ERROR_DNS_INVALID_SUBDOMAIN_BITS;

    val startsWithZeroByte = subdomain.preloadInt(8) == 0;

    if (startsWithZeroByte && subdomain.remainingBitsCount() == 8) {
        return (8, null);
    }
    if (startsWithZeroByte) {
        subdomain.loadUint(8);
    }

    val topSubdomainBits = getTopDomainBits(mutate subdomain);
    val topSubdomain = subdomain.loadBits(topSubdomainBits);
    val itemIndex = topSubdomain.hash();

    val result = DnsNextResolver {
        resolver: get_nft_address_by_index(itemIndex as int),
    }.toCell();

    return (topSubdomainBits + (startsWithZeroByte ? 8 : 0), result);
}
