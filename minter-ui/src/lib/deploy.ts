import { Address, beginCell, Cell, contractAddress, storeStateInit, toNano } from "@ton/core";
import { JettonMinterContract } from "../../wrappers/JettonMinterContract.ts";
import { JettonWalletContract } from "../../wrappers/JettonWalletContract.ts";
import { buildOnchainMetadata, type JettonMetadata } from "./jettonContent.ts";

/**
 * Convert a decimal string like "123.456" to nano-units bigint
 * without floating point precision loss.
 */
export function parseUnits(amount: string, decimals: number): bigint {
  const [whole = "", fracRaw = ""] = amount.split(".");
  const frac = fracRaw.slice(0, decimals).padEnd(decimals, "0");
  return BigInt(whole + frac);
}

// Opcodes from the contract
const OP_MINT = 0x00000015;
const OP_CHANGE_ADMIN = 0x00000003;
const OP_CHANGE_CONTENT = 0x00000004;
const OP_BURN = 0x595f07bc;
const OP_TRANSFER = 0x0f8a7ea5;

export async function buildDeployMessage(params: {
  metadata: JettonMetadata;
  ownerAddress: Address;
  mintAmount: bigint;
}) {
  const content = await buildOnchainMetadata(params.metadata);
  const walletCode = JettonWalletContract.CodeCell;
  const minterCode = JettonMinterContract.CodeCell;

  // Build initial data cell for the minter contract
  // MinterStorage: totalSupply(coins) + adminAddress(address) + content(ref cell) + walletCode(ref cell)
  const data = beginCell()
    .storeCoins(0n) // totalSupply starts at 0
    .storeAddress(params.ownerAddress) // admin
    .storeRef(content) // jetton content
    .storeRef(walletCode) // wallet code
    .endCell();

  const stateInit = { code: minterCode, data };
  const addr = contractAddress(0, stateInit);

  // Build mint message body
  const mintBody = buildMintBody({
    toAddress: params.ownerAddress,
    jettonAmount: params.mintAmount,
    forwardTonAmount: toNano("0.02"),
    totalTonAmount: toNano("0.05"),
  });

  return {
    contractAddress: addr,
    stateInit,
    mintBody,
  };
}

export function buildMintBody(params: {
  toAddress: Address;
  jettonAmount: bigint;
  forwardTonAmount: bigint;
  totalTonAmount: bigint;
  queryId?: bigint;
}) {
  const { toAddress, jettonAmount, forwardTonAmount, totalTonAmount, queryId = 0n } = params;

  // InternalTransferStep message that the minter forwards to the wallet
  const transferBody = beginCell()
    .storeUint(0x178d4519, 32) // internal_transfer op
    .storeUint(queryId, 64)
    .storeCoins(jettonAmount)
    .storeAddress(null) // from address (null = minter)
    .storeAddress(toAddress) // response address (send excesses back)
    .storeCoins(forwardTonAmount) // forward_ton_amount
    .storeUint(0, 1) // no forward payload
    .endCell();

  // MintNewJettons message
  return beginCell()
    .storeUint(OP_MINT, 32) // op mint
    .storeUint(queryId, 64)
    .storeAddress(toAddress) // to_address
    .storeCoins(totalTonAmount) // amount of TON for the internal message
    .storeRef(transferBody) // master_msg
    .endCell();
}

export function buildChangeAdminBody(newAdmin: Address, queryId = 0n): Cell {
  return beginCell()
    .storeUint(OP_CHANGE_ADMIN, 32)
    .storeUint(queryId, 64)
    .storeAddress(newAdmin)
    .endCell();
}

export async function buildChangeContentBody(metadata: JettonMetadata, queryId = 0n): Promise<Cell> {
  const content = await buildOnchainMetadata(metadata);
  return beginCell()
    .storeUint(OP_CHANGE_CONTENT, 32)
    .storeUint(queryId, 64)
    .storeRef(content)
    .endCell();
}

export function buildBurnBody(amount: bigint, responseAddress: Address, queryId = 0n): Cell {
  return beginCell()
    .storeUint(OP_BURN, 32)
    .storeUint(queryId, 64)
    .storeCoins(amount)
    .storeAddress(responseAddress) // response_destination
    .endCell();
}

export function buildTransferBody(params: {
  toAddress: Address;
  amount: bigint;
  responseAddress: Address;
  forwardTonAmount?: bigint;
  forwardPayload?: Cell | null;
  queryId?: bigint;
}): Cell {
  const {
    toAddress,
    amount,
    responseAddress,
    forwardTonAmount = 0n,
    forwardPayload = null,
    queryId = 0n,
  } = params;

  const builder = beginCell()
    .storeUint(OP_TRANSFER, 32)
    .storeUint(queryId, 64)
    .storeCoins(amount)
    .storeAddress(toAddress)
    .storeAddress(responseAddress)
    .storeUint(0, 1) // no custom payload
    .storeCoins(forwardTonAmount);

  if (forwardPayload) {
    builder.storeUint(1, 1).storeRef(forwardPayload);
  } else {
    builder.storeUint(0, 1);
  }

  return builder.endCell();
}
