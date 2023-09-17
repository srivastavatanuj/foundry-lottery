//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinatorV2,
            ,
            ,
            ,
            ,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        return createSubscription(vrfCoordinatorV2, deployerKey);
    }

    function createSubscription(
        address vrfCoordinatorV2,
        uint256 deployerKey
    ) public returns (uint64) {
        console.log("Creating subscription on Chainid: ", block.chainid);
        vm.startBroadcast(deployerKey);
        uint64 subId = VRFCoordinatorV2Mock(vrfCoordinatorV2)
            .createSubscription();
        vm.stopBroadcast();
        console.log("Your Sub Id is: ", subId);
        return subId;
    }

    function run() external returns (uint64) {
        return createSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script {
    uint96 public constant FUND_AMOUNT = 3 ether;

    function FundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinatorV2,
            ,
            ,
            uint64 subId,
            address link,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        fundSubscription(vrfCoordinatorV2, subId, link, deployerKey);
    }

    function fundSubscription(
        address vrfCoordinatorV2,
        uint64 subId,
        address link,
        uint256 deployerKey
    ) public {
        console.log("Funding Subscription", subId);
        console.log("On chainId", block.chainid);

        if (block.chainid == 31337) {
            vm.startBroadcast();
            VRFCoordinatorV2Mock(vrfCoordinatorV2).fundSubscription(
                subId,
                FUND_AMOUNT
            );
            vm.stopBroadcast();
        } else {
            vm.startBroadcast();
            LinkToken(link).transferAndCall(
                vrfCoordinatorV2,
                FUND_AMOUNT,
                abi.encode(subId)
            );

            vm.stopBroadcast();
        }
    }

    function run() external {
        FundSubscriptionUsingConfig();
    }
}

contract AddConsumer is Script {
    function addConsumer(
        address lottery,
        address vrfCoordinatorV2,
        uint64 subId,
        uint256 deployerKey
    ) public {
        console.log("Adding consumer contract: ", lottery);
        console.log("On ChainId: ", block.chainid);
        vm.startBroadcast(deployerKey);
        VRFCoordinatorV2Mock(vrfCoordinatorV2).addConsumer(subId, lottery);
        vm.stopBroadcast();
    }

    function addConsumerUsingConfig(address lottery) public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinatorV2,
            ,
            uint64 subId,
            ,
            ,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        addConsumer(lottery, vrfCoordinatorV2, subId, deployerKey);
    }

    function run() external {
        address lottery = DevOpsTools.get_most_recent_deployment(
            "Lottery",
            block.chainid
        );

        addConsumerUsingConfig(lottery);
    }
}
