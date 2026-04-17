// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {LPVault} from "./LPVault.sol";
import {ReferralManager} from "./ReferralManager.sol";

/// @title Lottery
/// @notice On-chain lottery on Polygon, optimised for emerging-market scale.
///
///  Key features:
///    - $1 USDC tickets (raffle model — no number picking)
///    - Daily time-based draws via Chainlink Automation
///    - 8 prize tiers (1 grand + 7 secondary) for frequent small wins
///    - Win-share: 10% of each prize is sent to the winner's referral chain
///    - Fee split: 70% prize pool, 20% LP yield, 10% referrals
///    - Chainlink VRF v2.5 for provably fair randomness
contract Lottery is VRFConsumerBaseV2Plus, AutomationCompatibleInterface, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ──────────────────────────────────────────────
    //  Constants
    // ──────────────────────────────────────────────

    /// @notice Fee split basis points (out of 10000)
    uint256 public constant JACKPOT_BPS = 7000;   // 70% → prize pool
    uint256 public constant LP_BPS = 2000;         // 20% → LP vault
    uint256 public constant REFERRAL_BPS = 1000;   // 10% → referrals

    /// @notice Win-share: 10% of each prize goes to referral chain
    uint256 public constant WINSHARE_BPS = 1000;   // 10% of prize

    /// @notice 8 prize tiers. Index 0 = grand prize. BPS are out of 10000 (of the prize pool).
    ///         Grand:  40%  (1 winner)
    ///         Tier 1: 15%  (1 winner)
    ///         Tier 2: 10%  (1 winner)
    ///         Tier 3: 10%  (2 winners — each gets 5%)
    ///         Tier 4:  8%  (3 winners — each gets ~2.67%)
    ///         Tier 5:  7%  (5 winners — each gets 1.4%)
    ///         Tier 6:  5%  (8 winners — each gets 0.625%)
    ///         Tier 7:  5%  (13 winners — each gets ~0.385%)
    ///         Total:  100% distributed across 34 winners
    uint256 public constant NUM_TIERS = 8;
    uint256 public constant TOTAL_WINNERS = 34;

    /// @notice VRF needs one random word per winner
    uint32 public constant NUM_WORDS = 34;

    // ──────────────────────────────────────────────
    //  Immutables
    // ──────────────────────────────────────────────

    IERC20 public immutable usdc;
    LPVault public immutable lpVault;
    ReferralManager public immutable referralManager;

    // ──────────────────────────────────────────────
    //  VRF Configuration
    // ──────────────────────────────────────────────

    uint256 public s_subscriptionId;
    bytes32 public s_keyHash;
    uint32 public s_callbackGasLimit;
    uint16 public s_requestConfirmations;

    // ──────────────────────────────────────────────
    //  Prize Tier Configuration
    // ──────────────────────────────────────────────

    struct TierConfig {
        uint256 poolBps;       // % of prize pool allocated to this tier (out of 10000)
        uint256 winnerCount;   // Number of winners in this tier
    }

    /// @notice Tier configurations (set in constructor, immutable-ish via storage)
    TierConfig[NUM_TIERS] public tiers;

    // ──────────────────────────────────────────────
    //  Lottery State
    // ──────────────────────────────────────────────

    struct Ticket {
        address buyer;
    }

    struct Round {
        uint256 prizePool;         // Accumulated 70% share
        uint256 totalTickets;
        uint256 drawTime;          // Timestamp when draw can occur
        uint256 vrfRequestId;
        bool drawInProgress;
        bool settled;
        address grandWinner;
        uint256 grandPrize;
    }

    uint256 public currentRoundId;
    uint256 public ticketPrice;        // In USDC (6 decimals), e.g. 1e6 = $1
    uint256 public drawInterval;       // Seconds between draws (default 86400 = 24h)
    uint256 public minPotForDraw;      // Minimum prize pool to allow a draw

    mapping(uint256 => Round) public rounds;
    mapping(uint256 => Ticket[]) internal roundTickets;
    mapping(uint256 => uint256) public vrfRequestToRound;

    /// @notice Player's ticket count per round (for efficient lookup)
    mapping(uint256 => mapping(address => uint256)) public playerTicketCount;

    /// @notice Claimable prizes per user per round
    mapping(uint256 => mapping(address => uint256)) public claimable;

    /// @notice Whether user has claimed for a round
    mapping(uint256 => mapping(address => bool)) public claimed;

    /// @notice All winners for a round (populated on settlement)
    mapping(uint256 => address[]) public roundWinners;

    /// @notice Prize amount per winner for a round
    mapping(uint256 => uint256[]) public roundPrizes;

    /// @notice Tier index per winner for a round
    mapping(uint256 => uint256[]) public roundWinnerTiers;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event RoundStarted(uint256 indexed roundId, uint256 drawTime, uint256 ticketPrice);
    event TicketPurchased(uint256 indexed roundId, address indexed buyer, uint256 quantity, address referrer);
    event DrawRequested(uint256 indexed roundId, uint256 vrfRequestId);
    event DrawCompleted(uint256 indexed roundId, uint256 totalPrizesPaid, uint256 totalWinSharePaid, uint256 winnersCount);
    event WinnerSelected(uint256 indexed roundId, uint256 tier, address indexed winner, uint256 prize);
    event PrizeClaimed(uint256 indexed roundId, address indexed winner, uint256 amount);
    event TicketPriceUpdated(uint256 newPrice);
    event DrawIntervalUpdated(uint256 newInterval);
    event MinPotUpdated(uint256 newMinPot);
    event VRFConfigUpdated(uint256 subId, bytes32 keyHash, uint32 callbackGasLimit, uint16 requestConfirmations);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error ZeroQuantity();
    error DrawAlreadyInProgress();
    error DrawNotReady();
    error NoTicketsSold();
    error RoundNotSettled();
    error NothingToClaim();
    error AlreadyClaimed();
    error InvalidTicketPrice();
    error InvalidDrawInterval();

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    constructor(
        address _vrfCoordinator,
        address _usdc,
        address _lpVault,
        address _referralManager,
        uint256 _ticketPrice,
        uint256 _drawInterval,
        uint256 _minPotForDraw,
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        usdc = IERC20(_usdc);
        lpVault = LPVault(_lpVault);
        referralManager = ReferralManager(_referralManager);
        ticketPrice = _ticketPrice;
        drawInterval = _drawInterval;
        minPotForDraw = _minPotForDraw;

        s_subscriptionId = _subscriptionId;
        s_keyHash = _keyHash;
        s_callbackGasLimit = _callbackGasLimit;
        s_requestConfirmations = _requestConfirmations;

        // Configure 8 prize tiers
        //              poolBps  winnerCount
        tiers[0] = TierConfig(4000, 1);   // Grand:  40%, 1 winner
        tiers[1] = TierConfig(1500, 1);   // Tier 1: 15%, 1 winner
        tiers[2] = TierConfig(1000, 1);   // Tier 2: 10%, 1 winner
        tiers[3] = TierConfig(1000, 2);   // Tier 3: 10%, 2 winners (5% each)
        tiers[4] = TierConfig( 800, 3);   // Tier 4:  8%, 3 winners (~2.67% each)
        tiers[5] = TierConfig( 700, 5);   // Tier 5:  7%, 5 winners (1.4% each)
        tiers[6] = TierConfig( 500, 8);   // Tier 6:  5%, 8 winners (0.625% each)
        tiers[7] = TierConfig( 500, 13);  // Tier 7:  5%, 13 winners (~0.385% each)
        // Total: 10000 bps, 34 winners

        // Start round 1
        currentRoundId = 1;
        rounds[1].drawTime = block.timestamp + _drawInterval;

        emit RoundStarted(1, rounds[1].drawTime, _ticketPrice);
    }

    // ──────────────────────────────────────────────
    //  Ticket Purchase
    // ──────────────────────────────────────────────

    /// @notice Buy lottery tickets for the current round
    /// @param quantity Number of tickets to buy
    /// @param referrer Referrer address (address(0) if none)
    function buyTicket(uint256 quantity, address referrer) external nonReentrant whenNotPaused {
        if (quantity == 0) revert ZeroQuantity();

        Round storage round = rounds[currentRoundId];
        if (round.drawInProgress) revert DrawAlreadyInProgress();

        uint256 totalCost = ticketPrice * quantity;
        usdc.safeTransferFrom(msg.sender, address(this), totalCost);

        // Split fees
        uint256 prizeShare = (totalCost * JACKPOT_BPS) / 10000;
        uint256 lpShare = (totalCost * LP_BPS) / 10000;
        uint256 referralShare = totalCost - prizeShare - lpShare; // Remainder to avoid rounding loss

        // Prize pool stays in this contract
        round.prizePool += prizeShare;

        // LP yield
        usdc.safeTransfer(address(lpVault), lpShare);
        lpVault.accrueYield(lpShare);

        // Referral (two-tier purchase fee distribution)
        usdc.safeTransfer(address(referralManager), referralShare);
        referralManager.recordSale(msg.sender, referrer, referralShare);

        // Record tickets
        for (uint256 i = 0; i < quantity; i++) {
            roundTickets[currentRoundId].push(Ticket({buyer: msg.sender}));
        }
        round.totalTickets += quantity;
        playerTicketCount[currentRoundId][msg.sender] += quantity;

        emit TicketPurchased(currentRoundId, msg.sender, quantity, referrer);
    }

    // ──────────────────────────────────────────────
    //  Chainlink Automation — Daily Draw Trigger
    // ──────────────────────────────────────────────

    /// @notice Chainlink Automation check: has draw time passed and are conditions met?
    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        Round storage round = rounds[currentRoundId];
        upkeepNeeded = block.timestamp >= round.drawTime
            && !round.drawInProgress
            && round.totalTickets > 0
            && round.prizePool >= minPotForDraw;
        performData = "";
    }

    /// @notice Chainlink Automation perform: request VRF randomness for daily draw
    function performUpkeep(bytes calldata) external override {
        Round storage round = rounds[currentRoundId];

        if (round.drawInProgress) revert DrawAlreadyInProgress();
        if (block.timestamp < round.drawTime) revert DrawNotReady();
        if (round.totalTickets == 0) revert NoTicketsSold();
        // minPotForDraw check: if pot is too small, skip this draw and extend
        if (round.prizePool < minPotForDraw) {
            round.drawTime = block.timestamp + drawInterval;
            emit RoundStarted(currentRoundId, round.drawTime, ticketPrice);
            return;
        }

        round.drawInProgress = true;

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_keyHash,
                subId: s_subscriptionId,
                requestConfirmations: s_requestConfirmations,
                callbackGasLimit: s_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );

        round.vrfRequestId = requestId;
        vrfRequestToRound[requestId] = currentRoundId;

        emit DrawRequested(currentRoundId, requestId);
    }

    // ──────────────────────────────────────────────
    //  VRF Callback — Multi-Tier Winner Selection
    // ──────────────────────────────────────────────

    /// @notice Chainlink VRF callback: select winners across 8 tiers.
    ///         Win-share is batched into a single transfer to save gas.
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        uint256 roundId = vrfRequestToRound[requestId];
        Round storage round = rounds[roundId];

        uint256 totalTickets = round.totalTickets;
        uint256 pot = round.prizePool;

        // --- Pass 1: Select winners, credit prizes, accumulate win-share ---
        uint256 totalWinShare;
        uint256 wordIndex;

        // Temporary arrays for win-share batch processing
        address[] memory winners = new address[](TOTAL_WINNERS);
        uint256[] memory winShares = new uint256[](TOTAL_WINNERS);

        for (uint256 t = 0; t < NUM_TIERS; t++) {
            uint256 tierPool = (pot * tiers[t].poolBps) / 10000;
            uint256 count = tiers[t].winnerCount;
            uint256 prizePerWinner = tierPool / count;
            uint256 winShare = (prizePerWinner * WINSHARE_BPS) / 10000;
            uint256 netPrize = prizePerWinner - winShare;

            for (uint256 w = 0; w < count; w++) {
                address winner = roundTickets[roundId][randomWords[wordIndex] % totalTickets].buyer;

                claimable[roundId][winner] += netPrize;
                winners[wordIndex] = winner;
                winShares[wordIndex] = winShare;
                totalWinShare += winShare;

                roundWinners[roundId].push(winner);
                roundPrizes[roundId].push(netPrize);
                roundWinnerTiers[roundId].push(t);

                if (wordIndex == 0) {
                    round.grandWinner = winner;
                    round.grandPrize = netPrize;
                }

                emit WinnerSelected(roundId, t, winner, netPrize);
                wordIndex++;
            }
        }

        // --- Pass 2: Batch win-share transfer + per-winner recording ---
        if (totalWinShare > 0) {
            usdc.safeTransfer(address(referralManager), totalWinShare);
            for (uint256 i = 0; i < TOTAL_WINNERS; i++) {
                if (winShares[i] > 0) {
                    referralManager.recordWinShare(winners[i], winShares[i]);
                }
            }
        }

        round.settled = true;
        round.drawInProgress = false;

        emit DrawCompleted(roundId, pot - totalWinShare, totalWinShare, TOTAL_WINNERS);

        // Start next round with next draw time
        currentRoundId++;
        rounds[currentRoundId].drawTime = block.timestamp + drawInterval;
        emit RoundStarted(currentRoundId, rounds[currentRoundId].drawTime, ticketPrice);
    }

    // ──────────────────────────────────────────────
    //  Prize Claims (pull-based)
    // ──────────────────────────────────────────────

    /// @notice Winners claim their prizes
    function claimPrize(uint256 roundId) external nonReentrant {
        if (!rounds[roundId].settled) revert RoundNotSettled();
        if (claimed[roundId][msg.sender]) revert AlreadyClaimed();

        uint256 amount = claimable[roundId][msg.sender];
        if (amount == 0) revert NothingToClaim();

        claimed[roundId][msg.sender] = true;
        usdc.safeTransfer(msg.sender, amount);

        emit PrizeClaimed(roundId, msg.sender, amount);
    }

    // ──────────────────────────────────────────────
    //  Admin (uses ConfirmedOwner from VRFConsumerBaseV2Plus)
    // ──────────────────────────────────────────────

    function setTicketPrice(uint256 _ticketPrice) external onlyOwner {
        if (_ticketPrice == 0) revert InvalidTicketPrice();
        ticketPrice = _ticketPrice;
        emit TicketPriceUpdated(_ticketPrice);
    }

    function setDrawInterval(uint256 _drawInterval) external onlyOwner {
        if (_drawInterval == 0) revert InvalidDrawInterval();
        drawInterval = _drawInterval;
        emit DrawIntervalUpdated(_drawInterval);
    }

    function setMinPotForDraw(uint256 _minPotForDraw) external onlyOwner {
        minPotForDraw = _minPotForDraw;
        emit MinPotUpdated(_minPotForDraw);
    }

    function updateVRFConfig(
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations
    ) external onlyOwner {
        s_subscriptionId = _subscriptionId;
        s_keyHash = _keyHash;
        s_callbackGasLimit = _callbackGasLimit;
        s_requestConfirmations = _requestConfirmations;
        emit VRFConfigUpdated(_subscriptionId, _keyHash, _callbackGasLimit, _requestConfirmations);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ──────────────────────────────────────────────
    //  View Helpers
    // ──────────────────────────────────────────────

    /// @notice Get current round info
    function getCurrentRound()
        external
        view
        returns (
            uint256 roundId,
            uint256 prizePool,
            uint256 totalTickets,
            uint256 drawTime,
            bool drawInProgress
        )
    {
        Round storage round = rounds[currentRoundId];
        return (currentRoundId, round.prizePool, round.totalTickets, round.drawTime, round.drawInProgress);
    }

    /// @notice Get ticket count for a player in a specific round (O(1))
    function getPlayerTicketCount(uint256 roundId, address player) external view returns (uint256) {
        return playerTicketCount[roundId][player];
    }

    /// @notice Get total tickets in a round
    function getRoundTicketCount(uint256 roundId) external view returns (uint256) {
        return roundTickets[roundId].length;
    }

    /// @notice Get all winners for a settled round
    function getRoundWinners(uint256 roundId)
        external
        view
        returns (address[] memory winners, uint256[] memory prizes, uint256[] memory tierIndices)
    {
        return (roundWinners[roundId], roundPrizes[roundId], roundWinnerTiers[roundId]);
    }

    /// @notice Get tier configuration
    function getTierConfig(uint256 tierIndex) external view returns (uint256 poolBps, uint256 winnerCount) {
        require(tierIndex < NUM_TIERS, "Invalid tier");
        TierConfig storage tier = tiers[tierIndex];
        return (tier.poolBps, tier.winnerCount);
    }

    /// @notice Time remaining until next draw (0 if draw is ready)
    function timeUntilDraw() external view returns (uint256) {
        uint256 drawTime = rounds[currentRoundId].drawTime;
        if (block.timestamp >= drawTime) return 0;
        return drawTime - block.timestamp;
    }
}
