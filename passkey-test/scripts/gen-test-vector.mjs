// Synthesizes a real WebAuthn-style ES256 (P-256) assertion test vector.
// Run with: node scripts/gen-test-vector.mjs
//
// Produces hex strings for:
//   - authenticatorData (rpIdHash || flags || signCount)
//   - clientDataJSON   (UTF-8 bytes of the WebAuthn JSON)
//   - signedMessage    (authenticatorData || sha256(clientDataJSON))   -> input for P256_CHKSIGNS
//   - digest           (sha256(signedMessage))                          -> input for P256_CHKSIGNU
//   - signature_raw    (r||s, 64 bytes)
//   - pubkey_uncompressed (04 || X || Y, 65 bytes)
//   - pubkey_compressed   (02/03 || X, 33 bytes)  <- this is what TVM P256_CHKSIGN* wants

import { createHash, createPrivateKey, createPublicKey, sign as nodeSign, generateKeyPairSync } from 'node:crypto';

function sha256(buf) {
  return createHash('sha256').update(buf).digest();
}

// Convert Node's DER ECDSA signature into raw r||s (64 bytes total, big-endian, zero-padded).
function derToRawRS(der) {
  // SEQUENCE { INTEGER r, INTEGER s }
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
  // Strip a leading 0x00 used to keep ASN.1 INTEGER positive.
  if (r.length > 32 && r[0] === 0x00) r = r.slice(1);
  if (s.length > 32 && s[0] === 0x00) s = s.slice(1);
  if (r.length > 32 || s.length > 32) throw new Error('r/s too long');
  const out = Buffer.alloc(64, 0);
  r.copy(out, 32 - r.length);
  s.copy(out, 64 - s.length);
  return out;
}

// Generate P-256 keypair. Use a fixed seed-style approach for reproducibility:
// Node has no deterministic generation, but once we run this and bake the
// values into the test we have a stable vector forever.
const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });

const spkiDer = publicKey.export({ format: 'der', type: 'spki' });
// SubjectPublicKeyInfo for P-256 always ends with the 65-byte uncompressed point: 04||X||Y.
const uncompressed = spkiDer.slice(spkiDer.length - 65);
if (uncompressed[0] !== 0x04) throw new Error('expected 0x04 prefix on uncompressed point');
const x = uncompressed.slice(1, 33);
const y = uncompressed.slice(33, 65);
const compressed = Buffer.concat([Buffer.from([(y[31] & 1) ? 0x03 : 0x02]), x]);

// --- Build the WebAuthn-style authenticatorData ---
// rpIdHash = sha256("localhost"), flags = UP+UV (0x05), signCount = 1
const RP_ID = 'localhost';
const rpIdHash = sha256(Buffer.from(RP_ID, 'utf8'));
const flags = Buffer.from([0x05]);
const signCount = Buffer.from([0x00, 0x00, 0x00, 0x01]);
const authenticatorData = Buffer.concat([rpIdHash, flags, signCount]); // 37 bytes

// --- Build clientDataJSON ---
// We pick a fake "challenge": this is what the wallet would set to the hash of
// the message being signed, base64url-encoded. Here we just embed an arbitrary
// 32-byte buffer so the test data is realistic.
// 32-byte challenge = full TVM cell hash. With the two-phase flow used in
// b64url-fast.test.tolk we check only the first 96 bits pre-ACCEPT (≈ 5.1k
// gas), ACCEPT_MESSAGE, then verify the remaining 160 bits post-ACCEPT.
// Use the 12-byte form below for the single-phase 9894-gas variant.
const challengeBytes = Buffer.from(
  '4a4b4c4d4e4f50515253545556575859505152535455565758595a5b5c5d5e5f',
  'hex',
);
// const challengeBytes = Buffer.from('4a4b4c4d4e4f505152535455', 'hex');
const challengeB64u = challengeBytes
  .toString('base64')
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const clientData = {
  type: 'webauthn.get',
  challenge: challengeB64u,
  origin: 'http://localhost:52261',
  crossOrigin: false,
};
const clientDataJSON = Buffer.from(JSON.stringify(clientData), 'utf8');

// --- Sign ---
const cdjHash = sha256(clientDataJSON);
const signedMessage = Buffer.concat([authenticatorData, cdjHash]);
const digest = sha256(signedMessage);

// Node sign('sha256', msg, privKey) hashes msg internally and signs the digest
// with ECDSA, returning DER. To exactly match TVM P256_CHKSIGNS semantics we
// pass the *unhashed* signedMessage to Node and let it hash once.
const sigDer = nodeSign('sha256', signedMessage, privateKey);
const sigRaw = derToRawRS(sigDer);

// --- Print Tolk-ready constants ---
const out = (name, buf) => console.log(`${name} = "${buf.toString('hex')}"  // ${buf.length} bytes`);

console.log('// === P-256 / ES256 WebAuthn test vector ===');
out('rpIdHash         ', rpIdHash);
out('authenticatorData', authenticatorData);
console.log(`clientDataJSON_str = ${JSON.stringify(clientData)}`);
out('clientDataJSON   ', clientDataJSON);
out('clientDataJSONHash', cdjHash);
out('signedMessage    ', signedMessage);
out('digest           ', digest);
out('signature_raw    ', sigRaw);
out('pubkey_uncompr   ', uncompressed);
out('pubkey_compressed', compressed);
console.log('// pubkey_compressed is the 33-byte SEC1 encoding TVM P256_CHKSIGN* expects.');

// --- Split clientDataJSON into the 3-slice layout the contract expects ---
//   prefix         = `{"type":"webauthn.get","challenge":"`
//   challengeB64u  = base64url(challenge)         (43 chars for a 32-byte hash, no padding)
//   suffix         = `","origin":"<origin>","crossOrigin":false}`
// The contract receives these as 3 refs; HASHEXT_SHA256 over the 3 slices reproduces
// sha256(clientDataJSON), so the contract never has to copy/buffer the JSON itself.
const cdjStr = clientDataJSON.toString('utf8');
const challengeMarker = '"challenge":"';
const cm = cdjStr.indexOf(challengeMarker);
if (cm < 0) throw new Error('challenge field not found in clientDataJSON');
const cmEnd = cm + challengeMarker.length;
const challengeEnd = cdjStr.indexOf('"', cmEnd);
const prefixStr   = cdjStr.slice(0, cmEnd);            // up to and including the opening quote of the value
const challengeIn = cdjStr.slice(cmEnd, challengeEnd); // the b64url value, no quotes
const suffixStr   = cdjStr.slice(challengeEnd);        // closing quote and onward

if (challengeIn !== challengeB64u) throw new Error('challenge mismatch');
if (prefixStr.length + challengeIn.length + suffixStr.length !== clientDataJSON.length) {
  throw new Error('split lengths do not sum to clientDataJSON length');
}

const prefixBuf    = Buffer.from(prefixStr, 'utf8');
const challengeBuf = Buffer.from(challengeIn, 'utf8');
const suffixBuf    = Buffer.from(suffixStr, 'utf8');

console.log('// 3-slice clientDataJSON layout (each fits in one TVM cell, ≤127 bytes):');
out('cdj_prefix      ', prefixBuf);
out('cdj_challengeB64u', challengeBuf);
out('cdj_suffix      ', suffixBuf);
console.log(`// challenge as plain hex (32 bytes, the value the wallet wants to bind to a body cell):`);
out('challenge_bytes ', challengeBytes);

