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
    address public referrer1 = makeAddr("referrer1");
    address public referrer2 = makeAddr("referrer2");

    uint256 public subscriptionId;
    uint256 public constant TICKET_PRICE = 1e6;       // $1 USDC
    uint256 public constant DRAW_INTERVAL = 86400;     // 24 hours
    uint256 public constant MIN_POT = 100e6;           // $100 min pot for draw
    uint256 public constant TOTAL_WINNERS = 34;

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
            DRAW_INTERVAL,
            MIN_POT,
            subscriptionId,
            bytes32(0), // keyHash (any for mock)
            10_000_000, // callbackGasLimit (34 winners + win-share processing)
            3           // requestConfirmations
        );

        // Wire contracts
        referralManager.setLottery(address(lottery));
        lpVault.setLottery(address(lottery));

        // Add lottery as VRF consumer
        vrfCoordinator.addConsumer(subscriptionId, address(lottery));

        // Mint USDC to test users
        usdc.mint(alice, 100_000e6);
        usdc.mint(bob, 100_000e6);
        usdc.mint(carol, 100_000e6);

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

        (uint256 roundId, uint256 prizePool, uint256 totalTickets,,) = lottery.getCurrentRound();
        assertEq(roundId, 1);
        assertEq(totalTickets, 1);
        assertEq(prizePool, 700000); // 70% of $1
    }

    function test_buyTicket_multiple() public {
        vm.prank(alice);
        lottery.buyTicket(10, address(0));

        (,, uint256 totalTickets,,) = lottery.getCurrentRound();
        assertEq(totalTickets, 10);
    }

    function test_buyTicket_feeSplit() public {
        uint256 lpVaultBefore = usdc.balanceOf(address(lpVault));

        vm.prank(alice);
        lottery.buyTicket(10, address(0)); // $10 total

        // LP gets 20% = $2
        uint256 lpVaultAfter = usdc.balanceOf(address(lpVault));
        assertEq(lpVaultAfter - lpVaultBefore, 2e6);

        // Prize pool gets 70% = $7
        (, uint256 prizePool,,,) = lottery.getCurrentRound();
        assertEq(prizePool, 7e6);

        // Referral 10% = $1 (goes to treasury since no referrer)
        assertEq(usdc.balanceOf(treasury), 1e6);
    }

    function test_buyTicket_playerTicketCount() public {
        vm.prank(alice);
        lottery.buyTicket(5, address(0));
        vm.prank(alice);
        lottery.buyTicket(3, address(0));

        assertEq(lottery.getPlayerTicketCount(1, alice), 8);
        assertEq(lottery.getPlayerTicketCount(1, bob), 0);
    }

    function test_buyTicket_revertZeroQuantity() public {
        vm.prank(alice);
        vm.expectRevert(Lottery.ZeroQuantity.selector);
        lottery.buyTicket(0, address(0));
    }

    function test_buyTicket_revertDuringDraw() public {
        _buyAndTriggerDraw();

        vm.prank(alice);
        vm.expectRevert(Lottery.DrawAlreadyInProgress.selector);
        lottery.buyTicket(1, address(0));
    }

    // ──────────────────────────────────────────────
    //  Two-Tier Referral Tests
    // ──────────────────────────────────────────────

    function test_twoTierReferral_singleTier() public {
        // Alice buys with referrer1 (no upstream for referrer1)
        vm.prank(alice);
        lottery.buyTicket(10, referrer1); // $10 total, $1 referral share

        // Tier-1 gets 80% of $1 = $0.80
        assertEq(referralManager.pendingCommission(referrer1), 800000);
        // Treasury gets remaining 20% = $0.20
        assertEq(usdc.balanceOf(treasury), 200000);
    }

    function test_twoTierReferral_twoTiers() public {
        // First: referrer1 was referred by referrer2
        // (referrer2 refers referrer1 in a separate purchase)
        usdc.mint(referrer1, 1e6);
        vm.startPrank(referrer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTicket(1, referrer2);
        vm.stopPrank();
        assertEq(referralManager.playerReferrer(referrer1), referrer2);

        // Now Alice buys with referrer1 → referrer1 is tier-1, referrer2 is tier-2
        vm.prank(alice);
        lottery.buyTicket(100, referrer1); // $100 total, $10 referral share

        // referrer1's own purchase ($1): referrer2 is tier-1, gets 80% of $0.10 = $0.08
        // Alice's purchase ($100): referrer1 is tier-1, gets 80% of $10 = $8.00
        // referrer1 total = $8.00 from alice
        assertEq(referralManager.pendingCommission(referrer1), 8_000_000);

        // referrer2: tier-1 for referrer1's $1 purchase = $0.08
        //           + tier-2 for alice's $100 purchase = 20% of $10 = $2.00
        assertEq(referralManager.pendingCommission(referrer2), 80_000 + 2_000_000);
    }

    function test_twoTierReferral_stickyPersists() public {
        // First purchase with referrer
        vm.prank(alice);
        lottery.buyTicket(1, referrer1);
        assertEq(referralManager.playerReferrer(alice), referrer1);

        // Second purchase without referrer — sticky kicks in
        vm.prank(alice);
        lottery.buyTicket(1, address(0));

        // referrer1 should have commission from both purchases
        // Each $1 purchase gives $0.10 referral, 80% = $0.08 per purchase = $0.16 total
        assertEq(referralManager.pendingCommission(referrer1), 160_000);
    }

    function test_twoTierReferral_selfReferralBlocked() public {
        // Alice tries to refer herself
        vm.prank(alice);
        lottery.buyTicket(10, alice);

        // No referrer set, treasury gets all
        assertEq(referralManager.playerReferrer(alice), address(0));
        assertEq(usdc.balanceOf(treasury), 1e6); // Full $1 referral share
    }

    // ──────────────────────────────────────────────
    //  Daily Draw Tests
    // ──────────────────────────────────────────────

    function test_checkUpkeep_beforeDrawTime() public {
        _buyTickets(alice, 200); // $200 → $140 prize pool > $100 min

        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded); // Draw time not reached
    }

    function test_checkUpkeep_afterDrawTime() public {
        _buyTickets(alice, 200);
        vm.warp(block.timestamp + DRAW_INTERVAL);

        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertTrue(upkeepNeeded);
    }

    function test_checkUpkeep_belowMinPot() public {
        _buyTickets(alice, 10); // $10 → $7 prize pool < $100 min
        vm.warp(block.timestamp + DRAW_INTERVAL);

        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function test_performUpkeep_revertBeforeDrawTime() public {
        _buyTickets(alice, 200);

        vm.expectRevert(Lottery.DrawNotReady.selector);
        lottery.performUpkeep("");
    }

    function test_performUpkeep_requestsVRF() public {
        _buyTickets(alice, 200);
        vm.warp(block.timestamp + DRAW_INTERVAL);

        lottery.performUpkeep("");

        (,,,, bool drawInProgress) = lottery.getCurrentRound();
        assertTrue(drawInProgress);
    }

    function test_timeUntilDraw() public {
        uint256 remaining = lottery.timeUntilDraw();
        assertTrue(remaining > 0 && remaining <= DRAW_INTERVAL);

        vm.warp(block.timestamp + DRAW_INTERVAL);
        assertEq(lottery.timeUntilDraw(), 0);
    }

    // ──────────────────────────────────────────────
    //  Multi-Tier Prize Distribution Tests
    // ──────────────────────────────────────────────

    function test_fullDraw_34Winners() public {
        _buyTickets(alice, 500);
        _buyTickets(bob, 500);
        vm.warp(block.timestamp + DRAW_INTERVAL);

        lottery.performUpkeep("");

        // Generate 34 random words
        uint256[] memory words = _makeRandomWords(34, 42);
        vrfCoordinator.fulfillRandomWordsWithOverride(1, address(lottery), words);

        // Round settled, advanced to round 2
        (uint256 roundId,,,,) = lottery.getCurrentRound();
        assertEq(roundId, 2);

        (,,,,, bool settled,,) = lottery.rounds(1);
        assertTrue(settled);

        // Check 34 winners recorded
        (address[] memory winners, uint256[] memory prizes, uint256[] memory tierIndices) = lottery.getRoundWinners(1);
        assertEq(winners.length, TOTAL_WINNERS);
        assertEq(prizes.length, TOTAL_WINNERS);
        assertEq(tierIndices.length, TOTAL_WINNERS);

        // Grand winner is tier 0
        assertEq(tierIndices[0], 0);
        assertTrue(winners[0] == alice || winners[0] == bob);
    }

    function test_fullDraw_prizeAmounts() public {
        // $1000 in tickets → $700 prize pool
        _buyTickets(alice, 1000);
        vm.warp(block.timestamp + DRAW_INTERVAL);

        lottery.performUpkeep("");

        uint256[] memory words = _makeRandomWords(34, 123);
        vrfCoordinator.fulfillRandomWordsWithOverride(1, address(lottery), words);

        // Grand prize = 40% of $700 = $280, minus 10% win-share = $252
        (,,,,,, address grandWinner, uint256 grandPrize) = lottery.rounds(1);
        assertEq(grandWinner, alice); // All tickets are alice's
        assertEq(grandPrize, 252e6);  // $280 - 10% = $252

        // Total claimable for alice should be ~90% of prize pool (10% win-share)
        // Small rounding differences expected from integer division across 8 tiers
        uint256 aliceClaimable = lottery.claimable(1, alice);
        assertApproxEqAbs(aliceClaimable, 630e6, 100); // within 100 USDC-wei
    }

    function test_fullDraw_winShareDistribution() public {
        // referrer1 referred alice
        vm.prank(alice);
        lottery.buyTicket(1, referrer1); // Set sticky referrer

        // Now alice buys more tickets
        _buyTickets(alice, 999);
        vm.warp(block.timestamp + DRAW_INTERVAL);

        lottery.performUpkeep("");

        uint256[] memory words = _makeRandomWords(34, 777);
        vrfCoordinator.fulfillRandomWordsWithOverride(1, address(lottery), words);

        // Win-share = ~10% of $700 prize pool = ~$70 total
        // All goes to referrer1's chain (referrer1 is tier-1, no tier-2)
        // Small rounding from integer division across 8 tiers
        uint256 refWinShare = referralManager.totalWinShare(referrer1);
        assertApproxEqAbs(refWinShare, 70e6, 100); // within 100 USDC-wei
    }

    // ──────────────────────────────────────────────
    //  Prize Claim Tests
    // ──────────────────────────────────────────────

    function test_claimPrize() public {
        _buyTickets(alice, 1000);
        vm.warp(block.timestamp + DRAW_INTERVAL);

        lottery.performUpkeep("");

        uint256[] memory words = _makeRandomWords(34, 0);
        vrfCoordinator.fulfillRandomWordsWithOverride(1, address(lottery), words);

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
        _buyTickets(alice, 1000);
        vm.warp(block.timestamp + DRAW_INTERVAL);
        lottery.performUpkeep("");

        uint256[] memory words = _makeRandomWords(34, 0);
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
        usdc.mint(alice, 1000e6);
        vm.startPrank(alice);
        usdc.approve(address(lpVault), 1000e6);
        lpVault.deposit(1000e6);
        vm.stopPrank();

        // Bob buys $100 in tickets → $20 LP yield
        _buyTickets(bob, 100);

        uint256 pending = lpVault.pendingYield(alice);
        assertEq(pending, 20e6);

        vm.prank(alice);
        lpVault.claimYield();
        assertEq(lpVault.pendingYield(alice), 0);
    }

    function test_lpVault_multipleDepositors() public {
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

        _buyTickets(bob, 100); // $20 LP yield

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

    function test_setDrawInterval() public {
        lottery.setDrawInterval(3600); // 1 hour
        assertEq(lottery.drawInterval(), 3600);
    }

    function test_setMinPotForDraw() public {
        lottery.setMinPotForDraw(500e6);
        assertEq(lottery.minPotForDraw(), 500e6);
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

        // 2. Set up two-tier referral chain: referrer2 → referrer1 → alice
        usdc.mint(referrer1, 10e6);
        vm.startPrank(referrer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTicket(1, referrer2);
        vm.stopPrank();

        // 3. Alice and Bob buy tickets
        vm.prank(alice);
        lottery.buyTicket(500, referrer1);
        vm.prank(bob);
        lottery.buyTicket(500, referrer1);
        // Total: ~$1001 in tickets, ~$700 prize pool, ~$200 LP, ~$100 referral

        // 4. Warp to draw time
        vm.warp(block.timestamp + DRAW_INTERVAL);

        // 5. Check upkeep
        (bool needed,) = lottery.checkUpkeep("");
        assertTrue(needed);

        // 6. Perform upkeep
        lottery.performUpkeep("");

        // 7. VRF fulfills
        uint256[] memory words = _makeRandomWords(34, 999);
        vrfCoordinator.fulfillRandomWordsWithOverride(1, address(lottery), words);

        // 8. Verify round settled, now on round 2
        (uint256 roundId,,,,) = lottery.getCurrentRound();
        assertEq(roundId, 2);

        // 9. LP claims yield
        uint256 lpYield = lpVault.pendingYield(carol);
        assertTrue(lpYield > 0);
        vm.prank(carol);
        lpVault.claimYield();

        // 10. Referrer1 claims commission (purchase fees + win-share)
        uint256 ref1Commission = referralManager.pendingCommission(referrer1);
        assertTrue(ref1Commission > 0);
        vm.prank(referrer1);
        referralManager.claimCommission();

        // 11. Referrer2 claims commission (tier-2 earnings)
        uint256 ref2Commission = referralManager.pendingCommission(referrer2);
        assertTrue(ref2Commission > 0);
        vm.prank(referrer2);
        referralManager.claimCommission();

        // 12. Winner claims prize
        (,,,,,, address grandWinner,) = lottery.rounds(1);
        uint256 winnerClaimable = lottery.claimable(1, grandWinner);
        assertTrue(winnerClaimable > 0);

        vm.prank(grandWinner);
        lottery.claimPrize(1);
    }

    // ──────────────────────────────────────────────
    //  Multi-Round Test
    // ──────────────────────────────────────────────

    function test_multipleRounds() public {
        // Round 1
        _buyTickets(alice, 200);
        vm.warp(block.timestamp + DRAW_INTERVAL);
        lottery.performUpkeep("");
        uint256[] memory words1 = _makeRandomWords(34, 1);
        vrfCoordinator.fulfillRandomWordsWithOverride(1, address(lottery), words1);

        (uint256 roundId1,,,,) = lottery.getCurrentRound();
        assertEq(roundId1, 2);

        // Round 2
        _buyTickets(bob, 200);
        vm.warp(block.timestamp + DRAW_INTERVAL);
        lottery.performUpkeep("");
        uint256[] memory words2 = _makeRandomWords(34, 2);
        vrfCoordinator.fulfillRandomWordsWithOverride(2, address(lottery), words2);

        (uint256 roundId2,,,,) = lottery.getCurrentRound();
        assertEq(roundId2, 3);

        // Both rounds settled
        (,,,,, bool settled1,,) = lottery.rounds(1);
        (,,,,, bool settled2,,) = lottery.rounds(2);
        assertTrue(settled1);
        assertTrue(settled2);
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
        assertEq(lottery.getPlayerTicketCount(1, alice), quantity);
    }

    function testFuzz_winnerSelection_inBounds(uint256 seed) public {
        _buyTickets(alice, 1000);
        vm.warp(block.timestamp + DRAW_INTERVAL);

        lottery.performUpkeep("");

        uint256[] memory words = _makeRandomWords(34, seed);
        vrfCoordinator.fulfillRandomWordsWithOverride(1, address(lottery), words);

        (,,,,, bool settled,,) = lottery.rounds(1);
        assertTrue(settled);

        (address[] memory winners,,) = lottery.getRoundWinners(1);
        assertEq(winners.length, TOTAL_WINNERS);
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    function _buyTickets(address buyer, uint256 quantity) internal {
        vm.prank(buyer);
        lottery.buyTicket(quantity, address(0));
    }

    function _buyAndTriggerDraw() internal {
        _buyTickets(alice, 200);
        vm.warp(block.timestamp + DRAW_INTERVAL);
        lottery.performUpkeep("");
    }

    function _makeRandomWords(uint256 count, uint256 seed) internal pure returns (uint256[] memory) {
        uint256[] memory words = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            words[i] = uint256(keccak256(abi.encode(seed, i)));
        }
        return words;
    }
}
