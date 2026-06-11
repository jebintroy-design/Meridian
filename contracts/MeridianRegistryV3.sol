// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MeridianRegistry v3
/// @notice Meridian — free-to-play memory match on Base.
///         v3 adds onchain game starts: startGame opens a session for the
///         player, submitScore closes it. Because both are transactions,
///         the claimed run time can never exceed the wall-clock time
///         between them, which hardens the anti-cheat bounds.
/// @dev    Moves are still client-reported (same trust model as before).
///         BREAKING vs v2: submitScore no longer takes gridSize — it is
///         read from the open session.
contract MeridianRegistry {
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
    /// player => currently open session (one at a time; restart overwrites)
    mapping(address => Session) public sessions;

    uint256 public totalStarts;
    uint256 public totalGames;

    event GameStarted(address indexed player, uint8 indexed gridSize, uint64 startedAt);
    event ScoreSubmitted(
        address indexed player,
        uint8 indexed gridSize,
        uint16 moves,
        uint32 timeMs,
        bool newBest
    );

    /// @notice Opens a session. Starting again before submitting simply
    ///         replaces the old session (abandoned boards cost nothing extra).
    function startGame(uint8 gridSize) external {
        require(gridSize == 2 || gridSize == 4 || gridSize == 6, "grid must be 2, 4 or 6");
        uint64 nowTs = uint64(block.timestamp);
        sessions[msg.sender] = Session(gridSize, nowTs);
        totalStarts += 1;
        emit GameStarted(msg.sender, gridSize, nowTs);
    }

    /// @notice Closes the open session with the result of the run.
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
        // Claimed play time can't exceed real time since startGame
        // (+15s slack for block timestamp granularity).
        require(uint256(timeMs) <= (block.timestamp - s.startedAt + 15) * 1000, "time exceeds session");

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

    /// @notice Convenience reader with named returns for frontends.
    function getBest(address player, uint8 gridSize)
        external
        view
        returns (uint16 moves, uint32 timeMs, uint32 plays, uint64 lastPlayed)
    {
        Best memory b = bests[player][gridSize];
        return (b.moves, b.timeMs, b.plays, b.lastPlayed);
    }

    /// @notice Reads the player's open session (startedAt == 0 means none).
    function getSession(address player)
        external
        view
        returns (uint8 gridSize, uint64 startedAt)
    {
        Session memory s = sessions[player];
        return (s.gridSize, s.startedAt);
    }
}
