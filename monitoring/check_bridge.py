"""
Monitor ETHFI NTT bridge activity across Ethereum, Arbitrum, Base, and Scroll.
Checks for:
  1. TransferSent / TransferRedeemed events in the last 30 minutes
  2. InboundTransferQueued / OutboundTransferQueued events (all-time, then validates on-chain)
"""

import os
import sys
import time
import json
import requests
from datetime import datetime, timezone, timedelta
from dotenv import load_dotenv
from web3 import Web3

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

LOOKBACK_MINUTES = 30

CHAINS = {
    "Ethereum": {
        "chain_id": 1,
        "wormhole_id": 2,
        "rpc": "https://eth-mainnet.g.alchemy.com/v2/{key}",
        "ntt_manager": "0x344169Cc4abE9459e77bD99D13AA8589b55b6174",
        "transceiver": "0x3bf4AebcaD920447c5fdD6529239Ab3922ce2186",
        "ethfi": "0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB",
    },
    "Arbitrum": {
        "chain_id": 42161,
        "wormhole_id": 23,
        "rpc": "https://arb-mainnet.g.alchemy.com/v2/{key}",
        "ntt_manager": "0x90A82462258F79780498151EF6f663f1D4BE4E3b",
        "transceiver": "0x4386e36B96D437b0F1C04A35E572C10C6627d88a",
        "ethfi": "0x7189fb5B6504bbfF6a852B13B7B82a3c118fDc27",
    },
    "Base": {
        "chain_id": 8453,
        "wormhole_id": 30,
        "rpc": "https://base-mainnet.g.alchemy.com/v2/{key}",
        "ntt_manager": "0xE87797A1aFb329216811dfA22C87380128CA17d8",
        "transceiver": "0x2153bEa70D96cd804aCbC89D82Ab36638fc1A5F4",
        "ethfi": "0x6C240DDA6b5c336DF09A4D011139beAAa1eA2Aa2",
    },
    "Scroll": {
        "chain_id": 534352,
        "wormhole_id": 34,
        "rpc": "https://scroll-mainnet.g.alchemy.com/v2/{key}",
        "ntt_manager": "0x552c09b224ec9146442767C0092C2928b61f62A1",
        "transceiver": "0xdd5567a62600709282d5ad35381505230e149B1a",
        "ethfi": "0x056A5FA5da84ceb7f93d36e545C5905607D8bD81",
    },
}

# keccak256 event signatures
EVENT_TRANSFER_SENT = "0x" + Web3.keccak(
    text="TransferSent(bytes32,bytes32,uint256,uint256,uint16,uint64)"
).hex()
EVENT_TRANSFER_REDEEMED = "0x" + Web3.keccak(
    text="TransferRedeemed(bytes32)"
).hex()
EVENT_INBOUND_QUEUED = "0x" + Web3.keccak(
    text="InboundTransferQueued(bytes32)"
).hex()
EVENT_OUTBOUND_QUEUED = "0x" + Web3.keccak(
    text="OutboundTransferQueued(uint64)"
).hex()

NTT_MANAGER_ABI = json.loads("""[
    {
        "inputs": [{"internalType":"bytes32","name":"digest","type":"bytes32"}],
        "name": "getInboundQueuedTransfer",
        "outputs": [
            {"components": [
                {"internalType":"TrimmedAmount","name":"amount","type":"uint72"},
                {"internalType":"uint64","name":"txTimestamp","type":"uint64"},
                {"internalType":"address","name":"recipient","type":"address"}
            ],
            "internalType":"struct IRateLimiter.InboundQueuedTransfer","name":"","type":"tuple"}
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [{"internalType":"uint64","name":"queueSequence","type":"uint64"}],
        "name": "getOutboundQueuedTransfer",
        "outputs": [
            {"components": [
                {"internalType":"bytes32","name":"recipient","type":"bytes32"},
                {"internalType":"bytes32","name":"refundAddress","type":"bytes32"},
                {"internalType":"TrimmedAmount","name":"amount","type":"uint72"},
                {"internalType":"uint64","name":"txTimestamp","type":"uint64"},
                {"internalType":"uint16","name":"recipientChain","type":"uint16"},
                {"internalType":"address","name":"sender","type":"address"},
                {"internalType":"bytes","name":"transceiverInstructions","type":"bytes"}
            ],
            "internalType":"struct IRateLimiter.OutboundQueuedTransfer","name":"","type":"tuple"}
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "getCurrentOutboundCapacity",
        "outputs": [{"internalType":"uint256","name":"","type":"uint256"}],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [{"internalType":"uint16","name":"chainId","type":"uint16"}],
        "name": "getCurrentInboundCapacity",
        "outputs": [{"internalType":"uint256","name":"","type":"uint256"}],
        "stateMutability": "view",
        "type": "function"
    }
]""")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def get_w3(chain_cfg: dict, api_key: str) -> Web3:
    url = chain_cfg["rpc"].format(key=api_key)
    return Web3(Web3.HTTPProvider(url))


