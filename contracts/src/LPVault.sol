// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title LPVault
/// @notice Liquidity provider vault that backs the lottery prize pool.
///         LPs deposit USDC and earn 20% of all ticket sales, distributed pro-rata.
///         Uses yield-per-share accounting (masterchef pattern).
contract LPVault is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    address public lottery;

    uint256 public totalDeposited;

    /// @notice Accumulated yield per share, scaled by 1e18
    uint256 public yieldPerShare;

    /// @notice User deposit amounts
    mapping(address => uint256) public userDeposits;

    /// @notice Yield debt for correct accounting on deposit/withdraw
    mapping(address => uint256) public userYieldDebt;

    /// @notice Minimum USDC that must remain in vault to back current round
    uint256 public minCollateral;

    uint256 private constant PRECISION = 1e18;

    event LotterySet(address indexed lottery);
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event YieldAccrued(uint256 amount, uint256 newYieldPerShare);
    event YieldClaimed(address indexed user, uint256 amount);
    event MinCollateralSet(uint256 amount);

    error OnlyLottery();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientDeposit();
    error WouldUndercollateralize();
    error NothingToClaim();

    modifier onlyLottery() {
        if (msg.sender != lottery) revert OnlyLottery();
        _;
    }

    constructor(address _usdc, address _owner) Ownable(_owner) {
        if (_usdc == address(0)) revert ZeroAddress();
        usdc = IERC20(_usdc);
    }

    /// @notice Set the lottery contract (only owner)
    function setLottery(address _lottery) external onlyOwner {
        if (_lottery == address(0)) revert ZeroAddress();
        lottery = _lottery;
        emit LotterySet(_lottery);
    }

    /// @notice Set minimum collateral requirement
    function setMinCollateral(uint256 _minCollateral) external onlyOwner {
        minCollateral = _minCollateral;
        emit MinCollateralSet(_minCollateral);
    }

    /// @notice Deposit USDC into the vault
    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        // Claim pending yield before changing deposit
        _claimYield(msg.sender);

        usdc.safeTransferFrom(msg.sender, address(this), amount);

        userDeposits[msg.sender] += amount;
        totalDeposited += amount;

        // Set yield debt so new deposit doesn't earn past yield
        userYieldDebt[msg.sender] = (userDeposits[msg.sender] * yieldPerShare) / PRECISION;

        emit Deposited(msg.sender, amount);
    }

    /// @notice Withdraw USDC from the vault
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (userDeposits[msg.sender] < amount) revert InsufficientDeposit();

        // Check collateral requirement
        if (totalDeposited - amount < minCollateral) revert WouldUndercollateralize();

        // Claim pending yield before changing deposit
        _claimYield(msg.sender);

        userDeposits[msg.sender] -= amount;
        totalDeposited -= amount;

        // Update yield debt
        userYieldDebt[msg.sender] = (userDeposits[msg.sender] * yieldPerShare) / PRECISION;

        usdc.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Called by Lottery on each ticket purchase (the 20% LP share).
    ///         Increases yieldPerShare for all LPs pro-rata.
    function accrueYield(uint256 amount) external onlyLottery {
        if (amount == 0) return;

        if (totalDeposited > 0) {
            yieldPerShare += (amount * PRECISION) / totalDeposited;
        }
        // If no LPs, yield stays in vault as surplus (will benefit next depositor)

        emit YieldAccrued(amount, yieldPerShare);
    }

    /// @notice Claim accrued yield
    function claimYield() external nonReentrant {
        uint256 claimed = _claimYield(msg.sender);
        if (claimed == 0) revert NothingToClaim();
    }

    /// @notice View pending yield for a user
    function pendingYield(address user) external view returns (uint256) {
        uint256 accumulatedYield = (userDeposits[user] * yieldPerShare) / PRECISION;
        if (accumulatedYield <= userYieldDebt[user]) return 0;
        return accumulatedYield - userYieldDebt[user];
    }

    /// @notice Internal claim logic
    function _claimYield(address user) internal returns (uint256 pending) {
        uint256 accumulatedYield = (userDeposits[user] * yieldPerShare) / PRECISION;

        if (accumulatedYield > userYieldDebt[user]) {
            pending = accumulatedYield - userYieldDebt[user];
            userYieldDebt[user] = accumulatedYield;
            usdc.safeTransfer(user, pending);
            emit YieldClaimed(user, pending);
        }
    }
}
