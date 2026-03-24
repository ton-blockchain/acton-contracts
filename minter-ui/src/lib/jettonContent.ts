import { beginCell, Cell, Dictionary } from "@ton/core";

const ONCHAIN_CONTENT_PREFIX = 0x00;
const SNAKE_DATA_PREFIX = 0x00;

const sha256Keys: Record<string, Buffer> = {};

async function sha256(key: string): Promise<Buffer> {
  if (!sha256Keys[key]) {
    const data = new TextEncoder().encode(key);
    const hash = await crypto.subtle.digest("SHA-256", data);
    sha256Keys[key] = Buffer.from(hash);
  }
  return sha256Keys[key]!;
}

function makeSnakeCell(data: Buffer): Cell {
  const firstChunkSize = 126; // 127 bytes - 1 byte snake prefix
  const chunkSize = 127;

  if (data.length <= firstChunkSize) {
    return beginCell()
      .storeUint(SNAKE_DATA_PREFIX, 8)
      .storeBuffer(data)
      .endCell();
  }

  const chunks: Buffer[] = [];
  chunks.push(data.subarray(0, firstChunkSize));
  let offset = firstChunkSize;
  while (offset < data.length) {
    const end = Math.min(offset + chunkSize, data.length);
    chunks.push(data.subarray(offset, end));
    offset = end;
  }

  let cell: Cell | null = null;
  for (let i = chunks.length - 1; i >= 0; i--) {
    const builder = beginCell();
    if (i === 0) {
      builder.storeUint(SNAKE_DATA_PREFIX, 8);
    }
    builder.storeBuffer(chunks[i]!);
    if (cell) {
      builder.storeRef(cell);
    }
    cell = builder.endCell();
  }
  return cell!;
}

export interface JettonMetadata {
  name: string;
  symbol: string;
  decimals: string;
  description?: string;
  image?: string;
  imageData?: string;
}

export async function buildOnchainMetadata(metadata: JettonMetadata): Promise<Cell> {
  const dict = Dictionary.empty(Dictionary.Keys.Buffer(32), Dictionary.Values.Cell());

  const entries: [string, string][] = [
    ["name", metadata.name],
    ["symbol", metadata.symbol],
    ["decimals", metadata.decimals],
  ];
  if (metadata.description) entries.push(["description", metadata.description]);
  if (metadata.image) entries.push(["image", metadata.image]);
  if (metadata.imageData) entries.push(["image_data", metadata.imageData]);

  for (const [key, value] of entries) {
    const keyHash = await sha256(key);
    const valueCell = makeSnakeCell(Buffer.from(value, "utf-8"));
    dict.set(keyHash, valueCell);
  }

  return beginCell()
    .storeUint(ONCHAIN_CONTENT_PREFIX, 8)
    .storeDict(dict)
    .endCell();
}

const OFFCHAIN_CONTENT_PREFIX = 0x01;

function readSnakeData(cell: Cell, skipPrefix = true): string {
  const parts: Buffer[] = [];
  let current: Cell | null = cell;
  let isFirst = true;
  while (current) {
    const cs = current.beginParse();
    if (isFirst && skipPrefix) {
      cs.loadUint(8); // skip snake prefix byte
      isFirst = false;
    }
    const bits = cs.remainingBits;
    if (bits > 0) {
      parts.push(cs.loadBuffer(bits / 8));
    }
    current = cs.remainingRefs > 0 ? cs.loadRef() : null;
  }
  return Buffer.concat(parts).toString("utf-8");
}

/**
 * Parse jetton content cell. Supports both on-chain (0x00) and off-chain (0x01) formats.
 * For off-chain, returns the URL in a special `_offchainUrl` field.
 */
export function parseOnchainMetadata(content: Cell): Partial<JettonMetadata> & { _offchainUrl?: string } {
  const result: Partial<JettonMetadata> & { _offchainUrl?: string } = {};
  try {
    const slice = content.beginParse();
    const prefix = slice.loadUint(8);

    if (prefix === OFFCHAIN_CONTENT_PREFIX) {
      // Off-chain: rest of the cell is a snake-encoded URL (no additional snake prefix byte)
      const bits = slice.remainingBits;
      const parts: Buffer[] = [];
      if (bits > 0) parts.push(slice.loadBuffer(bits / 8));
      let ref: Cell | null = slice.remainingRefs > 0 ? slice.loadRef() : null;
      while (ref) {
        const rs = ref.beginParse();
        const rb = rs.remainingBits;
        if (rb > 0) parts.push(rs.loadBuffer(rb / 8));
        ref = rs.remainingRefs > 0 ? rs.loadRef() : null;
      }
      result._offchainUrl = Buffer.concat(parts).toString("utf-8");
      return result;
    }

    if (prefix !== ONCHAIN_CONTENT_PREFIX) return result;

    const dict = slice.loadDict(Dictionary.Keys.Buffer(32), Dictionary.Values.Cell());

    const knownKeys = ["name", "symbol", "decimals", "description", "image"];
    for (const key of knownKeys) {
      if (sha256Keys[key]) {
        const cell = dict.get(sha256Keys[key]!);
        if (cell) {
          (result as any)[key] = readSnakeData(cell);
        }
      }
    }
  } catch {
    // Ignore parse errors
  }
  return result;
}

// Pre-compute known keys
(async () => {
  for (const key of ["name", "symbol", "decimals", "description", "image", "image_data", "uri"]) {
    await sha256(key);
  }
})();
