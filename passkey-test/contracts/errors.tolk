// PasskeyWallet error codes (range 200..220 to avoid collisions with other contracts).

const ERROR_INVALID_SIGNATURE        = 200
const ERROR_CHALLENGE_BINDING_PRE    = 201   // pre-ACCEPT: 96-bit prefix mismatch (cheap rejection)
const ERROR_CHALLENGE_BINDING_FULL   = 202   // post-ACCEPT: full 256-bit mismatch (collision attempt)
const ERROR_INVALID_SEQNO            = 203
const ERROR_EXPIRED                  = 204
const ERROR_INVALID_BODY             = 205
