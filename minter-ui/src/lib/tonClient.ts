import { TonClient } from "@ton/ton";
import { Address, type Cell, beginCell } from "@ton/core";

const clients: Record<string, TonClient> = {};

export function getTonClient(network: "mainnet" | "testnet"): TonClient {
  if (!clients[network]) {
    const endpoint = network === "mainnet"
      ? "https://toncenter.com/api/v2/jsonRPC"
      : "https://testnet.toncenter.com/api/v2/jsonRPC";
    clients[network] = new TonClient({ endpoint });
  }
  return clients[network]!;
}

export interface JettonData {
  totalSupply: bigint;
  mintable: boolean;
  adminAddress: Address | null;
  jettonContent: Cell;
  jettonWalletCode: Cell;
}

export interface JettonMasterInfo {
  totalSupply: bigint;
  mintable: boolean;
  adminAddress: Address | null;
  metadata: {
    name?: string;
    symbol?: string;
    decimals?: string;
    description?: string;
    image?: string;
  };
}

const toncenterV3 = {
  mainnet: "https://toncenter.com/api/v3",
  testnet: "https://testnet.toncenter.com/api/v3",
};

async function fetchWithRetry(url: string, maxRetries = 4): Promise<Response> {
  let delay = 1000;
  for (let i = 0; i <= maxRetries; i++) {
    const res = await fetch(url);
    if (res.status === 429 && i < maxRetries) {
      await new Promise((r) => setTimeout(r, delay));
      delay *= 2;
      continue;
    }
    return res;
  }
  throw new Error("Max retries exceeded");
}

/**
 * Fetch jetton info via toncenter v3 API — resolves off-chain metadata automatically.
 */
export async function fetchJettonMaster(
  network: "mainnet" | "testnet",
  address: string,
): Promise<JettonMasterInfo> {
  const base = toncenterV3[network];
  const res = await fetchWithRetry(`${base}/jetton/masters?address=${encodeURIComponent(address)}&limit=1&offset=0`);
  if (!res.ok) throw new Error(`Toncenter API error: ${res.status}`);

  const json = await res.json();
  const masters = json.jetton_masters;
  if (!masters || masters.length === 0) {
    throw new Error("Jetton not found");
  }

  const master = masters[0];
  const rawAddr = master.address as string; // "0:..."

  // Resolved metadata from toncenter (includes off-chain data)
  const metaEntry = json.metadata?.[rawAddr]?.token_info?.[0];

  let adminAddr: Address | null = null;
  try {
    if (master.admin_address) {
      adminAddr = Address.parse(master.admin_address);
    }
  } catch { /* addr_none */ }

  return {
    totalSupply: BigInt(master.total_supply),
    mintable: master.mintable,
    adminAddress: adminAddr,
    metadata: {
      name: metaEntry?.name || undefined,
      symbol: metaEntry?.symbol || undefined,
      decimals: metaEntry?.extra?.decimals || master.jetton_content?.decimals || undefined,
      description: metaEntry?.description || undefined,
      image: metaEntry?.image || undefined,
    },
  };
}

/**
 * Calls get_jetton_data on a minter contract using TupleReader
 * (the auto-generated wrapper's StackReader is incompatible with TonClient)
 */
export async function getJettonData(
  client: TonClient,
  minterAddress: Address,
): Promise<JettonData> {
  const result = await client.runMethod(minterAddress, "get_jetton_data");
  const totalSupply = result.stack.readBigNumber();
  const mintable = result.stack.readBoolean();
  const adminAddress = result.stack.readAddressOpt();
  const jettonContent = result.stack.readCell();
  const jettonWalletCode = result.stack.readCell();

  return { totalSupply, mintable, adminAddress, jettonContent, jettonWalletCode };
}

/**
 * Calls get_wallet_address on a minter contract using TupleReader
 */
export async function getWalletAddress(
  client: TonClient,
  minterAddress: Address,
  ownerAddress: Address,
): Promise<Address> {
  const result = await client.runMethod(minterAddress, "get_wallet_address", [
    {
      type: "slice",
      cell: beginCell().storeAddress(ownerAddress).endCell(),
    },
  ]);
  return result.stack.readAddress();
}
