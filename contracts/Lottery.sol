// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

// external contracts
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.6/vendor/SafeMathChainlink.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/VRFConsumerBase.sol";

contract Lottery is VRFConsumerBase, Ownable {
    using SafeMathChainlink for uint256;
    address payable[] public players;
    address payable public recentWinner;
    uint256 public randomness;
    uint256 public usdEntryFee;
    AggregatorV3Interface internal ethUsdPriceFeed;

    // enum allows switching state between open, closed, and calculating winner
    enum LOTTERY_STATE {
        OPEN,
        CLOSED,
        CALCULATING_WINNER
    }

    LOTTERY_STATE public lottery_state;
    uint256 public fee;
    bytes32 public keyhash;

    constructor(
        address _priceFeedAddress,
        address _vrfCoordinator,
        address _link,
        uint256 _fee,
        bytes32 _keyhash
    ) public VRFConsumerBase(_vrfCoordinator, _link) {
        usdEntryFee = 50 * (10**18);
        ethUsdPriceFeed = AggregatorV3Interface(_priceFeedAddress);
        lottery_state = LOTTERY_STATE.CLOSED;
        fee = _fee;
        keyhash = _keyhash;
    }

    function enter() public payable {
        // change lottery state
        require(lottery_state == LOTTERY_STATE.OPEN);
        // value of lottery must be >= entrance fee
        require((msg.value) >= getEntranceFee(), "Not Enough ETH");
        // append senders address to players array
        players.push(msg.sender);
    }

    function getEntranceFee() public view returns (uint256) {
        (, int256 price, , , ) = ethUsdPriceFeed.latestRoundData();
        // since value cannot have decimal points, multiply to 10 ** 18
        uint256 adjustedPrice = uint256(price) * (10**18);
        // cost to enter is entry fee / price of ETH/USD
        uint256 costToEnter = (usdEntryFee * 10**18) / adjustedPrice;
        return costToEnter;
    }

    function startLottery() public onlyOwner {
        // require lottery state to be closed before opening up
        require(
            lottery_state == LOTTERY_STATE.CLOSED,
            "Can't start lottery yet"
        );
        // change lottery state
        lottery_state = LOTTERY_STATE.OPEN;
    }

    function endLottery() public onlyOwner {
        // change lottery state
        lottery_state = LOTTERY_STATE.CALCULATING_WINNER;
        // request CHAINLINK VRF random
        requestRandomness(keyhash, fee);
    }
    function fulfillRandomness(bytes32 _requestId, uint256 _randomness) internal override {
        // require lottery state to calculating winner
        require(lottery_state == LOTTERY_STATE.CALCULATING_WINNER, "You are not there yet!");
        // require request random to be called, so randomness value is != 0
        require(_randomness > 0, "random-not-found");
        // find the winner address
        // modulo wraps the random value to number of players
        uint256 indexOfWinner = _randomness % players.length;
        recentWinner = players[indexOfWinner];
        // transfer balance to winner address
        recentWinner.transfer(address(this).balance);
        // new resets the value
        players = new address payable[](0);
        // change state of lottery
        lottery_state = LOTTERY_STATE.CLOSED;
        // keeps track of random number
        randomness = _randomness;
    }
}
