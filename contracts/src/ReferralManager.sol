// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ReferralManager
/// @notice Tracks referral relationships and distributes 10% of ticket sales as commissions.
///         Sticky referrals: a player's first referrer persists for all future purchases.
contract ReferralManager is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    address public lottery;
    address public treasury;

    /// @notice First referrer for each player (sticky)
    mapping(address => address) public playerReferrer;

    /// @notice Accrued, unclaimed commissions per referrer
    mapping(address => uint256) public pendingCommission;

    /// @notice Lifetime earnings per referrer
    mapping(address => uint256) public totalEarned;

    /// @notice Number of referred ticket purchases per referrer
    mapping(address => uint256) public referralCount;

    event LotterySet(address indexed lottery);
    event TreasurySet(address indexed treasury);
    event SaleRecorded(address indexed buyer, address indexed referrer, uint256 amount);
    event CommissionClaimed(address indexed referrer, uint256 amount);
    event TreasuryPaid(uint256 amount);

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

    /// @notice Set the lottery contract address (only owner, one-time setup)
    function setLottery(address _lottery) external onlyOwner {
        if (_lottery == address(0)) revert ZeroAddress();
        lottery = _lottery;
        emit LotterySet(_lottery);
    }

    /// @notice Update treasury address
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    /// @notice Called by Lottery on each ticket purchase to credit referral commission.
    ///         If no referrer is provided but the buyer has a sticky referrer, use that.
    ///         If no referrer at all, commission goes to treasury.
    /// @param buyer The ticket buyer
    /// @param referrer The referrer address from the frontend (address(0) if none)
    /// @param amount The referral commission amount (10% of ticket price, already calculated)
    function recordSale(address buyer, address referrer, uint256 amount) external onlyLottery {
        if (amount == 0) return;

        // Determine effective referrer
        address effectiveReferrer = referrer;

        // If referrer provided and buyer has no existing referrer, set sticky
        if (effectiveReferrer != address(0) && effectiveReferrer != buyer) {
            if (playerReferrer[buyer] == address(0)) {
                playerReferrer[buyer] = effectiveReferrer;
            } else {
                // Use existing sticky referrer
                effectiveReferrer = playerReferrer[buyer];
            }
        } else if (effectiveReferrer == address(0) || effectiveReferrer == buyer) {
            // Check for sticky referrer
            effectiveReferrer = playerReferrer[buyer];
        }

        if (effectiveReferrer != address(0) && effectiveReferrer != buyer) {
            // Credit referrer
            pendingCommission[effectiveReferrer] += amount;
            totalEarned[effectiveReferrer] += amount;
            referralCount[effectiveReferrer] += 1;
            emit SaleRecorded(buyer, effectiveReferrer, amount);
        } else {
            // No referrer — send to treasury
            usdc.safeTransfer(treasury, amount);
            emit TreasuryPaid(amount);
        }
    }

    /// @notice Referrers claim their accrued commissions
    function claimCommission() external nonReentrant {
        uint256 amount = pendingCommission[msg.sender];
        if (amount == 0) revert NothingToClaim();

        pendingCommission[msg.sender] = 0;
        usdc.safeTransfer(msg.sender, amount);

        emit CommissionClaimed(msg.sender, amount);
    }
}
