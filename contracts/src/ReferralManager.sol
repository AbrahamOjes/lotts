// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ReferralManager
/// @notice Two-tier referral system with win-share, designed for emerging market viral growth.
///
///  Purchase fees (from the 10% referral share of ticket sales):
///    - 1st-order referrer: 80% of referral share (≈8% of ticket price)
///    - 2nd-order referrer: 20% of referral share (≈2% of ticket price)
///    - Treasury gets whatever is unassigned (no referrer, self-referral, single-tier only)
///
///  Win-share (called by Lottery when a referred player wins):
///    - 1st-order referrer: 8% of prize
///    - 2nd-order referrer: 2% of prize
///    - Win-share is funded from the prize pool (Lottery sends USDC here)
///
///  Sticky referrals: a player's first referrer persists for all future purchases.
contract ReferralManager is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ──────────────────────────────────────────────
    //  Constants
    // ──────────────────────────────────────────────

    /// @notice Purchase fee split between tiers (basis points of referral share)
    uint256 public constant TIER1_PURCHASE_BPS = 8000; // 80% of referral share → ~8% of ticket
    uint256 public constant TIER2_PURCHASE_BPS = 2000; // 20% of referral share → ~2% of ticket

    /// @notice Win-share percentages (basis points of prize amount)
    uint256 public constant TIER1_WINSHARE_BPS = 800;  // 8% of prize
    uint256 public constant TIER2_WINSHARE_BPS = 200;  // 2% of prize

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────

    IERC20 public immutable usdc;
    address public lottery;
    address public treasury;

    /// @notice First referrer for each player (sticky, immutable once set)
    mapping(address => address) public playerReferrer;

    /// @notice Accrued, unclaimed commissions per referrer
    mapping(address => uint256) public pendingCommission;

    /// @notice Lifetime purchase-fee earnings per referrer
    mapping(address => uint256) public totalEarned;

    /// @notice Lifetime win-share earnings per referrer
    mapping(address => uint256) public totalWinShare;

    /// @notice Number of directly-referred players per referrer
    mapping(address => uint256) public referralCount;

    /// @notice Number of second-tier referred players
    mapping(address => uint256) public tier2Count;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event LotterySet(address indexed lottery);
    event TreasurySet(address indexed treasury);
    event ReferrerSet(address indexed player, address indexed referrer);
    event PurchaseFeeRecorded(
        address indexed buyer,
        address indexed tier1Referrer,
        uint256 tier1Amount,
        address tier2Referrer,
        uint256 tier2Amount,
        uint256 treasuryAmount
    );
    event WinShareRecorded(
        address indexed winner,
        address indexed tier1Referrer,
        uint256 tier1Amount,
        address tier2Referrer,
        uint256 tier2Amount
    );
    event CommissionClaimed(address indexed referrer, uint256 amount);
    event TreasuryPaid(uint256 amount);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error OnlyLottery();
    error ZeroAddress();
    error NothingToClaim();

    modifier onlyLottery() {
        if (msg.sender != lottery) revert OnlyLottery();
        _;
    }

    constructor(address _usdc, address _treasury, address _owner) Ownable(_owner) {
        if (_usdc == address(0) || _treasury == address(0)) revert ZeroAddress();
        usdc = IERC20(_usdc);
        treasury = _treasury;
    }

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    function setLottery(address _lottery) external onlyOwner {
        if (_lottery == address(0)) revert ZeroAddress();
        lottery = _lottery;
        emit LotterySet(_lottery);
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    // ──────────────────────────────────────────────
    //  Purchase Fee Distribution (called by Lottery)
    // ──────────────────────────────────────────────

    /// @notice Called by Lottery on each ticket purchase.
    ///         Distributes the referral share across two tiers.
    /// @param buyer The ticket buyer
    /// @param referrer The referrer address from the frontend (address(0) if none)
    /// @param amount The total referral commission (10% of ticket cost)
    function recordSale(address buyer, address referrer, uint256 amount) external onlyLottery {
        if (amount == 0) return;

        // Resolve and persist sticky referrer
        address tier1 = _resolveReferrer(buyer, referrer);
        address tier2 = tier1 != address(0) ? playerReferrer[tier1] : address(0);

        uint256 tier1Amount;
        uint256 tier2Amount;
        uint256 treasuryAmount;

        if (tier1 != address(0)) {
            tier1Amount = (amount * TIER1_PURCHASE_BPS) / 10000;

            if (tier2 != address(0) && tier2 != buyer) {
                tier2Amount = (amount * TIER2_PURCHASE_BPS) / 10000;
            }

            treasuryAmount = amount - tier1Amount - tier2Amount;

            // Credit tier-1 referrer
            pendingCommission[tier1] += tier1Amount;
            totalEarned[tier1] += tier1Amount;

            // Credit tier-2 referrer
            if (tier2Amount > 0) {
                pendingCommission[tier2] += tier2Amount;
                totalEarned[tier2] += tier2Amount;
            }

            referralCount[tier1] += 1;
        } else {
            treasuryAmount = amount;
        }

        // Treasury gets unassigned portion
        if (treasuryAmount > 0) {
            usdc.safeTransfer(treasury, treasuryAmount);
        }

        emit PurchaseFeeRecorded(buyer, tier1, tier1Amount, tier2, tier2Amount, treasuryAmount);
    }

    // ──────────────────────────────────────────────
    //  Win-Share Distribution (called by Lottery)
    // ──────────────────────────────────────────────

    /// @notice Called by Lottery when a referred player wins a prize.
    ///         The Lottery transfers the win-share USDC to this contract before calling.
    /// @param winner The prize winner
    /// @param amount The total win-share amount (already transferred to this contract)
    function recordWinShare(address winner, uint256 amount) external onlyLottery {
        if (amount == 0) return;

        address tier1 = playerReferrer[winner];
        address tier2 = tier1 != address(0) ? playerReferrer[tier1] : address(0);

        uint256 tier1Amount;
        uint256 tier2Amount;

        if (tier1 != address(0)) {
            // Win-share BPS are relative to the prize, but `amount` is already the total
            // win-share budget. Split it: tier1 gets 80%, tier2 gets 20%.
            tier1Amount = (amount * TIER1_WINSHARE_BPS) / (TIER1_WINSHARE_BPS + TIER2_WINSHARE_BPS);

            if (tier2 != address(0) && tier2 != winner) {
                tier2Amount = amount - tier1Amount;
            } else {
                // No tier-2: tier-1 gets everything
                tier1Amount = amount;
            }

            pendingCommission[tier1] += tier1Amount;
            totalWinShare[tier1] += tier1Amount;

            if (tier2Amount > 0) {
                pendingCommission[tier2] += tier2Amount;
                totalWinShare[tier2] += tier2Amount;
            }
        } else {
            // No referrer — win-share goes to treasury
            usdc.safeTransfer(treasury, amount);
        }

        emit WinShareRecorded(winner, tier1, tier1Amount, tier2, tier2Amount);
    }

    // ──────────────────────────────────────────────
    //  Claim
    // ──────────────────────────────────────────────

    /// @notice Referrers claim all accrued commissions (purchase fees + win-share)
    function claimCommission() external nonReentrant {
        uint256 amount = pendingCommission[msg.sender];
        if (amount == 0) revert NothingToClaim();

        pendingCommission[msg.sender] = 0;
        usdc.safeTransfer(msg.sender, amount);

        emit CommissionClaimed(msg.sender, amount);
    }

    // ──────────────────────────────────────────────
    //  View Helpers
    // ──────────────────────────────────────────────

    /// @notice Get full referral stats for a referrer
    function getReferrerStats(address ref)
        external
        view
        returns (
            uint256 pending,
            uint256 earnedFromPurchases,
            uint256 earnedFromWinShare,
            uint256 directReferrals,
            uint256 secondTierReferrals
        )
    {
        return (
            pendingCommission[ref],
            totalEarned[ref],
            totalWinShare[ref],
            referralCount[ref],
            tier2Count[ref]
        );
    }

    /// @notice Get the full referral chain for a player
    function getReferralChain(address player) external view returns (address tier1, address tier2) {
        tier1 = playerReferrer[player];
        tier2 = tier1 != address(0) ? playerReferrer[tier1] : address(0);
    }

    // ──────────────────────────────────────────────
    //  Internal
    // ──────────────────────────────────────────────

    /// @dev Resolve the effective referrer for a buyer. Sets sticky referral if new.
    function _resolveReferrer(address buyer, address referrer) internal returns (address) {
        address existing = playerReferrer[buyer];

        // Already has a sticky referrer — use it
        if (existing != address(0)) {
            return existing;
        }

        // New referrer provided and valid
        if (referrer != address(0) && referrer != buyer) {
            playerReferrer[buyer] = referrer;

            // Track tier-2 count for the referrer's referrer
            address upstream = playerReferrer[referrer];
            if (upstream != address(0) && upstream != buyer) {
                tier2Count[upstream] += 1;
            }

            emit ReferrerSet(buyer, referrer);
            return referrer;
        }

        // No referrer
        return address(0);
    }
}
