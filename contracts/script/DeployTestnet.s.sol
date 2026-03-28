// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Lottery} from "../src/Lottery.sol";
import {LPVault} from "../src/LPVault.sol";
import {ReferralManager} from "../src/ReferralManager.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

/// @notice Testnet deployment: deploys mock USDC + mock VRF + full system.
///         For Amoy with real Chainlink, use Deploy.s.sol instead.
///
/// Usage (local anvil):
///   anvil &
///   forge script script/DeployTestnet.s.sol:DeployTestnet \
///     --rpc-url http://127.0.0.1:8545 \
///     --broadcast -vvvv
contract DeployTestnet is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy mock USDC
        ERC20Mock usdc = new ERC20Mock("USD Coin", "USDC", 6);
        console.log("Mock USDC deployed:", address(usdc));

        // 2. Deploy mock VRF Coordinator
        VRFCoordinatorV2_5Mock vrfCoordinator = new VRFCoordinatorV2_5Mock(
            100000000000000000, // 0.1 LINK base fee
            1000000000,         // 1 gwei gas price
            4000000000000000    // 0.004 ETH per LINK
        );
        console.log("VRF Coordinator deployed:", address(vrfCoordinator));

        // 3. Create VRF subscription
        uint256 subId = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(subId, 1000 ether);
        console.log("VRF Subscription ID:", subId);

        // 4. Deploy ReferralManager
        ReferralManager referralManager = new ReferralManager(
            address(usdc),
            deployer, // treasury
            deployer  // owner
        );
        console.log("ReferralManager deployed:", address(referralManager));

        // 5. Deploy LPVault
        LPVault lpVault = new LPVault(address(usdc), deployer);
        console.log("LPVault deployed:", address(lpVault));

        // 6. Deploy Lottery
        Lottery lottery = new Lottery(
            address(vrfCoordinator),
            address(usdc),
            address(lpVault),
            address(referralManager),
            1e6,    // $1 ticket
            700e6,  // $700 target pot
            subId,
            bytes32(0), // keyHash (any for mock)
            500000,     // callbackGasLimit
            3           // requestConfirmations
        );
        console.log("Lottery deployed:", address(lottery));

        // 7. Wire contracts
        referralManager.setLottery(address(lottery));
        lpVault.setLottery(address(lottery));

        // 8. Add lottery as VRF consumer
        vrfCoordinator.addConsumer(subId, address(lottery));

        // 9. Mint test USDC to deployer
        usdc.mint(deployer, 100_000e6); // $100,000

        vm.stopBroadcast();

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("USDC:              ", address(usdc));
        console.log("VRF Coordinator:   ", address(vrfCoordinator));
        console.log("ReferralManager:   ", address(referralManager));
        console.log("LPVault:           ", address(lpVault));
        console.log("Lottery:           ", address(lottery));
        console.log("VRF Subscription:  ", subId);
        console.log("");
        console.log("Deployer USDC balance: 100,000");
    }
}
