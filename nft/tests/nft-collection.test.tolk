import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"

import "wrappers/NftCollectionContract"
import "wrappers/NftItemContract"
import "../contracts/messages"
import "../contracts/types"
import "@acton/build/build"
import "@acton/tolk-stdlib/tvm-dicts"

struct Royalty {
    numerator: int,
    denominator: int,
    royaltyAddress: address
}


get fun `test nft: report royalty params`() {
    val (nftCollection, _, royaltyParams) = setupTest();
    val randomTreasury = net.treasury("random treasury");
    val queryId = 42;
    val result = nftCollection.sendRequestRoyaltyParams(
        randomTreasury.address,
        queryId,
        {
            value: ton("0.05"),
        }
    );

    expect(result).toHaveSuccessfulTx<RequestRoyaltyParams>({
        from: randomTreasury.address,
        to: nftCollection.address,
    });

    expect(result).toHaveTx<ResponseRoyaltyParams>({
        from: nftCollection.address,
        to: randomTreasury.address,
        bounce: false,
        body: ResponseRoyaltyParams {
            queryId,
            royaltyParams
        }.toCell()
    });
}

fun shouldNotAllowAnyOtherOpcodeNotFromOwner(opcode: int) {
    val randomTreasury = net.treasury("random-treasury");

    val (nftCollection, _deployer, _royaltyParams) = setupTest();

    val result = nftCollection.sendAny(
        randomTreasury.address,
        beginCell().storeUint(opcode, 32).storeUint(42, 64).endCell(),
        {
            value: ton("0.05"),
        }
    );

    val exitCode = opcode == 0x042 ? 0xFFFF : 401;

    expect(result).toHaveTx({
        from: randomTreasury.address,
        to: nftCollection.address,
        opcode,
        success: false,
        // exitCode: 401,       // this changed against FunC: on invalid opcode, we always return 0xFFFF
        exitCode,
    });
}

get fun `test nft: should not allow any other opcode not from owner`() {
    shouldNotAllowAnyOtherOpcodeNotFromOwner(1);
    shouldNotAllowAnyOtherOpcodeNotFromOwner(2);
    shouldNotAllowAnyOtherOpcodeNotFromOwner(3);
    shouldNotAllowAnyOtherOpcodeNotFromOwner(0x42);
}

