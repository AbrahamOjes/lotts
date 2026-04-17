// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Lottery} from "../src/Lottery.sol";
import {LPVault} from "../src/LPVault.sol";
import {ReferralManager} from "../src/ReferralManager.sol";

/// @notice Deployment script for the Lotto system on Polygon.
///         Deploy order: ReferralManager → LPVault → Lottery → wire addresses.
///
/// Usage:
///   forge script script/Deploy.s.sol:DeployLotto \
///     --rpc-url $POLYGON_RPC_URL \
///     --broadcast \
///     --verify \
///     -vvvv
contract DeployLotto is Script {
    // Polygon Mainnet addresses
    address constant USDC_POLYGON = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    // Polygon Amoy testnet USDC (use a mock or Circle's testnet USDC)
    address constant USDC_AMOY = 0x41E94eb71898E8A6F6E0dC18B5478d0Fe83dE8A5;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address treasury = vm.envOr("TREASURY", deployer);

        // VRF config (set via env or defaults for Amoy testnet)
        address vrfCoordinator = vm.envAddress("VRF_COORDINATOR");
        uint256 subscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");
        bytes32 keyHash = vm.envBytes32("VRF_KEY_HASH");
        uint32 callbackGasLimit = uint32(vm.envOr("VRF_CALLBACK_GAS_LIMIT", uint256(10000000)));
        uint16 requestConfirmations = uint16(vm.envOr("VRF_REQUEST_CONFIRMATIONS", uint256(3)));

        // Lottery config
        uint256 ticketPrice = vm.envOr("TICKET_PRICE", uint256(1e6));        // $1 USDC
        uint256 drawInterval = vm.envOr("DRAW_INTERVAL", uint256(86400));    // 24 hours
        uint256 minPotForDraw = vm.envOr("MIN_POT_FOR_DRAW", uint256(100e6)); // $100 minimum

        // Determine USDC address based on chain
        address usdc;
        if (block.chainid == 137) {
            usdc = USDC_POLYGON;
        } else {
            usdc = USDC_AMOY;
        }

        console.log("Deployer:", deployer);
        console.log("Treasury:", treasury);
        console.log("USDC:", usdc);
        console.log("VRF Coordinator:", vrfCoordinator);
        console.log("Draw Interval:", drawInterval);
        console.log("Min Pot for Draw:", minPotForDraw);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy ReferralManager
        ReferralManager referralManager = new ReferralManager(usdc, treasury, deployer);
        console.log("ReferralManager deployed:", address(referralManager));

        // 2. Deploy LPVault
        LPVault lpVault = new LPVault(usdc, deployer);
        console.log("LPVault deployed:", address(lpVault));

        // 3. Deploy Lottery
        Lottery lottery = new Lottery(
            vrfCoordinator,
            usdc,
            address(lpVault),
            address(referralManager),
            ticketPrice,
            drawInterval,
            minPotForDraw,
            subscriptionId,
            keyHash,
            callbackGasLimit,
            requestConfirmations
        );
        console.log("Lottery deployed:", address(lottery));

        // 4. Wire contracts
        referralManager.setLottery(address(lottery));
        lpVault.setLottery(address(lottery));

        console.log("--- Deployment complete ---");
        console.log("Next steps:");
        console.log("1. Add Lottery as VRF consumer on subscription", subscriptionId);
        console.log("2. Register Chainlink Automation upkeep (time-based, daily draw)");
        console.log("3. Fund VRF subscription with LINK");

        vm.stopBroadcast();
    }
}
