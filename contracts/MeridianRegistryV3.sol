// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MeridianRegistryV3
/// @notice Meridian — free-to-play memory match on Base. v3 brackets every run
///         with an onchain game start: startGame opens a session, submitScore
///         closes it, so the claimed run time can be checked against the real
///         wall-clock time between the two transactions.
/// @dev    Scores are still client-reported (same trust model as dinobase);
///         sanity bounds plus the session time ceiling reject impossible runs.
contract MeridianRegistryV3 {
    struct Best {
        uint16 moves;      // fewest moves on record (1 move = 1 pair attempt)
        uint32 timeMs;     // elapsed time of that best run, milliseconds
        uint32 plays;      // completed runs at this grid size
        uint64 lastPlayed; // block timestamp of most recent submission
    }

    struct Session {
        uint8 gridSize;    // 2, 4 or 6
        uint64 startedAt;  // block timestamp of startGame; 0 = no open session
    }

    /// player => gridSize (2, 4 or 6) => best record
    mapping(address => mapping(uint8 => Best)) public bests;

    /// player => open session (overwritten by startGame, cleared by submitScore)
    mapping(address => Session) public sessions;

    uint256 public totalGames;
    uint256 public totalStarts;

    event GameStarted(address indexed player, uint8 indexed gridSize);

    event ScoreSubmitted(
        address indexed player,
        uint8 indexed gridSize,
        uint16 moves,
        uint32 timeMs,
        bool newBest
    );

    /// @notice Open a session for a run. Restarting just overwrites the session.
    /// @param gridSize 2 (2 pairs), 4 (8 pairs) or 6 (18 pairs)
    function startGame(uint8 gridSize) external {
        require(gridSize == 2 || gridSize == 4 || gridSize == 6, "grid must be 2, 4 or 6");

        sessions[msg.sender] = Session(gridSize, uint64(block.timestamp));
        totalStarts += 1;

        emit GameStarted(msg.sender, gridSize);
    }

    /// @notice Close the open session with a completed run. Grid size comes
    ///         from the session, not the caller.
    /// @param moves  pair attempts taken to clear the board
    /// @param timeMs elapsed milliseconds from first flip to last match
    function submitScore(uint16 moves, uint32 timeMs) external {
        Session memory s = sessions[msg.sender];
        require(s.startedAt != 0, "no open session");

        uint8 gridSize = s.gridSize;
        uint16 pairs = (uint16(gridSize) * uint16(gridSize)) / 2;

        // A perfect game needs at least one move per pair.
        require(moves >= pairs, "impossible move count");
        // ~400ms per pair is faster than any human can flip and read.
        require(timeMs >= uint32(pairs) * 400, "impossible time");
        // Runs longer than an hour are noise, not gameplay.
        require(timeMs <= 3_600_000, "run too long");
        // Claimed run time can't exceed real time since startGame (+15s slack).
        require(uint256(timeMs) <= (block.timestamp - s.startedAt + 15) * 1000, "time exceeds wall clock");

        delete sessions[msg.sender];

        Best storage b = bests[msg.sender][gridSize];

        bool newBest = b.plays == 0
            || moves < b.moves
            || (moves == b.moves && timeMs < b.timeMs);

        if (newBest) {
            b.moves = moves;
            b.timeMs = timeMs;
        }
        b.plays += 1;
        b.lastPlayed = uint64(block.timestamp);
        totalGames += 1;

        emit ScoreSubmitted(msg.sender, gridSize, moves, timeMs, newBest);
    }

    /// @notice Read a player's open session (startedAt is 0 if none).
    function getSession(address player)
        external
        view
        returns (uint8 gridSize, uint64 startedAt)
    {
        Session memory s = sessions[player];
        return (s.gridSize, s.startedAt);
    }

    /// @notice Convenience reader with named returns for frontends.
    function getBest(address player, uint8 gridSize)
        external
        view
        returns (uint16 moves, uint32 timeMs, uint32 plays, uint64 lastPlayed)
    {
        Best memory b = bests[player][gridSize];
        return (b.moves, b.timeMs, b.plays, b.lastPlayed);
    }
}
