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
/// @notice Megapot-style lottery on Polygon. $1 USDC tickets, draw when pot fills.
///         Fee split: 70% jackpot, 20% LP yield, 10% referrals.
///         Uses Chainlink VRF v2.5 for provably fair randomness and Chainlink Automation for draws.
contract Lottery is VRFConsumerBaseV2Plus, AutomationCompatibleInterface, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ──────────────────────────────────────────────
    //  Constants
    // ──────────────────────────────────────────────

    /// @notice Fee split basis points (out of 10000)
    uint256 public constant JACKPOT_BPS = 7000;   // 70%
    uint256 public constant LP_BPS = 2000;         // 20%
    uint256 public constant REFERRAL_BPS = 1000;   // 10%

    /// @notice Prize distribution from jackpot pot
    uint256 public constant GRAND_PRIZE_BPS = 9000; // 90% of pot to grand winner
    uint256 public constant SECONDARY_PRIZES = 5;   // 5 secondary winners
    uint256 public constant SECONDARY_PRIZE_BPS = 200; // 2% each

    /// @notice VRF needs 1 word for grand prize + 5 for secondary = 6
    uint32 public constant NUM_WORDS = 6;

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
    //  Lottery State
    // ──────────────────────────────────────────────

    struct Ticket {
        address buyer;
    }

    struct Round {
        uint256 targetPot;
        uint256 jackpotAmount;     // Accumulated 70% share
        uint256 totalTickets;
        uint256 vrfRequestId;
        bool drawInProgress;
        bool settled;
        address grandWinner;
        uint256 grandPrize;
    }

    uint256 public currentRoundId;
    uint256 public ticketPrice;     // In USDC (6 decimals), e.g. 1e6 = $1
    uint256 public targetPot;       // Target jackpot to trigger draw

    mapping(uint256 => Round) public rounds;
    mapping(uint256 => Ticket[]) internal roundTickets;
    mapping(uint256 => uint256) public vrfRequestToRound;

    /// @notice Claimable prizes per user per round
    mapping(uint256 => mapping(address => uint256)) public claimable;

    /// @notice Whether user has claimed for a round
    mapping(uint256 => mapping(address => bool)) public claimed;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event RoundStarted(uint256 indexed roundId, uint256 targetPot, uint256 ticketPrice);
    event TicketPurchased(uint256 indexed roundId, address indexed buyer, uint256 quantity, address referrer);
    event DrawRequested(uint256 indexed roundId, uint256 vrfRequestId);
    event DrawCompleted(
        uint256 indexed roundId,
        address indexed grandWinner,
        uint256 grandPrize,
        address[5] secondaryWinners,
        uint256 secondaryPrize
    );
    event PrizeClaimed(uint256 indexed roundId, address indexed winner, uint256 amount);
    event TicketPriceUpdated(uint256 newPrice);
    event TargetPotUpdated(uint256 newTarget);
    event VRFConfigUpdated(uint256 subId, bytes32 keyHash, uint32 callbackGasLimit, uint16 requestConfirmations);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error ZeroQuantity();
    error DrawAlreadyInProgress();
    error PotNotReached();
    error NoTicketsSold();
    error RoundNotSettled();
    error NothingToClaim();
    error AlreadyClaimed();
    error InvalidTicketPrice();
    error InvalidTargetPot();

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    constructor(
        address _vrfCoordinator,
        address _usdc,
        address _lpVault,
        address _referralManager,
        uint256 _ticketPrice,
        uint256 _targetPot,
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        usdc = IERC20(_usdc);
        lpVault = LPVault(_lpVault);
        referralManager = ReferralManager(_referralManager);
        ticketPrice = _ticketPrice;
        targetPot = _targetPot;

        s_subscriptionId = _subscriptionId;
        s_keyHash = _keyHash;
        s_callbackGasLimit = _callbackGasLimit;
        s_requestConfirmations = _requestConfirmations;

        // Start round 1
        currentRoundId = 1;
        rounds[1].targetPot = _targetPot;

        emit RoundStarted(1, _targetPot, _ticketPrice);
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
        uint256 jackpotShare = (totalCost * JACKPOT_BPS) / 10000;
        uint256 lpShare = (totalCost * LP_BPS) / 10000;
        uint256 referralShare = totalCost - jackpotShare - lpShare; // Remainder to avoid rounding loss

        // Jackpot stays in this contract
        round.jackpotAmount += jackpotShare;

        // LP yield
        usdc.safeTransfer(address(lpVault), lpShare);
        lpVault.accrueYield(lpShare);

        // Referral
        usdc.safeTransfer(address(referralManager), referralShare);
        referralManager.recordSale(msg.sender, referrer, referralShare);

        // Record tickets
        for (uint256 i = 0; i < quantity; i++) {
            roundTickets[currentRoundId].push(Ticket({buyer: msg.sender}));
        }
        round.totalTickets += quantity;

        emit TicketPurchased(currentRoundId, msg.sender, quantity, referrer);
    }

    // ──────────────────────────────────────────────
    //  Chainlink Automation
    // ──────────────────────────────────────────────

    /// @notice Chainlink Automation check: is the pot full and no draw in progress?
    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        Round storage round = rounds[currentRoundId];
        upkeepNeeded = round.jackpotAmount >= round.targetPot
            && !round.drawInProgress
            && round.totalTickets > 0;
        performData = "";
    }

    /// @notice Chainlink Automation perform: request VRF randomness
    function performUpkeep(bytes calldata) external override {
        Round storage round = rounds[currentRoundId];

        if (round.drawInProgress) revert DrawAlreadyInProgress();
        if (round.jackpotAmount < round.targetPot) revert PotNotReached();
        if (round.totalTickets == 0) revert NoTicketsSold();

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
    //  VRF Callback
    // ──────────────────────────────────────────────

    /// @notice Chainlink VRF callback: select winners and store claimable prizes
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        uint256 roundId = vrfRequestToRound[requestId];
        Round storage round = rounds[roundId];

        uint256 totalTickets = round.totalTickets;
        uint256 pot = round.jackpotAmount;

        // Grand prize winner
        uint256 grandWinnerIdx = randomWords[0] % totalTickets;
        address grandWinner = roundTickets[roundId][grandWinnerIdx].buyer;
        uint256 grandPrize = (pot * GRAND_PRIZE_BPS) / 10000;

        round.grandWinner = grandWinner;
        round.grandPrize = grandPrize;
        claimable[roundId][grandWinner] += grandPrize;

        // Secondary winners
        address[5] memory secondaryWinners;
        uint256 secondaryPrize = (pot * SECONDARY_PRIZE_BPS) / 10000;

        for (uint256 i = 0; i < SECONDARY_PRIZES; i++) {
            uint256 winnerIdx = randomWords[i + 1] % totalTickets;
            address winner = roundTickets[roundId][winnerIdx].buyer;
            secondaryWinners[i] = winner;
            claimable[roundId][winner] += secondaryPrize;
        }

        round.settled = true;
        round.drawInProgress = false;

        emit DrawCompleted(roundId, grandWinner, grandPrize, secondaryWinners, secondaryPrize);

        // Start next round
        currentRoundId++;
        rounds[currentRoundId].targetPot = targetPot;
        emit RoundStarted(currentRoundId, targetPot, ticketPrice);
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

    function setTargetPot(uint256 _targetPot) external onlyOwner {
        if (_targetPot == 0) revert InvalidTargetPot();
        targetPot = _targetPot;
        emit TargetPotUpdated(_targetPot);
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
            uint256 jackpotAmount,
            uint256 roundTargetPot,
            uint256 totalTickets,
            bool drawInProgress
        )
    {
        Round storage round = rounds[currentRoundId];
        return (currentRoundId, round.jackpotAmount, round.targetPot, round.totalTickets, round.drawInProgress);
    }

    /// @notice Get ticket count for a player in a specific round
    function getPlayerTicketCount(uint256 roundId, address player) external view returns (uint256 count) {
        Ticket[] storage tickets = roundTickets[roundId];
        for (uint256 i = 0; i < tickets.length; i++) {
            if (tickets[i].buyer == player) {
                count++;
            }
        }
    }

    /// @notice Get total tickets in a round
    function getRoundTicketCount(uint256 roundId) external view returns (uint256) {
        return roundTickets[roundId].length;
    }
}
