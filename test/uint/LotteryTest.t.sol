//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {Lottery} from "../../src/Lottery.sol";
import {DeployLottery} from "../../script/DeployLottery.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract LotteryTest is Test {
    event EnterLottery(address indexed player);

    Lottery lottery;
    HelperConfig helperConfig;

    uint256 enterenceFee;
    uint256 interval;
    address vrfCoordinatorV2;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint64 subscriptionId;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployLottery deployer = new DeployLottery();
        (lottery, helperConfig) = deployer.run();
        (
            enterenceFee,
            interval,
            vrfCoordinatorV2,
            gasLane,
            callbackGasLimit,
            subscriptionId,
            link,

        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testLotteryInitializesInOpenState() public view {
        assert(lottery.getLotteryState() == Lottery.LotteryState.OPEN);
    }

    function testLotteryWhenYouDontPayEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Lottery.Lottery__NotEnoughFee.selector);
        lottery.enterLottery();
    }

    function testLotteryRecordsWhenPlayerEnter() public {
        vm.prank(PLAYER);
        lottery.enterLottery{value: enterenceFee}();
        address playerRecorded = lottery.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testLotteryEmitsEventOnEnterance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(lottery));
        emit EnterLottery(PLAYER);
        lottery.enterLottery{value: enterenceFee}();
    }

    function testLotteryCantEnterLotteryWhenCalculating() public {
        vm.prank(PLAYER);
        lottery.enterLottery{value: enterenceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        lottery.performUpkeep("");
        vm.expectRevert(Lottery.Lottery__LotteryNotOpen.selector);
        vm.prank(PLAYER);
        lottery.enterLottery{value: enterenceFee}();
    }

    // ChainUpKeep

    function testLotteryCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        vm.prank(PLAYER);
        vm.expectRevert(Lottery.Lottery__NotEnoughFee.selector);
        lottery.enterLottery();
    }

    function testLotteryCheckUpKeepReturnsFalseIfLotteryNotOpen() public {
        vm.prank(PLAYER);
        lottery.enterLottery{value: enterenceFee}();
        vm.warp(block.timestamp + 1 + interval);
        vm.roll(block.number + 1);

        lottery.performUpkeep("");
        (bool upkeepNeeded, ) = lottery.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testLotteryCheckUpKeepReturnsFalseIfEnoughTimeNotPassed() public {
        vm.prank(PLAYER);
        lottery.enterLottery{value: enterenceFee}();
        vm.warp(block.timestamp - 1 + interval);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = lottery.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testLotteryCheckUpKeepReturnsTrueIfAllConditionTrue() public {
        vm.prank(PLAYER);
        lottery.enterLottery{value: enterenceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = lottery.checkUpkeep("");
        assert(upkeepNeeded);
    }

    //performUpkeep

    function testLotteryPerformUpkeepRunIfCheckUpkeepIsTrue() public {
        vm.prank(PLAYER);
        lottery.enterLottery{value: enterenceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        lottery.performUpkeep("");
    }

    function testLotteryPerformUpkeepRevertIfCheckUpkeepIsFalse() public {
        uint256 currentBalance = address(lottery).balance;
        uint256 numPlayers = 0;
        Lottery.LotteryState lstate = lottery.getLotteryState();
        vm.expectRevert(
            abi.encodeWithSelector(
                Lottery.Lottery__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                lstate
            )
        );
        lottery.performUpkeep("");
    }

    function testLotteryPerformUpkeepEmitRequestIdAndChangeLotteryState()
        public
    {
        vm.prank(PLAYER);
        lottery.enterLottery{value: enterenceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        vm.recordLogs();
        lottery.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Lottery.LotteryState lotteryState = lottery.getLotteryState();

        assert(uint(lotteryState) == 1);
        assert(uint256(requestId) > 0);
    }

    //fulfillRandomWords

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    modifier lotteryEntered() {
        vm.prank(PLAYER);
        lottery.enterLottery{value: enterenceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerUpKeep(
        uint256 ransomRequestId
    ) public lotteryEntered skipFork {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(
            ransomRequestId,
            address(lottery)
        );
    }

    function testFulfillRandomWordsPicksWinnerResetsAndSendsMoney()
        public
        lotteryEntered
        skipFork
    {
        uint256 startingIndex = 1;
        uint256 additionalPlayers = 5;

        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalPlayers;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, 1 ether);
            lottery.enterLottery{value: enterenceFee}();
        }

        uint256 prize = enterenceFee * (additionalPlayers + 1);

        vm.recordLogs();
        lottery.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimeStamp = lottery.getLastTimeStamp();

        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(
            uint256(requestId),
            address(lottery)
        );

        assert(uint256(lottery.getLotteryState()) == 0);
        assert(lottery.getRecentWinner() != address(0));
        assert(lottery.getLengthOfPlayers() == 0);
        assert(
            lottery.getRecentWinner().balance == 1 ether + prize - enterenceFee
        );
    }
}
