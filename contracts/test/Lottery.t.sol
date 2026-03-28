// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Lottery} from "../src/Lottery.sol";
import {LPVault} from "../src/LPVault.sol";
import {ReferralManager} from "../src/ReferralManager.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract LotteryTest is Test {
    Lottery public lottery;
    LPVault public lpVault;
    ReferralManager public referralManager;
    VRFCoordinatorV2_5Mock public vrfCoordinator;
    ERC20Mock public usdc;

    address public owner = address(this);
    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");
    address public referrer = makeAddr("referrer");

    uint256 public subscriptionId;
    uint256 public constant TICKET_PRICE = 1e6; // $1 USDC
    uint256 public constant TARGET_POT = 700e6; // $700 (70% of $1000 in tickets)

    function setUp() public {
        // Deploy mock USDC (6 decimals)
        usdc = new ERC20Mock("USD Coin", "USDC", 6);

        // Deploy VRF coordinator mock
        vrfCoordinator = new VRFCoordinatorV2_5Mock(
            100000000000000000, // 0.1 LINK base fee
            1000000000,         // 1 gwei gas price
            4000000000000000    // 0.004 ETH per LINK
        );

        // Create VRF subscription
        subscriptionId = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(subscriptionId, 1000 ether);

        // Deploy contracts
        referralManager = new ReferralManager(address(usdc), treasury, owner);
        lpVault = new LPVault(address(usdc), owner);

        lottery = new Lottery(
            address(vrfCoordinator),
            address(usdc),
            address(lpVault),
            address(referralManager),
            TICKET_PRICE,
            TARGET_POT,
            subscriptionId,
            bytes32(0), // keyHash (any for mock)
            500000,     // callbackGasLimit
            3           // requestConfirmations
        );

        // Wire contracts
        referralManager.setLottery(address(lottery));
        lpVault.setLottery(address(lottery));

        // Add lottery as VRF consumer
        vrfCoordinator.addConsumer(subscriptionId, address(lottery));

        // Mint USDC to test users
        usdc.mint(alice, 10000e6);
        usdc.mint(bob, 10000e6);
        usdc.mint(carol, 10000e6);

        // Approve lottery to spend USDC
        vm.prank(alice);
        usdc.approve(address(lottery), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(lottery), type(uint256).max);
        vm.prank(carol);
        usdc.approve(address(lottery), type(uint256).max);
    }

    // ──────────────────────────────────────────────
    //  Ticket Purchase Tests
    // ──────────────────────────────────────────────

    function test_buyTicket_single() public {
        vm.prank(alice);
        lottery.buyTicket(1, address(0));

        (uint256 roundId, uint256 jackpotAmount,, uint256 totalTickets,) = lottery.getCurrentRound();
        assertEq(roundId, 1);
        assertEq(totalTickets, 1);
        // 70% of $1 = $0.70
        assertEq(jackpotAmount, 700000);
    }

    function test_buyTicket_multiple() public {
        vm.prank(alice);
        lottery.buyTicket(10, address(0));

        (,, , uint256 totalTickets,) = lottery.getCurrentRound();
        assertEq(totalTickets, 10);
    }

    function test_buyTicket_feeSplit() public {
        uint256 lpVaultBefore = usdc.balanceOf(address(lpVault));

        vm.prank(alice);
        lottery.buyTicket(10, address(0)); // $10 total

        // LP gets 20% = $2
        uint256 lpVaultAfter = usdc.balanceOf(address(lpVault));
        assertEq(lpVaultAfter - lpVaultBefore, 2e6);

        // Jackpot gets 70% = $7
        (, uint256 jackpotAmount,,,) = lottery.getCurrentRound();
        assertEq(jackpotAmount, 7e6);

        // Referral 10% = $1 (goes to treasury since no referrer)
        assertEq(usdc.balanceOf(treasury), 1e6);
    }

    function test_buyTicket_withReferrer() public {
        vm.prank(alice);
        lottery.buyTicket(10, referrer); // $10 total

        // Referrer gets 10% = $1
        assertEq(referralManager.pendingCommission(referrer), 1e6);
        assertEq(referralManager.referralCount(referrer), 1);

        // Treasury gets nothing
        assertEq(usdc.balanceOf(treasury), 0);
    }

    function test_buyTicket_stickyReferrer() public {
        // First purchase with referrer
        vm.prank(alice);
        lottery.buyTicket(1, referrer);
        assertEq(referralManager.playerReferrer(alice), referrer);

        // Second purchase without referrer — should use sticky
        vm.prank(alice);
        lottery.buyTicket(1, address(0));
        assertEq(referralManager.pendingCommission(referrer), 200000); // 2 * $0.10
    }

    function test_buyTicket_revertZeroQuantity() public {
        vm.prank(alice);
        vm.expectRevert(Lottery.ZeroQuantity.selector);
        lottery.buyTicket(0, address(0));
    }

    // ──────────────────────────────────────────────
    //  Draw Tests
    // ──────────────────────────────────────────────

    function test_checkUpkeep_potNotReached() public {
        vm.prank(alice);
        lottery.buyTicket(1, address(0));

        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function test_checkUpkeep_potReached() public {
        _fillPot();

        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertTrue(upkeepNeeded);
    }

    function test_performUpkeep_requestsVRF() public {
        _fillPot();

        lottery.performUpkeep("");

        (,,,, bool drawInProgress) = lottery.getCurrentRound();
        assertTrue(drawInProgress);
    }

    function test_performUpkeep_revertPotNotReached() public {
        vm.prank(alice);
        lottery.buyTicket(1, address(0));

        vm.expectRevert(Lottery.PotNotReached.selector);
        lottery.performUpkeep("");
    }

    function test_fullDraw_selectsWinner() public {
        _fillPot();

        // Perform upkeep (request VRF)
        lottery.performUpkeep("");

        // Fulfill VRF
        vrfCoordinator.fulfillRandomWords(1, address(lottery));

        // Round should be settled
        (, , , , bool drawInProgress) = lottery.getCurrentRound();
        assertFalse(drawInProgress);

        // Should be on round 2 now
        (uint256 roundId,,,,) = lottery.getCurrentRound();
        assertEq(roundId, 2);

        // Check round 1 is settled
        (,,,,,bool settled,,) = lottery.rounds(1);
        assertTrue(settled);
    }

    function test_fullDraw_prizeDistribution() public {
        // Buy 1000 tickets ($1000 total, $700 jackpot)
        vm.prank(alice);
        lottery.buyTicket(500, address(0));
        vm.prank(bob);
        lottery.buyTicket(500, address(0));

        lottery.performUpkeep("");
        vrfCoordinator.fulfillRandomWords(1, address(lottery));

        // Grand prize = 90% of $700 = $630
        // Secondary prizes = 2% each = $14 each, 5 winners = $70 total
        (,,,,, bool settled, address grandWinner, uint256 grandPrize) = lottery.rounds(1);
        assertTrue(settled);
        assertEq(grandPrize, 630e6); // $630
        assertTrue(grandWinner == alice || grandWinner == bob);
    }

    function test_claimPrize() public {
        vm.prank(alice);
        lottery.buyTicket(1000, address(0));

        lottery.performUpkeep("");

        // Fulfill with known random words so alice wins
        uint256[] memory words = new uint256[](6);
        words[0] = 0; // Grand winner = ticket 0 = alice
        words[1] = 1;
        words[2] = 2;
        words[3] = 3;
        words[4] = 4;
        words[5] = 5;
        vrfCoordinator.fulfillRandomWordsWithOverride(1, address(lottery), words);

        // Alice should be grand winner
        uint256 claimableAmount = lottery.claimable(1, alice);
        assertTrue(claimableAmount > 0);

        uint256 balanceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        lottery.claimPrize(1);
        uint256 balanceAfter = usdc.balanceOf(alice);
        assertEq(balanceAfter - balanceBefore, claimableAmount);
    }

    function test_claimPrize_revertNotSettled() public {
        vm.prank(alice);
        vm.expectRevert(Lottery.RoundNotSettled.selector);
        lottery.claimPrize(1);
    }

    function test_claimPrize_revertDoubleClaim() public {
        vm.prank(alice);
        lottery.buyTicket(1000, address(0));

        lottery.performUpkeep("");

        uint256[] memory words = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) words[i] = 0; // All point to alice
        vrfCoordinator.fulfillRandomWordsWithOverride(1, address(lottery), words);

        vm.prank(alice);
        lottery.claimPrize(1);

        vm.prank(alice);
        vm.expectRevert(Lottery.AlreadyClaimed.selector);
        lottery.claimPrize(1);
    }

    // ──────────────────────────────────────────────
    //  LP Vault Tests
    // ──────────────────────────────────────────────

    function test_lpVault_deposit() public {
        usdc.mint(alice, 1000e6);
        vm.startPrank(alice);
        usdc.approve(address(lpVault), 1000e6);
        lpVault.deposit(1000e6);
        vm.stopPrank();

        assertEq(lpVault.userDeposits(alice), 1000e6);
        assertEq(lpVault.totalDeposited(), 1000e6);
    }

    function test_lpVault_yieldAccrual() public {
        // Alice deposits as LP
        usdc.mint(alice, 1000e6);
        vm.startPrank(alice);
        usdc.approve(address(lpVault), 1000e6);
        lpVault.deposit(1000e6);
        vm.stopPrank();

        // Bob buys tickets (generates yield for LPs)
        vm.prank(bob);
        lottery.buyTicket(100, address(0)); // $100 total, $20 to LP vault

        // Alice should have $20 pending yield
        uint256 pending = lpVault.pendingYield(alice);
        assertEq(pending, 20e6);

        // Claim yield
        vm.prank(alice);
        lpVault.claimYield();
        assertEq(lpVault.pendingYield(alice), 0);
    }

    function test_lpVault_multipleDepositors() public {
        // Alice and Carol each deposit $500
        usdc.mint(alice, 500e6);
        usdc.mint(carol, 500e6);

        vm.startPrank(alice);
        usdc.approve(address(lpVault), 500e6);
        lpVault.deposit(500e6);
        vm.stopPrank();

        vm.startPrank(carol);
        usdc.approve(address(lpVault), 500e6);
        lpVault.deposit(500e6);
        vm.stopPrank();

        // Bob buys $100 in tickets ($20 LP yield)
        vm.prank(bob);
        lottery.buyTicket(100, address(0));

        // Each should get $10
        assertEq(lpVault.pendingYield(alice), 10e6);
        assertEq(lpVault.pendingYield(carol), 10e6);
    }

    function test_lpVault_withdraw() public {
        usdc.mint(alice, 1000e6);
        vm.startPrank(alice);
        usdc.approve(address(lpVault), 1000e6);
        lpVault.deposit(1000e6);
        lpVault.withdraw(500e6);
        vm.stopPrank();

        assertEq(lpVault.userDeposits(alice), 500e6);
    }

    // ──────────────────────────────────────────────
    //  Referral Tests
    // ──────────────────────────────────────────────

    function test_referral_claimCommission() public {
        vm.prank(alice);
        lottery.buyTicket(10, referrer);

        uint256 balanceBefore = usdc.balanceOf(referrer);
        vm.prank(referrer);
        referralManager.claimCommission();
        uint256 balanceAfter = usdc.balanceOf(referrer);

        assertEq(balanceAfter - balanceBefore, 1e6); // 10% of $10
    }

    // ──────────────────────────────────────────────
    //  Admin Tests
    // ──────────────────────────────────────────────

    function test_pause_blocksPurchase() public {
        lottery.pause();

        vm.prank(alice);
        vm.expectRevert();
        lottery.buyTicket(1, address(0));
    }

    function test_unpause_allowsPurchase() public {
        lottery.pause();
        lottery.unpause();

        vm.prank(alice);
        lottery.buyTicket(1, address(0));
    }

    // ──────────────────────────────────────────────
    //  Full Integration Test
    // ──────────────────────────────────────────────

    function test_fullLifecycle() public {
        // 1. LP deposits
        usdc.mint(carol, 5000e6);
        vm.startPrank(carol);
        usdc.approve(address(lpVault), 5000e6);
        lpVault.deposit(5000e6);
        vm.stopPrank();

        // 2. Multiple users buy tickets to fill pot
        vm.prank(alice);
        lottery.buyTicket(500, referrer); // $500

        vm.prank(bob);
        lottery.buyTicket(500, referrer); // $500

        // Total: $1000 in tickets, $700 jackpot, $200 LP, $100 referral

        // 3. Check upkeep
        (bool needed,) = lottery.checkUpkeep("");
        assertTrue(needed);

        // 4. Perform upkeep
        lottery.performUpkeep("");

        // 5. VRF fulfills
        vrfCoordinator.fulfillRandomWords(1, address(lottery));

        // 6. Verify round settled
        (uint256 roundId,,,,) = lottery.getCurrentRound();
        assertEq(roundId, 2); // Now on round 2

        // 7. LP claims yield
        uint256 lpYield = lpVault.pendingYield(carol);
        assertEq(lpYield, 200e6); // $200

        vm.prank(carol);
        lpVault.claimYield();

        // 8. Referrer claims commission
        uint256 refCommission = referralManager.pendingCommission(referrer);
        assertEq(refCommission, 100e6); // $100

        vm.prank(referrer);
        referralManager.claimCommission();

        // 9. Winner claims prize
        (,,,,, , address grandWinner,) = lottery.rounds(1);
        uint256 winnerClaimable = lottery.claimable(1, grandWinner);
        assertTrue(winnerClaimable > 0);

        vm.prank(grandWinner);
        lottery.claimPrize(1);
    }

    // ──────────────────────────────────────────────
    //  Fuzz Tests
    // ──────────────────────────────────────────────

    function testFuzz_buyTicket_quantity(uint256 quantity) public {
        quantity = bound(quantity, 1, 500);
        usdc.mint(alice, quantity * TICKET_PRICE);

        vm.startPrank(alice);
        usdc.approve(address(lottery), quantity * TICKET_PRICE);
        lottery.buyTicket(quantity, address(0));
        vm.stopPrank();

        assertEq(lottery.getRoundTicketCount(1), quantity);
    }

    function testFuzz_winnerSelection_inBounds(uint256 randomWord) public {
        vm.prank(alice);
        lottery.buyTicket(1000, address(0));

        lottery.performUpkeep("");

        uint256[] memory words = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            words[i] = uint256(keccak256(abi.encode(randomWord, i)));
        }
        vrfCoordinator.fulfillRandomWordsWithOverride(1, address(lottery), words);

        // Should always settle without reverting
        (,,,,, bool settled,,) = lottery.rounds(1);
        assertTrue(settled);
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    function _fillPot() internal {
        // Need $700 in jackpot = $1000 in tickets (70%)
        vm.prank(alice);
        lottery.buyTicket(500, address(0));
        vm.prank(bob);
        lottery.buyTicket(500, address(0));
    }
}
