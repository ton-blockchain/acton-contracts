import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "@acton/tlb/maybe"
import "@acton/types/transaction"
import "test_utils"
import "wrappers/DnsCollection"
import "wrappers/DnsItem"
import "../contracts/dns-utils"
import "../contracts/messages"

const E2E_DOMAIN = "benchflow"
const E2E_INITIAL_BID = ton("1000")
const E2E_NEXT_BID = ton("1050")
const E2E_GOVERNANCE_QUERY_ID = 7001

fun deployDnsDomainStage(domain: string = E2E_DOMAIN, value: coins = E2E_INITIAL_BID) {
    val (collection, deployer, bidder) = deployCollectionContract();
    val governanceCaller = newActor("dns_e2e_governance_caller", ton("100000"));
    net.setNow((AUCTION_START_TIME + 1));

    val deploy = collection.sendDeployDnsDomain(
        deployer.address,
        makeDomainCell(domain).beginParse(),
        { value, bounce: true },
    );
    expect(deploy).toHaveSuccessfulTx<DeployDnsDomain>({
        from: deployer.address,
        to: collection.address,
    });

    val itemDeployTx = deploy.findTransaction({ from: collection.address, deploy: true });
    expect(itemDeployTx).toBeDefined();

    val item = NftItemContract.fromAddress(itemDeployTx.unwrap().getAccountAddress());
    return (item, collection, deployer, bidder, governanceCaller);
}

fun processNewBidStage(
    item: NftItemContract,
    previousWinnerAddress: address,
    bidderAddress: address,
    bidValue: coins = E2E_NEXT_BID,
) {
    val bid = item.sendAny(bidderAddress, createEmptyCell(), { value: bidValue, bounce: true });
    expect(bid).toHaveSuccessfulTx<OutbidNotification>({
        from: item.address,
        to: previousWinnerAddress,
    });

    val auction = item.getAuctionInfo();
    expect(auction.maxBidAddress).toEqual(bidderAddress);
    expect(auction.maxBidAmount).toEqual(bidValue);
}

fun applyOwnershipStage(item: NftItemContract, collectionAddress: address, expectedOwner: address) {
    val apply = completeAuction(item, expectedOwner, 5001);
    expect(apply).toHaveSuccessfulTx<FillUp>({ from: item.address, to: collectionAddress });

    expect(item.getEditor()).toEqual(expectedOwner);

    val nftData = item.getNftData();
    expect(nftData.ownerAddress).toEqual(expectedOwner);
}

fun processGovernanceDecisionStage(
    item: NftItemContract,
    callerAddress: address,
    newOwner: address,
) {
    val transferData = makeTransferData(newOwner, null, 0, createEmptyCell().beginParse());

    val nftDataBefore = item.getNftData();
    setGovernanceDecision(
        nftDataBefore.index,
        GovernanceTransfer { transferData }.toCell().beginParse(),
    );

    val governance = item.sendProcessGovernanceDecision(
        callerAddress,
        E2E_GOVERNANCE_QUERY_ID,
        { value: ton("1"), bounce: true },
    );
    expect(governance).toHaveSuccessfulTx<ProcessGovernanceDecision>({
        from: callerAddress,
        to: item.address,
    });

    expect(item.getEditor()).toEqual(newOwner);

    val nftDataAfter = item.getNftData();
    expect(nftDataAfter.ownerAddress).toEqual(newOwner);
}

get fun `test dns e2e bench: stage 1 deploy dns domain`() {
    val (item, _, deployer, _, _) = deployDnsDomainStage();

    val nftData = item.getNftData();
    expect(nftData.isInitialized).toEqual(true);
    expect(nftData.index).toEqual(domainIndex(E2E_DOMAIN));
    expect(nftData.ownerAddress).toBeNull();

    val auction = item.getAuctionInfo();
    expect(auction.maxBidAddress).toEqual(deployer.address);
    expect(auction.maxBidAmount == 0).toEqual(false);
    expect(item.getEditor()).toBeNull();
}

get fun `test dns e2e bench: stage 2 process new bid on dns item`() {
    val (item, _, deployer, bidder, _) = deployDnsDomainStage();
    processNewBidStage(item, deployer.address, bidder.address);
}

get fun `test dns e2e bench: stage 3 apply ownership`() {
    val (item, collection, deployer, bidder, _) = deployDnsDomainStage();
    processNewBidStage(item, deployer.address, bidder.address);
    applyOwnershipStage(item, collection.address, bidder.address);
}

get fun `test dns e2e bench: stage 4 full flow with governance decision`() {
    val (item, collection, deployer, bidder, governanceCaller) = deployDnsDomainStage();
    val governmentOwner = newActor("dns_e2e_government_owner", ton("100000"));

    processNewBidStage(item, deployer.address, bidder.address);
    applyOwnershipStage(item, collection.address, bidder.address);
    processGovernanceDecisionStage(item, governanceCaller.address, governmentOwner.address);
}
