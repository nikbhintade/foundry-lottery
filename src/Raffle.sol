// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title A raffle contract
 * @author cyfrin - just following along
 * @notice This contract is for creating a simple raffle
 * @dev Implements chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /* Errors */
    // just to make erros more readable errors are written
    // in following structure
    // error CONTRACTNAME_CUSTOMERROR();
    error Reffle__SendMoreToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 balance,
        uint256 playersLength,
        uint256 raffleState
    );

    /* Type Declaration */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /* State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    VRFConsumerBaseV2Plus private immutable i_vrfCoordinator;
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address private s_recentWinner;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    RaffleState private s_raffleState;

    /* Events */
    // indexed topics cost more gas than non-indexed one
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    // if topic is not indexed then you need ABI to decode in
    // it so if we want to make it very gas efficient we can
    // just not index any topic and provide ABI for it so
    // users or explorers can decode it themselves

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gaslane,
        uint256 subscriptionId,
        uint32 gasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFConsumerBaseV2Plus(vrfCoordinator);
        i_keyHash = gaslane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = gasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN; // == RaffleState(0);
    }

    // external functions are more gas efficient than public in this case.
    // as we are only user are going to call it, this can have visibility
    // external instead of public
    // there are also tools that tells if you need to use public or external
    // as the visibility
    function enterRaffle() external payable {
        // line below is not gas efficient due to it returning string
        // require(msg.value >= i_entranceFee, "Not enought ETH sent!");

        // from v0.8.26 with via-ir, custom errors can be uses with
        // require but as this contract doesn't use it we can't use it here

        // right now, custom errors with conditionals is the way to go and
        // gas efficient
        if (msg.value < i_entranceFee) {
            revert Reffle__SendMoreToEnterRaffle();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev This is the function that the chainlink nodes will call to ses
     * if the lottery is ready to have winner picked.
     * The following should be true in order for upkeepNeeded to be true:
     * 1. The time interval has passed between raffle runs
     * 2. The lottery is open.
     * 3. The contract has ETH
     * 4. Implicitly, your subscription has LINK.
     * @param - ignored
     * @return upkeepNeeded - trye if it's time to restart the lottery
     * @return - ignored
     */

    function checkUpkeep(
        bytes memory /* calldata*/
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >=
            i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, hex"");
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) external returns (uint256 requestId) {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING; // == RaffleState(1);

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        requestId = s_vrfCoordinator.requestRandomWords(request);
    }

    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] calldata randomWords
    ) internal virtual override {
        // checks

        // effects
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;

        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;

        emit WinnerPicked(s_recentWinner);

        // interactions
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /** Getter Function */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }
}
