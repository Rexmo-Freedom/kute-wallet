#!/usr/bin/env python3
"""Generate known-answer vectors for the Dart Hyperliquid signing engine.

Run (any machine, no network needed):
    python3 -m venv /tmp/hlvec && /tmp/hlvec/bin/pip install hyperliquid-python-sdk
    /tmp/hlvec/bin/python test/services/fixtures/generate_hl_vectors.py \
        > test/services/fixtures/hl_vectors.json

The Dart tests (test/services/hyperliquid_*_test.dart) assert byte equality
against these vectors up to the EIP-712 digest. Signatures themselves are
validated by ecRecover, NOT byte equality: polybrainz's deterministic-k
differs from eth_account's RFC 6979, so r/s never match across the two —
both are valid signatures over the same digest.
"""

import json

import msgpack
from eth_account import Account
from eth_account.messages import encode_typed_data, _hash_eip191_message
from eth_utils import keccak
from hyperliquid.utils.signing import (
    action_hash,
    construct_phantom_agent,
    l1_payload,
    user_signed_payload,
    float_to_wire,
    order_request_to_order_wire,
    order_wires_to_order_action,
    WITHDRAW_SIGN_TYPES,
    USD_CLASS_TRANSFER_SIGN_TYPES,
)

# Inlined in the SDK's sign_approve_builder_fee — keep in sync.
APPROVE_BUILDER_FEE_SIGN_TYPES = [
    {"name": "hyperliquidChain", "type": "string"},
    {"name": "maxFeeRate", "type": "string"},
    {"name": "builder", "type": "address"},
    {"name": "nonce", "type": "uint64"},
]

KEY = "0x0123456789012345678901234567890101234567890123456789012345678901"
ACCT = Account.from_key(KEY)
VAULT = "0x1719884eb866cb12b2287399b15f7db5e7d775ea"
NONCE = 1677777606040


def typed_digest(payload):
    return _hash_eip191_message(encode_typed_data(full_message=payload)).hex()


def sign_digest(digest_hex):
    sig = ACCT.unsafe_sign_hash(bytes.fromhex(digest_hex))
    return {"r": hex(sig.r), "s": hex(sig.s), "v": sig.v}


out = {"signer": ACCT.address, "nonce": NONCE}

# ── msgpack scalars ────────────────────────────────────────────────────
out["msgpack"] = {
    "scalars": [
        {"value": None, "hex": msgpack.packb(None).hex()},
        {"value": True, "hex": msgpack.packb(True).hex()},
        {"value": False, "hex": msgpack.packb(False).hex()},
        {"value": 0, "hex": msgpack.packb(0).hex()},
        {"value": 127, "hex": msgpack.packb(127).hex()},
        {"value": 128, "hex": msgpack.packb(128).hex()},
        {"value": 255, "hex": msgpack.packb(255).hex()},
        {"value": 256, "hex": msgpack.packb(256).hex()},
        {"value": 65535, "hex": msgpack.packb(65535).hex()},
        {"value": 65536, "hex": msgpack.packb(65536).hex()},
        {"value": 4294967295, "hex": msgpack.packb(4294967295).hex()},
        {"value": 4294967296, "hex": msgpack.packb(4294967296).hex()},
        {"value": 1677777606040, "hex": msgpack.packb(1677777606040).hex()},
        {"value": -1, "hex": msgpack.packb(-1).hex()},
        {"value": -32, "hex": msgpack.packb(-32).hex()},
        {"value": -33, "hex": msgpack.packb(-33).hex()},
        {"value": -129, "hex": msgpack.packb(-129).hex()},
        {"value": -32769, "hex": msgpack.packb(-32769).hex()},
        {"value": "", "hex": msgpack.packb("").hex()},
        {"value": "Gtc", "hex": msgpack.packb("Gtc").hex()},
        {"value": "a" * 31, "hex": msgpack.packb("a" * 31).hex()},
        {"value": "a" * 32, "hex": msgpack.packb("a" * 32).hex()},
        {"value": "a" * 300, "hex": msgpack.packb("a" * 300).hex()},
    ],
}

# ── actions ────────────────────────────────────────────────────────────
order_gtc = order_wires_to_order_action(
    [
        order_request_to_order_wire(
            {
                "coin": "ETH",
                "is_buy": True,
                "sz": 0.0147,
                "limit_px": 1670.1,
                "reduce_only": False,
                "order_type": {"limit": {"tif": "Ioc"}},
                "cloid": None,
            },
            4,
        )
    ]
)
from hyperliquid.utils.types import Cloid