def estimate_block_at(w3: Web3, target_ts: int) -> int:
    """Binary-search for the block closest to `target_ts`."""
    latest = w3.eth.block_number
    lo, hi = max(1, latest - 500_000), latest

    while lo < hi:
        mid = (lo + hi) // 2
        block_ts = w3.eth.get_block(mid)["timestamp"]
        if block_ts < target_ts:
            lo = mid + 1
        else:
            hi = mid
    return lo


def fetch_logs(w3: Web3, address: str, topics: list, from_block: int, to_block: int) -> list:
    """Fetch logs, chunking if the range is too large."""
    chunk = 50_000
    all_logs = []
    start = from_block
    while start <= to_block:
        end = min(start + chunk - 1, to_block)
        try:
            logs = w3.eth.get_logs({
                "address": Web3.to_checksum_address(address),
                "topics": topics,
                "fromBlock": start,
                "toBlock": end,
            })
            all_logs.extend(logs)
        except Exception as e:
            if chunk > 2_000:
                chunk = chunk // 2
                continue
            raise
        start = end + 1
    return all_logs


def format_ts(ts: int) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


# ---------------------------------------------------------------------------
# Check recent transfer events
# ---------------------------------------------------------------------------

def check_recent_transfers(w3: Web3, chain_name: str, cfg: dict, from_block: int, to_block: int):
    manager = cfg["ntt_manager"]

    sent_logs = fetch_logs(w3, manager, [EVENT_TRANSFER_SENT], from_block, to_block)
    redeemed_logs = fetch_logs(w3, manager, [EVENT_TRANSFER_REDEEMED], from_block, to_block)

    print(f"\n  TransferSent events:     {len(sent_logs)}")
    for log in sent_logs:
        block = w3.eth.get_block(log["blockNumber"])
        tx_hash = log["transactionHash"].hex()
        print(f"    - block {log['blockNumber']}  |  {format_ts(block['timestamp'])}  |  tx {tx_hash}")

    print(f"  TransferRedeemed events: {len(redeemed_logs)}")
    for log in redeemed_logs:
        block = w3.eth.get_block(log["blockNumber"])
        tx_hash = log["transactionHash"].hex()
        digest = log["topics"][1].hex() if len(log["topics"]) > 1 else "n/a"
        print(f"    - block {log['blockNumber']}  |  {format_ts(block['timestamp'])}  |  digest {digest[:18]}...  |  tx {tx_hash}")


# ---------------------------------------------------------------------------
# Check queued transfers
# ---------------------------------------------------------------------------