fun nftFixture(nftCollection: NftCollectionContract, nftOwnerAddress: address) {
    val deployer = net.treasury("deployer");
    val nextItemIndex = nftCollection.getCollectionData().nextItemIndex;
    val nftDeployResult = nftCollection.sendDeployNft(
        deployer.address,
        0,
        nextItemIndex,
        ton("0.02"),
        {
            ownerAddress: nftOwnerAddress,
            content: createEmptyCell() as Cell<SnakeString>,
        },
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(nftDeployResult).toHaveSuccessfulTx({
        from: deployer.address,
        to: nftCollection.address,
    });

    val nftAddress = nftCollection.getNftAddressByIndex(nextItemIndex);

    expect(nftDeployResult).toHaveSuccessfulDeploy({
        from: nftCollection.address,
        to: nftAddress,
    });

    return NftItemContract.fromAddress(nftAddress);
}

/// Initializes the test environment, creating a fresh instance of the contract.
/// Returns the contract wrapper and two treasury accounts (`deployer` and `not_deployer`).
fun setupTest() {
    val deployer = net.treasury("deployer");

    val royaltyParams = RoyaltyParams {
        numerator: 16,
        denominator: 2,
        royaltyAddress: net.randomAddress(),
    };

    // Initialize and deploy the contract with default values
    val nftCollection = NftCollectionContract.fromStorage({
        adminAddress: deployer.address,
        nextItemIndex: 0,
        content: CollectionContent {
            collectionMetadata: createEmptyCell(),
            commonContent: createEmptySlice().toCell()
        }.toCell(),
        nftItemCode: build("nft-item"),
        royaltyParams: royaltyParams.toCell(),
    });

    val deployRes = nftCollection.deploy(deployer.address, {
        value: ton("0.05"),
        bounce: false
    });

    expect(deployRes).toHaveSuccessfulDeploy({
        to: nftCollection.address,
    });

    return (nftCollection, deployer, royaltyParams)
}

get fun `test nft: should deploy nft`() {
    val (nftCollection, deployer, _) = setupTest();
    val nextItemIndex = nftCollection.getCollectionData().nextItemIndex;
    val nftOwnerAddress = net.randomAddress();
    val content: Cell<SnakeString> = beginCell().storeString("Content").endCell() as Cell<SnakeString>;

    val nftDeployResult = nftCollection.sendDeployNft(
        deployer.address,
        0,  // queryId
        nextItemIndex,
        ton("0.02"),
        {
            ownerAddress: nftOwnerAddress,
            content,
        },
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(nftDeployResult).toHaveSuccessfulTx<DeployNft>({
        from: deployer.address,
        to: nftCollection.address,
    });

    val nftAddress = nftCollection.getNftAddressByIndex(nextItemIndex);

    expect(nftDeployResult).toHaveSuccessfulDeploy({
        from: nftCollection.address,
        to: nftAddress,
        // TODO initCode: nftItemCode,
    });

    val nftItem = NftItemContract.fromAddress(nftAddress);
    val data = nftItem.getNftData();

    expect(data.isInitialized).toBeTrue();
    expect(data.itemIndex).toEqual(nextItemIndex);
    expect(data.ownerAddress!).toEqual(nftOwnerAddress);
    expect(data.collectionAddress).toEqual(nftCollection.address);
    expect(data.content).toEqual(content);
}

get fun `test nft: should not deploy nft with invalid item index`() {
    val (nftCollection, deployer, _) = setupTest();
    val nextItemIndex = nftCollection.getCollectionData().nextItemIndex;

    // Trying to deploy with invalid index (nextItemIndex + 1 instead of nextItemIndex)
    val nftDeployResult = nftCollection.sendDeployNft(
        deployer.address,
        0,  // queryId
        nextItemIndex + 1,  // invalid index!
        ton("0.02"),
        {
            ownerAddress: deployer.address,
            content: createEmptyCell() as Cell<SnakeString>,
        },
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(nftDeployResult).toHaveFailedTx<DeployNft>({
        from: deployer.address,
        to: nftCollection.address,
        exitCode: 402,
    });
}

get fun `test nft: should increment item index if last`() {
    val (nftCollection, deployer, _) = setupTest();
    val nextItemIndex = nftCollection.getCollectionData().nextItemIndex;

    val nftDeployResult = nftCollection.sendDeployNft(
        deployer.address,
        0,  // queryId
        nextItemIndex,
        ton("0.02"),
        {
            ownerAddress: deployer.address,
            content: createEmptyCell() as Cell<SnakeString>,
        },
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(nftDeployResult).toHaveSuccessfulTx<DeployNft>({
        from: deployer.address,
        to: nftCollection.address,
    });

    val newNextItemIndex = nftCollection.getCollectionData().nextItemIndex;
    expect(newNextItemIndex).toEqual(nextItemIndex + 1);
}

get fun `test nft: should not increment item index if not last`() {
    val (nftCollection, deployer, _) = setupTest();
    val nextItemIndex = nftCollection.getCollectionData().nextItemIndex;

    // Deploy first NFT at index 0
    nftCollection.sendDeployNft(
        deployer.address,
        0,
        nextItemIndex,
        ton("0.02"),
        {
            ownerAddress: deployer.address,
            content: createEmptyCell() as Cell<SnakeString>,
        },
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    val newNextItemIndex = nftCollection.getCollectionData().nextItemIndex;
    expect(newNextItemIndex).toEqual(nextItemIndex + 1);

    // Deploy again at index 0 (re-deploy, not last)
    val nftDeployResult = nftCollection.sendDeployNft(
        deployer.address,
        0,
        0,  // index 0, not the last one
        ton("0.02"),
        {
            ownerAddress: deployer.address,
            content: createEmptyCell() as Cell<SnakeString>,
        },
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(nftDeployResult).toHaveSuccessfulTx<DeployNft>({
        from: deployer.address,
        to: nftCollection.address,
    });

    // Index should NOT have changed
    val newNextItemIndexAfterSecondDeploy = nftCollection.getCollectionData().nextItemIndex;
    expect(newNextItemIndexAfterSecondDeploy).toEqual(newNextItemIndex);
}

get fun `test nft: should deploy some nfts via batch deploy`() {
    val (nftCollection, deployer, _) = setupTest();
    val nextItemIndex = nftCollection.getCollectionData().nextItemIndex;
    val nftOwnerAddress = net.randomAddress();
    val content: Cell<SnakeString> = beginCell().storeString("Content").endCell() as Cell<SnakeString>;

    var deployList: map<uint64, BatchDeployDictItem> = [];
    val indexes: array<int> = [nextItemIndex, nextItemIndex + 1, nextItemIndex + 2];

    var i = 0;
    while (i < 3) {
        deployList.set(indexes.get(i), BatchDeployDictItem {
            attachTonAmount: ton("0.02"),
            initParams: NftItemInitAtDeployment {
                ownerAddress: nftOwnerAddress,
                content,
            }.toCell(),
        });
        i += 1;
    }

    val nftDeployResult = nftCollection.sendBatchDeployNfts(
        deployer.address,
        0,  // queryId
        deployList,
        {
            value: ton("0.5"),
            bounce: true,
        }
    );

    expect(nftDeployResult).toHaveSuccessfulTx<BatchDeployNfts>({
        from: deployer.address,
        to: nftCollection.address,
    });

    // Check all NFTs were deployed
    i = 0;
    while (i < 3) {
        val index = indexes.get(i);
        val nftAddress = nftCollection.getNftAddressByIndex(index);

        expect(nftDeployResult).toHaveSuccessfulDeploy({
            from: nftCollection.address,
            to: nftAddress,
        });

        val nftItem = NftItemContract.fromAddress(nftAddress);
        val data = nftItem.getNftData();

        expect(data.isInitialized).toBeTrue();
        expect(data.itemIndex).toEqual(index);
        expect(data.ownerAddress!).toEqual(nftOwnerAddress);
        expect(data.collectionAddress).toEqual(nftCollection.address);
        expect(data.content).toEqual(content);

        i += 1;
    }
}

get fun `test nft: should change owner`() {
    val (nftCollection, deployer, _) = setupTest();
    val oldOwnerAddress = nftCollection.getCollectionData().adminAddress;
    val newOwner = net.treasury("new-owner");

    val result = nftCollection.sendChangeCollectionAdmin(
        deployer.address,
        0,  // queryId
        newOwner.address,
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(result).toHaveSuccessfulTx<ChangeCollectionAdmin>({
        from: deployer.address,
        to: nftCollection.address,
    });

    val newOwnerAddress = nftCollection.getCollectionData().adminAddress;

    expect(oldOwnerAddress).toNotEqual(newOwnerAddress);
    expect(newOwnerAddress).toEqual(newOwner.address);
}

// ==================== NFTItem tests ====================

get fun `test nft: should transfer ownership`() {
    val (nftCollection, _, _) = setupTest();
    val nftOwner = net.treasury("nft-owner");
    val nftReceiverAddress = net.randomAddress();

    val nftItem = nftFixture(nftCollection, nftOwner.address);

    val ownerBeforeTransfer = nftItem.getNftData().ownerAddress;
    expect(ownerBeforeTransfer!).toEqual(nftOwner.address);

    val result = nftItem.sendAskToChangeOwnership(
        nftOwner.address,
        0,  // queryId
        nftReceiverAddress,
        null,  // sendExcessesTo
        createEmptyDict(),  // customPayload
        0,  // forwardTonAmount
        beginCell().storeBool(false).toSlice(),  // forwardPayload
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(result).toHaveSuccessfulTx<AskToChangeOwnership>({
        from: nftOwner.address,
        to: nftItem.address,
    });

    // Should NOT have notification to receiver (forwardAmount = 0)
    expect(result).toNotHaveTx<NotificationForNewOwner>({
        from: nftItem.address,
        to: nftReceiverAddress,
    });

    val ownerAfterTransfer = nftItem.getNftData().ownerAddress;
    expect(ownerAfterTransfer!).toEqual(nftReceiverAddress);
}

get fun `test nft: should transfer ownership and return excesses`() {
    val (nftCollection, _, _) = setupTest();

    val nftOwner = net.treasury("nft-owner");
    val nftReceiverAddress = net.randomAddress();
    val excessesAddress = net.randomAddress();

    val nftItem = nftFixture(nftCollection, nftOwner.address);

    val ownerBeforeTransfer = nftItem.getNftData().ownerAddress;
    expect(ownerBeforeTransfer!).toEqual(nftOwner.address);

    val result = nftItem.sendAskToChangeOwnership(
        nftOwner.address,
        0,  // queryId
        nftReceiverAddress,
        excessesAddress,  // sendExcessesTo
        createEmptyDict(),  // customPayload
        0,  // forwardTonAmount
        beginCell().storeBool(false).toSlice(),  // forwardPayload
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(result).toHaveSuccessfulTx<AskToChangeOwnership>({
        from: nftOwner.address,
        to: nftItem.address,
    });

    expect(result).toHaveTx<ReturnExcessesBack>({
        from: nftItem.address,
        to: excessesAddress,
        bounce: false,
    });

    val ownerAfterTransfer = nftItem.getNftData().ownerAddress;
    expect(ownerAfterTransfer!).toEqual(nftReceiverAddress);
}

get fun `test nft: should not transfer ownership not from owner`() {
    val (nftCollection, _, _) = setupTest();
    val nftOwner = net.treasury("nft-owner");
    val notOwner = net.treasury("not-owner");
    val nftReceiverAddress = net.randomAddress();

    val nftItem = nftFixture(nftCollection, nftOwner.address);

    val ownerBeforeTransfer = nftItem.getNftData().ownerAddress;
    expect(ownerBeforeTransfer!).toEqual(nftOwner.address);

    val result = nftItem.sendAskToChangeOwnership(
        notOwner.address,  // NOT the owner!
        0,  // queryId
        nftReceiverAddress,
        null,  // sendExcessesTo
        createEmptyDict(),  // customPayload
        0,  // forwardTonAmount
        createEmptySlice(),  // forwardPayload
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(result).toHaveFailedTx<AskToChangeOwnership>({
        from: notOwner.address,
        to: nftItem.address,
        exitCode: 401,
    });

    // Owner should NOT have changed
    val ownerAfterTransfer = nftItem.getNftData().ownerAddress;
    expect(ownerAfterTransfer!).toEqual(ownerBeforeTransfer!);
}

get fun `test nft: should transfer ownership with notification`() {
    val (nftCollection, _, _) = setupTest();
    val nftOwner = net.treasury("nft-owner");
    val nftReceiverAddress = net.randomAddress();

    val nftItem = nftFixture(nftCollection, nftOwner.address);

    val ownerBeforeTransfer = nftItem.getNftData().ownerAddress;
    expect(ownerBeforeTransfer!).toEqual(nftOwner.address);

    val forwardAmount = ton("0.01");
    val forwardBody = beginCell().storeUint(0, 32).storeString("Hello!").endCell();
    val queryId = 42;

    val result = nftItem.sendAskToChangeOwnership(
        nftOwner.address,
        queryId,
        nftReceiverAddress,
        null,  // sendExcessesTo
        createEmptyDict(),  // customPayload
        forwardAmount,
        beginCell().storeBool(true).storeRef(forwardBody).toSlice(),  // forwardPayload as ref
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(result).toHaveSuccessfulTx<AskToChangeOwnership>({
        from: nftOwner.address,
        to: nftItem.address,
    });

    expect(result).toHaveTx<NotificationForNewOwner>({
        from: nftItem.address,
        to: nftReceiverAddress,
        value: forwardAmount,
        bounce: false,
        // TODO check body content
    });

    val ownerAfterTransfer = nftItem.getNftData().ownerAddress;
    expect(ownerAfterTransfer!).toEqual(nftReceiverAddress);
}

get fun `test nft: should get static data`() {
    val (nftCollection, _, _) = setupTest();
    val nftOwner = net.treasury("nft-owner");
    val randomTreasury = net.treasury("random-treasury");

    val nftItem = nftFixture(nftCollection, nftOwner.address);

    val queryId = 42;
    val nftData = nftItem.getNftData();

    val result = nftItem.sendRequestStaticData(
        randomTreasury.address,
        queryId,
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(result).toHaveSuccessfulTx<RequestStaticData>({
        from: randomTreasury.address,
        to: nftItem.address,
    });

    expect(result).toHaveTx<ResponseStaticData>({
        from: nftItem.address,
        to: randomTreasury.address,
        bounce: false,
        body: ResponseStaticData {
            queryId,
            itemIndex: nftData.itemIndex,
            collectionAddress: nftData.collectionAddress,
        }.toCell(),
    });
}

get fun `test nft: should fail when receiver in different workchain`() {
    val (nftCollection, _, _) = setupTest();
    val nftOwner = net.treasury("nft-owner");
    val nftReceiverAddress = net.randomAddress("random_user", -1);

    val nftItem = nftFixture(nftCollection, nftOwner.address);

    val result = nftItem.sendAskToChangeOwnership(
        nftOwner.address,
        0,  // queryId
        nftReceiverAddress,
        null,  // sendExcessesTo
        createEmptyDict(),  // customPayload
        0,  // forwardTonAmount
        beginCell().storeBool(false).toSlice(),  // forwardPayload
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(result).toHaveFailedTx<AskToChangeOwnership>({
        from: nftOwner.address,
        to: nftItem.address,
        exitCode: 333,
    });
}

get fun `test nft: should fail when op not on list`() {
    val (nftCollection, _, _) = setupTest();
    val nftOwner = net.treasury("nft-owner");
    val randomTreasury = net.treasury("random-treasury");

    val nftItem = nftFixture(nftCollection, nftOwner.address);

    val queryId = 42;
    val invalidOpcode = 0x123459;

    val result = nftItem.sendAny(
        randomTreasury.address,
        beginCell().storeUint(invalidOpcode, 32).storeUint(queryId, 64).endCell(),
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(result).toHaveTx({
        from: randomTreasury.address,
        to: nftItem.address,
        exitCode: 0xFFFF,
    });
}

get fun `test nft: should fail when response address in different workchain`() {
    val (nftCollection, _, _) = setupTest();
    val nftOwner = net.treasury("nft-owner");
    val nftReceiverAddress = net.randomAddress();
    val excessesAddress = net.randomAddress("excesses", -1);  // masterchain

    val nftItem = nftFixture(nftCollection, nftOwner.address);

    val result = nftItem.sendAskToChangeOwnership(
        nftOwner.address,
        0,  // queryId
        nftReceiverAddress,
        excessesAddress,  // sendExcessesTo in different workchain
        createEmptyDict(),  // customPayload
        0,  // forwardTonAmount
        beginCell().storeBool(false).toSlice(),  // forwardPayload
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(result).toHaveFailedTx<AskToChangeOwnership>({
        from: nftOwner.address,
        to: nftItem.address,
        exitCode: 333,
    });
}

get fun `test nft: should fail with no fwd payload provided`() {
    val (nftCollection, _, _) = setupTest();
    val nftOwner = net.treasury("nft-owner");
    val nftReceiverAddress = net.randomAddress();
    val responseAddress = net.randomAddress();

    val nftItem = nftFixture(nftCollection, nftOwner.address);

    val ownerBeforeTransfer = nftItem.getNftData().ownerAddress;
    expect(ownerBeforeTransfer!).toEqual(nftOwner.address);

    val body = beginCell()
        .storeUint(0x5fcc3d14, 32)  // op::transfer
        .storeUint(42, 64)          // queryId
        .storeAddress(nftReceiverAddress)  // new_owner
        .storeAddress(responseAddress)     // response_destination
        .storeMaybeRef(null)        // custom_payload
        .storeCoins(999)            // forward_amount
        // missing forward_payload!
        .endCell();

    val result = nftItem.sendAny(
        nftOwner.address,
        body,
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(result).toHaveFailedTx({
        from: nftOwner.address,
        to: nftItem.address,
        body,
        exitCode: 708,  // No forward payload provided
    });

    val ownerAfterTransfer = nftItem.getNftData().ownerAddress;
    expect(ownerAfterTransfer!).toEqual(ownerBeforeTransfer!);
}

get fun `test nft: should transfer ownership with forward payload in slice`() {
    val (nftCollection, _, _) = setupTest();
    val nftOwner = net.treasury("nft-owner");
    val nftReceiverAddress = net.randomAddress();

    val nftItem = nftFixture(nftCollection, nftOwner.address);
    val queryId = 42;
    val forwardAmount = ton("0.01");

    // forward_payload as inline slice (not ref)
    val forwardPayloadSlice = beginCell()
        .storeBool(false)  // not a ref
        .storeUint(0xDEADBEEF, 32)  // some payload data
        .toSlice();

    val result = nftItem.sendAskToChangeOwnership(
        nftOwner.address,
        queryId,
        nftReceiverAddress,
        null,  // sendExcessesTo
        createEmptyDict(),  // customPayload
        forwardAmount,
        forwardPayloadSlice,
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(result).toHaveSuccessfulTx<AskToChangeOwnership>({
        from: nftOwner.address,
        to: nftItem.address,
    });

    expect(result).toHaveTx<NotificationForNewOwner>({
        from: nftItem.address,
        to: nftReceiverAddress,
        bounce: false,
    });

    val ownerAfterTransfer = nftItem.getNftData().ownerAddress;
    expect(ownerAfterTransfer!).toEqual(nftReceiverAddress);
}

get fun `test nft: should fail with incomplete transfer body`() {
    val (nftCollection, _, _) = setupTest();
    val nftOwner = net.treasury("nft-owner");

    val nftItem = nftFixture(nftCollection, nftOwner.address);

    val ownerBeforeTransfer = nftItem.getNftData().ownerAddress;
    expect(ownerBeforeTransfer!).toEqual(nftOwner.address);

    // Send transfer op with only queryId (missing new_owner and rest)
    val body = beginCell()
        .storeUint(0x5fcc3d14, 32)  // op::transfer
        .storeUint(42, 64)          // queryId
        // missing new_owner and rest!
        .endCell();

    val result = nftItem.sendAny(
        nftOwner.address,
        body,
        {
            value: ton("0.05"),
            bounce: true,
        }
    );

    expect(result).toHaveFailedTx({
        from: nftOwner.address,
        to: nftItem.address,
        body,
        exitCode: 9,  // cell underflow
    });

    val ownerAfterTransfer = nftItem.getNftData().ownerAddress;
    expect(ownerAfterTransfer!).toEqual(ownerBeforeTransfer!);
}

get fun `test nft: bench should deploy 100 nfts via batch deploy`() {
    val (nftCollection, deployer, _) = setupTest();
    val nftOwnerAddress = net.randomAddress();
    val content: Cell<SnakeString> = beginCell().storeString("Content").endCell() as Cell<SnakeString>;

    var deployList: map<uint64, BatchDeployDictItem> = [];

    var i = 0;
    while (i < 100) {
        deployList.set(i, BatchDeployDictItem {
            attachTonAmount: ton("0.02"),
            initParams: NftItemInitAtDeployment {
                ownerAddress: nftOwnerAddress,
                content,
            }.toCell(),
        });
        i += 1;
    }

    val nftDeployResult = nftCollection.sendBatchDeployNfts(
        deployer.address,
        0,  // queryId
        deployList,
        {
            value: ton("5"),  // more TON for 100 NFTs
            bounce: true,
        }
    );

    expect(nftDeployResult).toHaveSuccessfulTx<BatchDeployNfts>({
        from: deployer.address,
        to: nftCollection.address,
    });

    // Check first and last NFT were deployed
    val firstNftAddress = nftCollection.getNftAddressByIndex(0);
    expect(nftDeployResult).toHaveSuccessfulDeploy({
        from: nftCollection.address,
        to: firstNftAddress,
    });

    val lastNftAddress = nftCollection.getNftAddressByIndex(99);
    expect(nftDeployResult).toHaveSuccessfulDeploy({
        from: nftCollection.address,
        to: lastNftAddress,
    });

    // Verify collection state
    val newNextItemIndex = nftCollection.getCollectionData().nextItemIndex;
    expect(newNextItemIndex).toEqual(100);
}