order_cloid = order_wires_to_order_action(
    [
        order_request_to_order_wire(
            {
                "coin": "ETH",
                "is_buy": True,
                "sz": 0.0147,
                "limit_px": 1670.1,
                "reduce_only": False,
                "order_type": {"limit": {"tif": "Ioc"}},
                "cloid": Cloid.from_str("0x00000000000000000000000000000001"),
            },
            4,
        )
    ]
)
order_builder = order_wires_to_order_action(
    [
        order_request_to_order_wire(
            {
                "coin": "ETH",
                "is_buy": True,
                "sz": 0.0147,
                "limit_px": 1670.1,
                "reduce_only": False,
                "order_type": {"limit": {"tif": "Ioc"}},
                "cloid": None,
            },
            4,
        )
    ],
    {"b": "0x8c967E73E6B15087c42A10D344cFf4c96D877f1D".lower(), "f": 10},
)
order_trigger = order_wires_to_order_action(
    [
        order_request_to_order_wire(
            {
                "coin": "ETH",
                "is_buy": False,
                "sz": 0.0147,
                "limit_px": 1670.1,
                "reduce_only": True,
                "order_type": {
                    "trigger": {
                        "isMarket": True,
                        "triggerPx": 1600.0,
                        "tpsl": "sl",
                    }
                },
                "cloid": None,
            },
            4,
        )
    ]
)
spot_order = order_wires_to_order_action(
    [
        order_request_to_order_wire(
            {
                "coin": "@8",
                "is_buy": True,
                "sz": 12.0,
                "limit_px": 172.21,
                "reduce_only": False,
                "order_type": {"limit": {"tif": "Gtc"}},
                "cloid": None,
            },
            10008,
        )
    ]
)
cancel = {"type": "cancel", "cancels": [{"a": 4, "o": 77738308}]}
cancel_cloid = {
    "type": "cancelByCloid",
    "cancels": [{"asset": 4, "cloid": "0x00000000000000000000000000000001"}],
}
update_leverage = {"type": "updateLeverage", "asset": 4, "isCross": True, "leverage": 5}


# setReferrer has no standalone builder in the SDK: Exchange.set_referrer
# builds the action inline and signs it. Run that exact method with the
# clock pinned to NONCE and the POST captured, so the vector is the SDK's
# own action and signature, with no network.
def sdk_set_referrer(code):
    from hyperliquid import exchange as hl_exchange
    from hyperliquid.utils.constants import MAINNET_API_URL

    captured = {}
    ex = hl_exchange.Exchange.__new__(hl_exchange.Exchange)
    ex.wallet = ACCT
    ex.base_url = MAINNET_API_URL
    ex.vault_address = None
    ex.expires_after = None
    ex._post_action = lambda action, signature, nonce: captured.update(
        action=action, signature=signature, nonce=nonce
    )
    clock = hl_exchange.get_timestamp_ms
    hl_exchange.get_timestamp_ms = lambda: NONCE
    try:
        ex.set_referrer(code)
    finally:
        hl_exchange.get_timestamp_ms = clock
    assert captured["nonce"] == NONCE
    return captured


set_referrer_call = sdk_set_referrer("KUTE")
set_referrer = set_referrer_call["action"]

actions = {
    "order_gtc": order_gtc,
    "order_cloid": order_cloid,
    "order_builder": order_builder,
    "order_trigger": order_trigger,
    "spot_order": spot_order,
    "cancel": cancel,
    "cancel_cloid": cancel_cloid,
    "update_leverage": update_leverage,
    "set_referrer": set_referrer,
}

out["l1Actions"] = []
for name, action in actions.items():
    for vault, expires, suffix in [
        (None, None, ""),
        (VAULT, None, "_vault"),
        (None, NONCE + 60_000, "_expires"),
    ]:
        if suffix and name != "order_gtc":
            continue  # vault/expires variants only needed once
        h = action_hash(action, vault, NONCE, expires)
        entry = {
            "name": name + suffix,
            "action": action,
            "vaultAddress": vault,
            "nonce": NONCE,
            "expiresAfter": expires,
            "msgpackHex": msgpack.packb(action).hex(),
            "connectionIdHex": h.hex(),
        }
        for is_mainnet, net in [(True, "mainnet"), (False, "testnet")]:
            payload = l1_payload(construct_phantom_agent(h, is_mainnet))
            d = typed_digest(payload)
            entry[f"digest_{net}"] = d
            entry[f"pythonSig_{net}"] = sign_digest(d)
        out["l1Actions"].append(entry)

