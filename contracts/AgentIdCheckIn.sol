// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal read interface for an ERC-721 style registry that tracks
///         Agent ID ownership. Only `balanceOf` is needed for the access gate.
/// @dev The Agent ID registry on BNB Smart Chain mainnet is deployed at
///      0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F (SPACE ID). An address holds
///      an Agent ID if and only if `balanceOf(address) > 0` in that registry.
interface IAgentIdRegistry {
    /// @notice Returns how many Agent ID tokens `account` holds.
    function balanceOf(address account) external view returns (uint256);
}

/// @title AgentIdCheckIn — daily check-in and guestbook for Agent ID holders
/// @notice A permissionless daily check-in contract gated by Agent ID
///         ownership. Any address that holds an Agent ID (a `.ai` name issued
///         through the registry given at deployment) may check in once per
///         UTC day, build a consecutive-day streak, and leave a short
///         guestbook message.
/// @dev Design and permissions — read this before deploying:
///
///      - There is NO owner and there are NO admin functions. Nobody can
///        pause, upgrade, edit, or delete check-ins or messages after
///        deployment, including the deployer.
///      - There are NO payable functions and the contract never holds funds.
///      - There is NO upgradeability: no proxy, no delegatecall, no
///        self-destruct. The deployed bytecode is final.
///      - The only external call is the `balanceOf` view on the Agent ID
///        registry, whose address is fixed as an `immutable` at deployment.
///      - The contract records activity only. It issues no token, pays no
///        rewards, and makes no promise of any return.
contract AgentIdCheckIn {
    /// @notice Maximum guestbook message length, in bytes.
    uint256 public constant MAX_MESSAGE_LENGTH = 280;

    /// @notice The Agent ID registry used for the access gate.
    /// @dev On BNB Smart Chain mainnet this is the SPACE ID registry at
    ///      0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F.
    IAgentIdRegistry public immutable registry;

    /// @notice Total number of counted check-ins across all agents.
    uint256 public totalCheckIns;

    /// @notice Number of distinct addresses that have ever checked in.
    uint256 public uniqueAgents;

    /// @notice Per-agent check-in statistics and guestbook entry.
    /// @param lastCheckInDay UTC day number (block.timestamp / 1 days) of the
    ///        most recent counted check-in; 0 means the agent never checked in.
    /// @param currentStreak Consecutive-day streak ending at `lastCheckInDay`.
    /// @param bestStreak Longest streak the agent has ever reached.
    /// @param totalCheckIns Total counted check-ins by this agent.
    /// @param message The agent's latest guestbook message.
    struct AgentStats {
        uint256 lastCheckInDay;
        uint256 currentStreak;
        uint256 bestStreak;
        uint256 totalCheckIns;
        string message;
    }

    mapping(address => AgentStats) private _agents;

    /// @notice Emitted when an agent's daily check-in is counted.
    /// @param agent The checking-in address.
    /// @param day The UTC day number of the check-in.
    /// @param streak The agent's streak after this check-in.
    /// @param message The guestbook message left with this check-in.
    event CheckedIn(address indexed agent, uint256 day, uint256 streak, string message);

    /// @notice Emitted when an agent updates its guestbook message without a
    ///         new counted check-in (i.e. a repeat call on the same UTC day).
    /// @param agent The address updating its message.
    /// @param day The UTC day number of the update.
    /// @param message The new guestbook message.
    event MessageUpdated(address indexed agent, uint256 day, string message);

    /// @notice Thrown when a caller that holds no Agent ID tries to check in.
    error NotAgentIdHolder(address caller);

    /// @notice Thrown when a guestbook message exceeds the length cap.
    error MessageTooLong(uint256 length);

    /// @param registry_ Address of the Agent ID registry contract. On BNB
    ///        Smart Chain mainnet: 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F.
    constructor(address registry_) {
        require(registry_ != address(0), "registry is zero address");
        registry = IAgentIdRegistry(registry_);
    }

    /// @notice Check in for today and leave a guestbook message.
    /// @dev Reverts unless the caller holds an Agent ID. The first call on a
    ///      new UTC day counts as that day's check-in: it extends the streak
    ///      if the previous counted check-in was yesterday, restarts it at 1
    ///      if a day (or more) was missed, and updates all counters. A repeat
    ///      call on the same UTC day only replaces the guestbook message and
    ///      emits `MessageUpdated`; counters and streak are untouched, so a
    ///      day can never be counted twice.
    /// @param message Guestbook message, at most 280 bytes. May be empty.
    function checkIn(string calldata message) external {
        if (registry.balanceOf(msg.sender) == 0) {
            revert NotAgentIdHolder(msg.sender);
        }
        if (bytes(message).length > MAX_MESSAGE_LENGTH) {
            revert MessageTooLong(bytes(message).length);
        }

        uint256 today = block.timestamp / 1 days;
        AgentStats storage stats = _agents[msg.sender];

        if (stats.lastCheckInDay == today) {
            // Same-day repeat: guestbook update only, no double counting.
            stats.message = message;
            emit MessageUpdated(msg.sender, today, message);
            return;
        }

        if (stats.totalCheckIns == 0) {
            // First ever check-in from this address.
            uniqueAgents += 1;
        }

        if (stats.lastCheckInDay == today - 1) {
            stats.currentStreak += 1;
        } else {
            stats.currentStreak = 1;
        }
        if (stats.currentStreak > stats.bestStreak) {
            stats.bestStreak = stats.currentStreak;
        }

        stats.lastCheckInDay = today;
        stats.totalCheckIns += 1;
        stats.message = message;
        totalCheckIns += 1;

        emit CheckedIn(msg.sender, today, stats.currentStreak, message);
    }

    /// @notice Read an agent's check-in statistics and guestbook message.
    /// @param agent The address to look up.
    /// @return lastCheckInDay UTC day number of the last counted check-in
    ///         (0 if the agent has never checked in).
    /// @return currentStreak Current consecutive-day streak. Note: this is
    ///         the streak as of the last check-in; if the agent has not
    ///         checked in today or yesterday, the live streak has lapsed even
    ///         though the stored value is unchanged.
    /// @return bestStreak Longest streak ever reached.
    /// @return totalCheckIns_ Total counted check-ins by this agent.
    /// @return message The agent's latest guestbook message.
    function getAgent(address agent)
        external
        view
        returns (
            uint256 lastCheckInDay,
            uint256 currentStreak,
            uint256 bestStreak,
            uint256 totalCheckIns_,
            string memory message
        )
    {
        AgentStats storage stats = _agents[agent];
        return (
            stats.lastCheckInDay,
            stats.currentStreak,
            stats.bestStreak,
            stats.totalCheckIns,
            stats.message
        );
    }

    /// @notice Check whether an address currently holds an Agent ID and is
    ///         therefore allowed to check in.
    /// @param account The address to test.
    /// @return True if the registry reports a balance greater than zero.
    function isAgentIdHolder(address account) external view returns (bool) {
        return registry.balanceOf(account) > 0;
    }
}
