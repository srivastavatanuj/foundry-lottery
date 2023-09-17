// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

contract Lottery is VRFConsumerBaseV2 {
    error Lottery__NotEnoughFee();
    error Lottery__TransferFailed();
    error Lottery__LotteryNotOpen();
    error Lottery__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 lotteryState
    );

    enum LotteryState {
        OPEN,
        CALCULATING
    }

    uint256 private s_enteranceFee;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    uint256 private immutable i_interval;
    address private s_recentWinner;
    LotteryState private s_lotteryState;

    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    event EnterLottery(address indexed player);
    event RequestedLotteryWinner(uint256 indexed requestId);
    event WinnerPicked(address indexed player);

    constructor(
        uint256 enterenceFee,
        uint256 interval,
        address vrfCoordinatorV2,
        bytes32 gasLane,
        uint32 callbackGasLimit,
        uint64 subscriptionId
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        s_enteranceFee = enterenceFee;
        s_lastTimeStamp = block.timestamp;
        i_interval = interval;
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        s_lotteryState = LotteryState.OPEN;
    }

    function enterLottery() external payable {
        if (msg.value < s_enteranceFee) {
            revert Lottery__NotEnoughFee();
        }

        if (s_lotteryState != LotteryState.OPEN) {
            revert Lottery__LotteryNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit EnterLottery(msg.sender);
    }

    function checkUpkeep(
        bytes memory /*checkData*/
    ) public view returns (bool upkeepNeeded, bytes memory /*performData*/) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = s_lotteryState == LotteryState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /*perform*/) external {
        (bool upKeepNeeded, ) = checkUpkeep("");
        if (!upKeepNeeded) {
            revert Lottery__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_lotteryState)
            );
        }
        s_lotteryState = LotteryState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedLotteryWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_lastTimeStamp = block.timestamp;
        s_lotteryState = LotteryState.OPEN;
        s_players = new address payable[](0);
        emit WinnerPicked(winner);
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Lottery__TransferFailed();
        }
    }

    function getEnterenceFee() external view returns (uint256) {
        return s_enteranceFee;
    }

    function getLotteryState() external view returns (LotteryState) {
        return s_lotteryState;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLengthOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