# The SDK's own set_referrer signature is the one this generator computes
# for the same action (both RFC 6979), so the entry above is its output.
_set_referrer_entry = next(e for e in out["l1Actions"] if e["name"] == "set_referrer")
assert set_referrer_call["signature"] == _set_referrer_entry["pythonSig_mainnet"]

# ── user-signed actions ────────────────────────────────────────────────
def user_signed(name, action, sign_types, primary_type):
    payload = user_signed_payload(primary_type, sign_types, action)
    d = typed_digest(payload)
    return {
        "name": name,
        "action": action,
        "primaryType": primary_type,
        "digest": d,
        "pythonSig": sign_digest(d),
    }


out["userSignedActions"] = [
    user_signed(
        "withdraw3_mainnet",
        {
            "destination": "0x5e9ee1089755c3435139848e47e6635505d5a13a",
            "amount": "100.5",
            "time": NONCE,
            "type": "withdraw3",
            "signatureChainId": "0x66eee",
            "hyperliquidChain": "Mainnet",
        },
        WITHDRAW_SIGN_TYPES,
        "HyperliquidTransaction:Withdraw",
    ),
    user_signed(
        "withdraw3_testnet",
        {
            "destination": "0x5e9ee1089755c3435139848e47e6635505d5a13a",
            "amount": "100.5",
            "time": NONCE,
            "type": "withdraw3",
            "signatureChainId": "0x66eee",
            "hyperliquidChain": "Testnet",
        },
        WITHDRAW_SIGN_TYPES,
        "HyperliquidTransaction:Withdraw",
    ),
    user_signed(
        "usd_class_transfer",
        {
            "type": "usdClassTransfer",
            "amount": "55.75",
            "toPerp": False,
            "nonce": NONCE,
            "signatureChainId": "0x66eee",
            "hyperliquidChain": "Mainnet",
        },
        USD_CLASS_TRANSFER_SIGN_TYPES,
        "HyperliquidTransaction:UsdClassTransfer",
    ),
    user_signed(
        "approve_builder_fee",
        {
            "maxFeeRate": "0.01%",
            "builder": "0x8c967E73E6B15087c42A10D344cFf4c96D877f1D",
            "nonce": NONCE,
            "type": "approveBuilderFee",
            "signatureChainId": "0x66eee",
            "hyperliquidChain": "Mainnet",
        },
        APPROVE_BUILDER_FEE_SIGN_TYPES,
        "HyperliquidTransaction:ApproveBuilderFee",
    ),
]

# ── EIP-2612 permit (Arbitrum native USDC domain) ──────────────────────
permit_msg = {
    "owner": ACCT.address,
    "spender": "0x2Df1c51E09aECF9cacB7bc98cB1742757f163dF7",
    "value": 25_000_000,
    "nonce": 0,
    "deadline": 1719999999,
}
permit_payload = {
    "domain": {
        "name": "USD Coin",
        "version": "2",
        "chainId": 42161,
        "verifyingContract": "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
    },
    "types": {
        "EIP712Domain": [
            {"name": "name", "type": "string"},
            {"name": "version", "type": "string"},
            {"name": "chainId", "type": "uint256"},
            {"name": "verifyingContract", "type": "address"},
        ],
        "Permit": [
            {"name": "owner", "type": "address"},
            {"name": "spender", "type": "address"},
            {"name": "value", "type": "uint256"},
            {"name": "nonce", "type": "uint256"},
            {"name": "deadline", "type": "uint256"},
        ],
    },
    "primaryType": "Permit",
    "message": permit_msg,
}
out["permit"] = {
    "message": permit_msg,
    "digest": typed_digest(permit_payload),
    "pythonSig": sign_digest(typed_digest(permit_payload)),
}

# ── float_to_wire table ────────────────────────────────────────────────
out["floatToWire"] = [
    {"value": v, "wire": float_to_wire(v)}
    for v in [
        0.0, 1.0, 1670.1, 0.0147, 100.5, 55.75, 0.1, 123456.0, 99999.0,
        0.00000001, 12345678.0, 3.0, 2.5, 1e-8, 50000.0, 0.5, -0.0,
    ]
]

print(json.dumps(out, indent=1))
