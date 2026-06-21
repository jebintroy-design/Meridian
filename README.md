# Meridian

Free onchain memory match on Base mainnet. Flip tiles, find pairs, submit your best run. Fewer moves wins, time breaks ties. Scores are client-reported (same trust model as dinobase); the contract enforces sanity bounds and keeps your best per grid size.

Tagline: **Flip less. Match more.**

## Live deployment (v3)

- Contract: [`0x67404e40bb2c74aceff1b4338d31ee0b1972156c`](https://basescan.org/address/0x67404e40bb2c74aceff1b4338d31ee0b1972156c) on Base mainnet (chain 8453)
- Fresh address, fresh storage — v2 (single-tx submit) is deprecated and its scores stay on v2; nothing carries over.

## The two-transaction flow

Every onchain run is bracketed by two transactions:

1. **`startGame(uint8 gridSize)`** — boards are dealt face-down and locked; pressing **Start Game** sends this transaction. It opens a session recording the grid size and the start timestamp. The board stays locked until it confirms (~2s on Base); the run timer starts at the player's first flip after unlock. Without a connected wallet, Start just unlocks a free unrecorded run, no transaction.
2. **`submitScore(uint16 moves, uint32 timeMs)`** — sent on win. No grid size argument: the contract reads it from the session.

Why: the contract checks that the claimed `timeMs` doesn't exceed the real wall-clock time between the two transactions (plus 15s slack), so a submitted run time can't be shorter than the time the run actually took. Restarting before submitting just overwrites the session. Playing without a connected wallet works fine — no transactions, nothing recorded.

## Connecting

Two options, both ending in the same ethers `BrowserProvider`:

- **Base Wallet** — Base Account SDK (`@base-org/account` from CDN), passkey popup, works with no extension installed.
- **Browser wallet** — injected `window.ethereum` (MetaMask etc.), with automatic Base chain switch/add.

## What's in here

- `MeridianRegistryV3.sol` — v3 score registry: per-player sessions (`startGame`/`getSession`), best moves + time per grid size (2x2, 4x4, 6x6), total games and starts, `GameStarted`/`ScoreSubmitted` events for indexing.
- `index.html` — the whole game in one file. Split-flap board aesthetic, two connect paths, chain switch to Base, session flow and score submission via ethers v6 from CDN. No build step. `CONTRACT_ADDRESS` is wired to the v3 deployment.

## Grid sizes

All onchain, tracked separately per player: **2x2** (2 pairs), **4x4** (8 pairs), **6x6** (18 pairs).

## Hosting

Host `index.html` anywhere static, same as baseshooter.

## Builder attribution (ERC-8021)

Both onchain transactions (`startGame` and `submitScore`) carry Meridian's Base builder code as an ERC-8021 data suffix appended to the calldata, so the app earns onchain attribution in its base.dev dashboard. The suffix is the precomputed output of the `ox` library's `Attribution.toDataSuffix({ codes: ["bc_4ugk858d"] })` — a 29-byte tail (`…8021` marker + schema byte + length + the ASCII code) that the contract ignores and off-chain indexers read. It's appended manually via `signer.sendTransaction` so it applies identically through the injected wallet and the Base Account smart wallet; read calls carry no suffix. The Base Account SDK's own auto-attribution is left off to avoid a second, conflicting suffix. To verify, decode a tx's input data on Basescan and confirm it ends with the marker, or use the [builder code checker](https://builder-code-checker.vercel.app/).

## Smoke test before announcing

1. Connect via Base Wallet (no extension) and via a browser wallet — both should land on Base (8453) and show the address chip.
2. Deal a board, press Start Game, watch "Starting onchain…" resolve and the board unlock after the start tx confirms.
3. Clear and submit on each grid size; check both txs on Basescan and that BEST updates.
4. Submit a worse run, confirm BEST does not regress (`newBest` is false in the event).
5. Reject a start tx, confirm the board stays locked and "Try Again" re-sends it.
6. Clear a 2x2 in under 0.8s (possible!) and confirm the frontend hides submit with the floor message instead of letting the tx revert.

## Contract notes

- `startGame(uint8 gridSize)` reverts on grid sizes other than 2/4/6; restarting overwrites the open session.
- `submitScore(uint16 moves, uint32 timeMs)` reverts with no open session, move counts below the pair count, runs faster than ~400ms per pair (2x2 floor: 800ms), runs over an hour, or claimed time exceeding wall-clock time since `startGame` + 15s.
- `getSession(player)` returns `(gridSize, startedAt)`; `getBest(player, gridSize)` returns `(moves, timeMs, plays, lastPlayed)`.
- Leaderboard: index `ScoreSubmitted` events (player and gridSize are indexed); `GameStarted` lets you compute completion rates.

## Deploy / verify (Remix)

1. Open remix.ethereum.org, paste `MeridianRegistryV3.sol` in, compile with `0.8.24`+ (note the exact version and optimization setting — both are needed for verification).
2. Deploy & Run tab: Environment "Injected Provider", wallet on Base mainnet (8453), Deploy. No constructor arguments.
3. Verify on basescan.org: Solidity (Single file), exact compiler version, MIT license, matching optimization setting, paste the full source. Compiler version or optimization mismatch causes nearly every verification failure.
4. Update `CONTRACT_ADDRESS` at the top of the script in `index.html`.
