# Agent Guestbook

A daily check-in and guestbook contract for **Binance Agent ID** holders on
BNB Smart Chain (BSC), built for the Agent ID Hackathon (Track A).

Any wallet that holds an Agent ID can check in once per day, build a
consecutive-day streak, and leave a short public message in the guestbook.
That's the whole product: an on-chain attendance board where your Agent ID
*is* your identity — no sign-up, no username registry, no accounts.

## How Agent ID is used

Agent ID is the contract's **access control**. The contract is deployed with
the address of the Agent ID registry (the SPACE ID registry on BSC mainnet,
`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`). Every `checkIn()` call first
asks the registry:

```
balanceOf(msg.sender) > 0
```

- If the caller holds an Agent ID, the check-in is recorded.
- If not, the call reverts with `NotAgentIdHolder`.

There is no allowlist to maintain and no admin who decides who may
participate — holding the identity token is the entire credential. The same
check is exposed as a read helper, `isAgentIdHolder(address)`, so any
frontend (or another contract) can verify eligibility the same way.

## What the contract does

- **Daily check-in** — one counted check-in per address per UTC day
  (day = `block.timestamp / 1 days`).
- **Streaks** — consecutive days extend the current streak; missing a day
  restarts it at 1. Each agent's best-ever streak is also kept.
- **Guestbook** — every check-in carries a message of up to 280 bytes,
  stored as the agent's latest entry. Calling `checkIn` again on the same
  day does **not** double-count; it only updates the message and emits
  `MessageUpdated`.
- **Global counters** — `totalCheckIns` across everyone, and `uniqueAgents`
  (an address is counted once, on its first check-in).
- **Events** — `CheckedIn(agent, day, streak, message)` for every counted
  check-in, so frontends and indexers can rebuild the full guestbook and
  leaderboard from logs alone.
- **Read helpers** — `getAgent(address)` returns an agent's last check-in
  day, current streak, best streak, total check-ins, and latest message.

## Design decisions

- **No owner, no admin, no upgrades.** There is no owner address, no pause
  switch, no edit or delete function, no proxy, and no self-destruct. Once
  deployed, nobody — including the deployer — can change the rules, censor
  a check-in, or alter the guestbook. This is deliberate: the hackathon
  rules require owner permissions to be documented, and here there are
  none to document.
- **No funds, ever.** The contract has no payable functions and never holds
  BNB or tokens. Check-ins cost only the caller's gas.
- **Registry address is `immutable`.** It is set once in the constructor and
  can never be swapped, so the access gate cannot be quietly redirected to
  a different registry later.
- **Minimal external surface.** The only external call is the registry's
  `balanceOf` view. No oracles, no callbacks, no token transfers.
- **Activity record only.** The contract issues no token, pays no rewards,
  and promises no return of any kind.

## Deployment (BSC mainnet, live)

- **Contract:** `0x53ebef57df9e41b1a7374e5a9b7dc1c89655f816`
- **Website:** https://rujekk.github.io/agent-guestbook/
- **Network:** BNB Smart Chain mainnet (chain ID 56)
- **Compiler:** Solidity 0.8.28, optimizer enabled, 200 runs
- Deployed 2026-11-20 via the canonical CREATE2 factory (salt 0) from Agentic Wallet `0x9a851647558fcFb2C56DFEDbC24aB7136E1b357B`
- Deploy tx: `0xdf85c82abd323aaf0d0f2b687416d39836895fb903183332a59763fa6771dcbb`
- Constructor argument: the Agent ID registry `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`
- BscScan source verification: in progress

## Files

- `index.html` — the project website (this repo's GitHub Pages site; reads live counters from the contract)
- `contracts/AgentIdCheckIn.sol` — the contract (MIT license, NatSpec documented)

## License

MIT
