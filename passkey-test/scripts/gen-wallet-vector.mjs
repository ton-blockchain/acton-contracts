// End-to-end test-vector generator for the Acton PasskeyWallet contract.
//
// Builds a real Body cell, takes its TVM cell hash, uses that hash as the
// WebAuthn challenge, runs a P-256 keypair through the WebAuthn cdj signing
// flow, and prints all values needed to drive an integration test.
//
// Run with:  cd passkey-test && bun install && node scripts/gen-wallet-vector.mjs

import {
  createHash,
  createPrivateKey,
  createPublicKey,
  generateKeyPairSync,
  sign as nodeSign,
} from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Address, beginCell, Cell, toNano } from '@ton/core';

const __dirname = dirname(fileURLToPath(import.meta.url));
const KEYPAIR_FILE = resolve(__dirname, 'wallet-vector.key.pem');
const VECTOR_FILE = resolve(__dirname, 'wallet-vector.json');
const FORCE_REGENERATE = process.argv.includes('--regenerate');

const sha256 = (b) => createHash('sha256').update(b).digest();

function derToRawRS(der) {
  let off = 0;
  if (der[off++] !== 0x30) throw new Error('not a SEQUENCE');
  let seqLen = der[off++];
  if (seqLen & 0x80) {
    const n = seqLen & 0x7f;
    seqLen = 0;
    for (let i = 0; i < n; i++) seqLen = (seqLen << 8) | der[off++];
  }
  if (der[off++] !== 0x02) throw new Error('not an INTEGER (r)');
  const rLen = der[off++];
  let r = der.slice(off, off + rLen); off += rLen;
  if (der[off++] !== 0x02) throw new Error('not an INTEGER (s)');
  const sLen = der[off++];
  let s = der.slice(off, off + sLen); off += sLen;
  if (r.length > 32 && r[0] === 0x00) r = r.slice(1);
  if (s.length > 32 && s[0] === 0x00) s = s.slice(1);
  const out = Buffer.alloc(64, 0);
  r.copy(out, 32 - r.length);
  s.copy(out, 64 - s.length);
  return out;
}

// ─── Wallet config ────────────────────────────────────────────────────────
const RP_ID = 'localhost';
const ORIGIN = 'http://localhost:52261';