def check_queued_transfers(w3: Web3, chain_name: str, cfg: dict):
    manager_addr = cfg["ntt_manager"]
    manager = w3.eth.contract(
        address=Web3.to_checksum_address(manager_addr),
        abi=NTT_MANAGER_ABI,
    )

    latest_block = w3.eth.block_number
    # Scan a generous window for queue events (last ~7 days of blocks)
    scan_blocks = 500_000
    from_block = max(1, latest_block - scan_blocks)

    inbound_logs = fetch_logs(w3, manager_addr, [EVENT_INBOUND_QUEUED], from_block, latest_block)
    outbound_logs = fetch_logs(w3, manager_addr, [EVENT_OUTBOUND_QUEUED], from_block, latest_block)

    active_inbound = []
    for log in inbound_logs:
        digest = log["topics"][1] if len(log["topics"]) > 1 else log["data"][:32]
        try:
            result = manager.functions.getInboundQueuedTransfer(digest).call()
            if result[1] > 0:  # txTimestamp != 0 means still queued
                active_inbound.append({
                    "digest": digest.hex() if isinstance(digest, bytes) else digest,
                    "recipient": result[2],
                    "timestamp": result[1],
                    "tx_hash": log["transactionHash"].hex(),
                })
        except Exception:
            pass

    active_outbound = []
    for log in outbound_logs:
        raw = log["data"] if isinstance(log["data"], bytes) else bytes.fromhex(log["data"].replace("0x", ""))
        seq = int.from_bytes(raw[-8:], "big") if len(raw) >= 8 else int.from_bytes(raw, "big")
        try:
            result = manager.functions.getOutboundQueuedTransfer(seq).call()
            if result[3] > 0:  # txTimestamp != 0 means still queued
                active_outbound.append({
                    "sequence": seq,
                    "sender": result[5],
                    "recipient_chain": result[4],
                    "timestamp": result[3],
                    "tx_hash": log["transactionHash"].hex(),
                })
        except Exception:
            pass

    print(f"\n  Active inbound queued:   {len(active_inbound)}")
    for q in active_inbound:
        print(f"    - digest {q['digest'][:18]}...  |  recipient {q['recipient']}  |  queued {format_ts(q['timestamp'])}  |  tx {q['tx_hash']}")

    print(f"  Active outbound queued:  {len(active_outbound)}")
    for q in active_outbound:
        print(f"    - seq {q['sequence']}  |  sender {q['sender']}  |  dest chain {q['recipient_chain']}  |  queued {format_ts(q['timestamp'])}  |  tx {q['tx_hash']}")


# ---------------------------------------------------------------------------
# Rate limit capacity
# ---------------------------------------------------------------------------

def check_capacity(w3: Web3, chain_name: str, cfg: dict):
    manager = w3.eth.contract(
        address=Web3.to_checksum_address(cfg["ntt_manager"]),
        abi=NTT_MANAGER_ABI,
    )

    outbound_cap = manager.functions.getCurrentOutboundCapacity().call()
    print(f"\n  Outbound capacity:       {Web3.from_wei(outbound_cap, 'ether')} ETHFI")

    peer_chains = {name: c for name, c in CHAINS.items() if name != chain_name}
    for peer_name, peer_cfg in peer_chains.items():
        try:
            inbound_cap = manager.functions.getCurrentInboundCapacity(peer_cfg["wormhole_id"]).call()
            print(f"  Inbound from {peer_name:10s}:  {Web3.from_wei(inbound_cap, 'ether')} ETHFI")
        except Exception:
            print(f"  Inbound from {peer_name:10s}:  n/a (peer not configured)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    env_path = os.path.join(os.path.dirname(__file__), "..", "..", ".env")
    load_dotenv(dotenv_path=env_path)

    api_key = os.environ.get("ALCHEMY_API_KEY")
    if not api_key:
        print("ERROR: ALCHEMY_API_KEY not found in .env")
        sys.exit(1)

    now = int(time.time())
    cutoff = now - (LOOKBACK_MINUTES * 60)

    print("=" * 70)
    print(f"  ETHFI NTT Bridge Monitor")
    print(f"  Checking last {LOOKBACK_MINUTES} minutes  ({format_ts(cutoff)} → {format_ts(now)})")
    print("=" * 70)

    for chain_name, cfg in CHAINS.items():
        print(f"\n{'─' * 70}")
        print(f"  {chain_name}  (chain {cfg['chain_id']}, wormhole {cfg['wormhole_id']})")
        print(f"  NttManager: {cfg['ntt_manager']}")
        print(f"{'─' * 70}")

        try:
            w3 = get_w3(cfg, api_key)
            if not w3.is_connected():
                print(f"  ⚠ Could not connect to {chain_name} RPC — skipping")
                continue

            latest_block = w3.eth.block_number
            from_block = estimate_block_at(w3, cutoff)
            print(f"  Block range: {from_block} → {latest_block}")

            check_recent_transfers(w3, chain_name, cfg, from_block, latest_block)
            check_queued_transfers(w3, chain_name, cfg)
            check_capacity(w3, chain_name, cfg)

        except Exception as e:
            print(f"  ERROR on {chain_name}: {e}")

    print(f"\n{'=' * 70}")
    print("  Done.")
    print(f"{'=' * 70}")


if __name__ == "__main__":
    main()
