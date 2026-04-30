import "@stdlib/strings"
import "@acton/build"
import "@acton/crypto"
import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "../../contracts/messages"
import "../../contracts/storage"
import "../../wrappers/WalletV5Contract"

const W5_DEFAULT_SEED_HEX = "0x2222222222222222222222222222222222222222222222222222222222222222"
const W5_DEFAULT_SUBWALLET_ID = "0"
const W5_DEFAULT_DEPLOY_VALUE = "50000000"
const W5_DEFAULT_TRANSFER_VALUE = "10000000"

fun parseDecOrHexInt(s: string): int {
    var slc = s.beginParse();
    var bits = slc.remainingBitsCount();
    var isHex = false;
    if (bits >= 16) {
        val prefix = slc.preloadUint(16);
        if (prefix == 0x3078 || prefix == 0x3058) {
            slc.loadUint(16);
            bits -= 16;
            isHex = true;
        }
    }
    if (bits == 0) {
        throw 901;
    }
    var result: int = 0;
    while (bits >= 8) {
        val c = slc.loadUint(8);
        var digit: int = -1;
        if (c >= 0x30 && c <= 0x39) {
            digit = c - 0x30;
        } else if (isHex && c >= 0x41 && c <= 0x46) {
            digit = c - 0x41 + 10;
        } else if (isHex && c >= 0x61 && c <= 0x66) {
            digit = c - 0x61 + 10;
        }
        if (digit < 0) {
            throw 902;
        }
        result = result * (isHex ? 16 : 10) + digit;
        bits -= 8;
    }
    return result;
}

fun promptW5Int(envName: string, message: string, default: string): int {
    val fromEnv = env<int>(envName);
    if (fromEnv != null) {
        return fromEnv;
    }
    return parseDecOrHexInt(prompt(message, "decimal or 0x...", default));
}

fun promptW5Coins(envName: string, message: string, default: string): coins {
    val fromEnv = env<coins>(envName);
    if (fromEnv != null) {
        return fromEnv;
    }
    return parseInt(prompt(message, "in nanotons", default));
}

fun promptW5AddressRequired(envName: string, message: string): address {
    val fromEnv = env<address>(envName);
    if (fromEnv != null) {
        return fromEnv;
    }
    return parseAddress(prompt(message, "EQ... / kQ...", ""));
}

fun promptW5Wallet(envName: string, message: string): ActonWallet {
    val nameFromEnv = env<string>(envName);
    if (nameFromEnv != null) {
        return scripts.wallet(nameFromEnv);
    }
    return scripts.wallet(promptWallet(message));
}

fun promptW5KeyPair(): KeyPair {
    val seed = promptW5Int(
        "W5_SEED",
        "Enter W5 wallet seed (hex int)",
        W5_DEFAULT_SEED_HEX,
    );
    return crypto.seedToKeyPair(seed);
}

fun promptW5SubwalletId(): int {
    return promptW5Int(
        "W5_SUBWALLET_ID",
        "Enter W5 subwallet id",
        W5_DEFAULT_SUBWALLET_ID,
    );
}

fun buildW5FromKey(keyPair: KeyPair, subwalletId: int): WalletV5Contract {
    return WalletV5Contract.fromStorage(Storage {
        isSignatureAllowed: true,
        seqno: 0,
        subwalletId,
        publicKey: keyPair.publicKey,
        extensions: [],
    });
}

fun resolveW5Wallet(keyPair: KeyPair, subwalletId: int): WalletV5Contract {
    val derived = buildW5FromKey(keyPair, subwalletId);
    val explicit = env<address>("W5_WALLET_ADDRESS");
    if (explicit != null && explicit != derived.address) {
        println(
            "W5_WALLET_ADDRESS={} does not match address derived from key+subwalletId ({}). Using env address; get methods will be unavailable for library-coded wallets.",
            explicit,
            derived.address,
        );
        return WalletV5Contract { address: explicit };
    }
    return derived;
}

fun deployW5Wallet(
    deployer: ActonWallet,
    keyPair: KeyPair,
    subwalletId: int,
    value: coins,
): WalletV5Contract {
    val wallet = buildW5FromKey(keyPair, subwalletId);
    val res = wallet.deploy(deployer.address, { value, bounce: false });
    res.waitForFirstTransaction();
    return wallet;
}

fun buildSendAction(
    dest: address,
    value: coins,
    body: cell? = null,
    mode: int = SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_IGNORE_ERRORS,
): SendAction {
    var actionBody = body;
    if (actionBody == null) {
        actionBody = createEmptyCell();
    }
    return SendAction {
        mode,
        messageCell: createMessage({
            bounce: false,
            value,
            dest,
            body: actionBody!,
        }).messageCell,
    };
}

fun printW5Info(wallet: WalletV5Contract, label: string) {
    val deployed = scripts.isContractDeployed(wallet.address);
    println("{} ADDRESS={}", label, wallet.address);
    println("{} DEPLOYED={}", label, deployed);
    if (!deployed) {
        return;
    }
    val extensions = wallet.getExtensionsArray();
    println("{} SEQNO={}", label, wallet.getSeqno());
    println("{} PUBLIC_KEY={}", label, wallet.getPublicKey());
    println("{} SUBWALLET_ID={}", label, wallet.getSubwalletId());
    println("{} SIGNATURE_ALLOWED={}", label, wallet.isSignatureAllowed());
    println("{} EXTENSIONS_COUNT={}", label, extensions.size());
    var i = 0;
    while (i < extensions.size()) {
        println("{} EXTENSION[{}]={}", label, i, extensions.get(i));
        i += 1;
    }
}