// ─── Generate (or load) a P-256 keypair ───────────────────────────────────
// Persist the keypair so the test vector is stable across re-runs.
let privateKey, publicKey;
if (existsSync(KEYPAIR_FILE)) {
  privateKey = createPrivateKey(readFileSync(KEYPAIR_FILE, 'utf8'));
  publicKey = createPublicKey(privateKey);
} else {
  ({ privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' }));
  writeFileSync(KEYPAIR_FILE, privateKey.export({ format: 'pem', type: 'pkcs8' }));
  console.error(`(saved fresh keypair to ${KEYPAIR_FILE}; commit it for stable vectors)`);
}
const spki = publicKey.export({ format: 'der', type: 'spki' });
const uncompressed = spki.slice(spki.length - 65);
if (uncompressed[0] !== 0x04) throw new Error('expected 0x04 prefix');
const x = uncompressed.slice(1, 33);
const y = uncompressed.slice(33, 65);
const pubkeyCompressed = Buffer.concat([Buffer.from([(y[31] & 1) ? 0x03 : 0x02]), x]);

// ─── authenticatorData: rpIdHash || flags=0x05 (UP|UV) || signCount=1 ─────
const rpIdHash = sha256(Buffer.from(RP_ID, 'utf8'));
const authData = Buffer.concat([
  rpIdHash,
  Buffer.from([0x05]),
  Buffer.from([0, 0, 0, 1]),
]);

// ─── Build the Body cell exactly as the contract will deserialize it ──────
// Body { seqno: uint32, validUntil: uint32, sendMode: uint8, outMsg: cell }
//
// outMsg is a real internal-message cell. We build a minimal one that the
// wallet would forward. Sandbox tests can decode this and check the receiver.
// Workchain 0, all-zero hash: the simplest deterministic address for the test.
const RECEIVER = new Address(0, Buffer.alloc(32, 0));
const outMsg = beginCell()
  // info (CommonMsgInfoRelaxed): int_msg_info, ihr_disabled=true, bounce=false, bounced=false
  // tag 0b0,                ihr_disabled=1, bounce=0, bounced=0, src=addr_none(00), dest=...
  // We just use createMsgInternal-style hand-encoding:
  .storeUint(0b01_0000, 6)                  // 0 (int_msg) 1 (ihr_disabled) 0 0 src=00 (2 bits in addr_none)
  .storeAddress(RECEIVER)                   // dest
  .storeCoins(toNano('0.001'))              // value (grams)
  .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1) // currency_collection, ihr_fee, fwd_fee, created_lt, created_at, init?, body inline
  .endCell();

const seqno = 0;
// Fixed far-future timestamp so the test vector doesn't decay. Tests should
// arrange `blockchain.now` to be earlier than this (Acton sandbox starts in
// 2024, plenty of headroom).
const validUntil = 4102444800; // 2100-01-01 UTC
const sendMode = 3; // pay_gas_separately + ignore_errors

const bodyCell = beginCell()
  .storeUint(seqno, 32)
  .storeUint(validUntil, 32)
  .storeUint(sendMode, 8)
  .storeRef(outMsg)
  .endCell();

const bodyHash = bodyCell.hash(); // 32-byte Buffer (Uint8Array): TVM HASHCU equivalent
const bodyHashBuf = Buffer.from(bodyHash);

// ─── Build clientDataJSON with challenge = base64url(bodyHash) ────────────
const challengeB64u = bodyHashBuf
  .toString('base64')
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const cdj = JSON.stringify({
  type: 'webauthn.get',
  challenge: challengeB64u,
  origin: ORIGIN,
  crossOrigin: false,
});
const cdjBuf = Buffer.from(cdj, 'utf8');
const cdjHash = sha256(cdjBuf);

// 3-piece split for HASHEXT_SHA256 on chain:
const cdjStr = cdj;
const challengeMarker = '"challenge":"';
const cm = cdjStr.indexOf(challengeMarker);
const cmEnd = cm + challengeMarker.length;
const challengeEnd = cdjStr.indexOf('"', cmEnd);
const cdjPrefixBuf = Buffer.from(cdjStr.slice(0, cmEnd), 'utf8');
const cdjSuffixBuf = Buffer.from(cdjStr.slice(challengeEnd), 'utf8');

// ─── Sign authData || sha256(cdj) with ECDSA-P256-SHA256 ──────────────────
// ECDSA uses a random k each call, so re-signing changes the signature.
// We persist the signature to keep the test vector stable; pass --regenerate
// to roll a fresh one.
const signedMessage = Buffer.concat([authData, cdjHash]);
let sigRaw;
if (!FORCE_REGENERATE && existsSync(VECTOR_FILE)) {
  const prev = JSON.parse(readFileSync(VECTOR_FILE, 'utf8'));
  // Sanity-check: stored signature must still be valid for the current message.
  const { createVerify } = await import('node:crypto');
  const verifier = createVerify('sha256');
  verifier.update(signedMessage);
  // Convert raw r||s back to DER for verification.
  const r = Buffer.from(prev.signature_raw, 'hex').slice(0, 32);
  const s = Buffer.from(prev.signature_raw, 'hex').slice(32, 64);
  const rTrimmed = r[0] & 0x80 ? Buffer.concat([Buffer.from([0]), r]) : r;
  const sTrimmed = s[0] & 0x80 ? Buffer.concat([Buffer.from([0]), s]) : s;
  const seq = Buffer.concat([
    Buffer.from([0x02, rTrimmed.length]), rTrimmed,
    Buffer.from([0x02, sTrimmed.length]), sTrimmed,
  ]);
  const der = Buffer.concat([Buffer.from([0x30, seq.length]), seq]);
  if (verifier.verify(publicKey, der)) {
    sigRaw = Buffer.from(prev.signature_raw, 'hex');
  } else {
    console.error('(stored signature no longer matches; re-signing)');
  }
}
if (!sigRaw) {
  const sigDer = nodeSign('sha256', signedMessage, privateKey);
  sigRaw = derToRawRS(sigDer);
  writeFileSync(VECTOR_FILE, JSON.stringify({ signature_raw: sigRaw.toString('hex') }, null, 2));
}

// ─── Print Tolk-ready constants ───────────────────────────────────────────
const out = (name, buf) => console.log(`${name.padEnd(20)} = "${Buffer.from(buf).toString('hex')}"  // ${buf.length} bytes`);

console.log('// === PasskeyWallet integration test vector ===');
console.log('// All values are hex strings ready for `"...".hexToSlice()` in Tolk.');
console.log();
console.log('// Storage init values:');
out('PUBKEY_COMPRESSED  ', pubkeyCompressed);
out('AUTH_DATA          ', authData);
out('CDJ_PREFIX         ', cdjPrefixBuf);
out('CDJ_SUFFIX         ', cdjSuffixBuf);
console.log(`// initial seqno: 0`);
console.log();
console.log('// External-message values (one signing of the body below):');
out('SIGNATURE_RAW      ', sigRaw);
out('CDJ_CHALLENGE_43   ', Buffer.from(challengeB64u, 'utf8'));
console.log();
console.log('// Body cell that was signed (TVM-serialised):');
out('BODY_BOC           ', bodyCell.toBoc({ idx: false }));
out('BODY_HASH          ', bodyHashBuf);
console.log(`// Body fields:  seqno=${seqno}  validUntil=${validUntil}  sendMode=${sendMode}`);
console.log(`// outMsg sends ${toNano('0.001')} nanoTON to ${RECEIVER.toString()}`);
console.log();
console.log(`// Sanity:`);
console.log(`//   sha256(cdj)    = ${cdjHash.toString('hex')}`);
console.log(`//   signedMessage  = authData || sha256(cdj)  (${signedMessage.length} bytes)`);
console.log(`//   sha256(signed) = ${sha256(signedMessage).toString('hex')}`);
