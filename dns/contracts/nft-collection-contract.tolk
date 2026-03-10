import "dns-utils"
import "errors"
import "messages"
import "storage"

type AllowedCollectionMessage = DeployDnsDomain | FillUp

fun onInternalMessage(in: InMessage) {
    var msg = lazy AllowedCollectionMessage.fromSlice(in.body);

    match (msg) {
        DeployDnsDomain => {
            val storage = lazy CollectionStorage.load();

            val nowTime = blockchain.now();
            assert (nowTime > AUCTION_START_TIME) throw ERROR_AUCTION_NOT_STARTED;

            val domain = readDomainFromComment(mutate msg.payload);
            val len = domain.remainingBitsCount();

            assert (len > MIN_DOMAIN_SIZE * BYTE_SIZE) throw ERROR_DOMAIN_TOO_SHORT;
            assert (len <= MAX_DOMAIN_SIZE * BYTE_SIZE) throw ERROR_DOMAIN_TOO_LONG;
            assert (len % BYTE_SIZE == 0) throw ERROR_DOMAIN_FORMAT_INVALID;
            assert (checkDomainString(domain, len)) throw ERROR_DOMAIN_HAS_INVALID_CHARS;

            val minPrice = getMinPrice(len, nowTime);
            assert (in.valueCoins >= minPrice) throw ERROR_BID_BELOW_MIN_PRICE;

            val itemIndex = domain.hash();

            val configCell = blockchain.configParam(DNS_CONFIG_ID);
            if (configCell != null) {
                val configDict = loadDnsConfigMap(configCell);
                val found = configDict.exists(itemIndex);
                assert (!found) throw ERROR_DOMAIN_IS_BLACKLISTED;
            }

            val deployItemMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: calcDeployedNftItem(itemIndex, storage.nftItemCode),
                value: 0,
                body: ItemInitData {
                    fromAddress: in.senderAddress,
                    domain: domain.toCell(),
                },
            });
            deployItemMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }

        FillUp => {
            // Top up balance.
        }

        else => throw ERROR_UNKNOWN_OP,
    }
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
        ownerAddress: null,
    };
}

get fun get_nft_address_by_index(index: int): address {
    val st = CollectionStorage.load();
    return calcDeployedNftItem(index, st.nftItemCode).calculateAddress();
}

get fun get_nft_content(_index: int, individualNftContent: cell): cell {
    return individualNftContent;
}

get fun dnsresolve(subdomain: slice, _category: int): DnsResolveResponse {
    assert (subdomain.remainingBitsCount() % BYTE_SIZE == 0) throw ERROR_DNS_INVALID_SUBDOMAIN_BITS;

    val startsWithZeroByte = subdomain.preloadInt(BYTE_SIZE) == 0;

    // "." is resolved, without dns record
    if (startsWithZeroByte && subdomain.remainingBitsCount() == BYTE_SIZE) {
        return { resolvedPrefixLengthBits: BYTE_SIZE, resolvedRecord: null };
    }

    if (startsWithZeroByte) {
        subdomain.skipBits(BYTE_SIZE);
    }

    val topSubdomainBits = getTopDomainBits(subdomain);
    val topSubdomain = subdomain.loadBits(topSubdomainBits);
    val itemIndex = topSubdomain.hash();

    val nextResolverAddress = get_nft_address_by_index(itemIndex);

    return {
        resolvedPrefixLengthBits: topSubdomainBits + (startsWithZeroByte ? BYTE_SIZE : 0),
        resolvedRecord: nextResolverAddress.toNextResolver(),
    };
}
