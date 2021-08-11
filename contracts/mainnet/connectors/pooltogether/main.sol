pragma solidity ^0.7.0;

/**
 * @title PoolTogether
 * @dev Deposit & Withdraw from PoolTogether
 */

 import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
 import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
 import { PrizePoolInterface, TokenFaucetInterface, TokenFaucetProxyFactoryInterface } from "./interface.sol";

import { TokenInterface } from "../../common/interfaces.sol";
import { Events } from "./events.sol";
import { DSMath } from "../../common/math.sol";
import { Basic } from "../../common/basic.sol";

abstract contract PoolTogetherResolver is Events, DSMath, Basic {
    using SafeERC20 for IERC20;

    /**
     * @dev Deposit into Prize Pool
     * @notice Deposit a token into a prize pool
     * @param prizePool PrizePool address to deposit to
     * @param to Address to whom the controlled tokens should be minted
     * @param amount The amount of the underlying asset the user wishes to deposit. The Prize Pool contract should have been pre-approved by the caller to transfer the underlying ERC20 tokens.
     * @param controlledToken The address of the token that they wish to mint. For our default Prize Strategy this will either be the Ticket address or the Sponsorship address.  Those addresses can be looked up on the Prize Strategy.
     * @param referrer The address that should receive referral awards, if any.
     * @param getId Get token amount at this ID from `InstaMemory` Contract.
     * @param setId Set token amount at this ID in `InstaMemory` Contract.
    */

    function depositTo(
        address prizePool,
        address to,
        uint256 amount,
        address controlledToken,
        address referrer,
        uint256 getId,
        uint256 setId
    ) external returns ( string memory _eventName, bytes memory _eventParam) {
        uint _amount = getUint(getId, amount);

        PrizePoolInterface prizePoolContract = PrizePoolInterface(prizePool);
        address prizePoolToken = prizePoolContract.token();

        // Approve prizePool
        TokenInterface tokenContract = TokenInterface(prizePoolToken);
        tokenContract.approve(prizePool, _amount);

        prizePoolContract.depositTo(to, _amount, controlledToken, referrer);

        setUint(setId, _amount);

        _eventName = "LogDepositTo(address,address,uint256,address,address,uint256, uint256)";
        _eventParam = abi.encode(address(prizePool), address(to), _amount, address(controlledToken), address(referrer), getId, setId);
    }

    /**
     * @dev Withdraw from Prize Pool
     * @notice Withdraw a token from a prize pool
     * @param prizePool PrizePool address to deposit to
     * @param from The address to withdraw from. This means you can withdraw on another user's behalf if you have an allowance for the controlled token.
     * @param amount THe amount to withdraw
     * @param controlledToken The controlled token to withdraw from.
     * @param maximumExitFee The maximum early exit fee the caller is willing to pay. This prevents the Prize Strategy from changing the fee on the fly.
     * @param getId Get token amount at this ID from `InstaMemory` Contract.
     * @param setId Set token amount at this ID in `InstaMemory` Contract.
    */

    function withdrawInstantlyFrom (
        address prizePool,
        address from,
        uint256 amount,
        address controlledToken,
        uint256 maximumExitFee,
        uint256 getId,
        uint256 setId
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        uint _amount = getUint(getId, amount);

        PrizePoolInterface prizePoolContract = PrizePoolInterface(prizePool);

        prizePoolContract.withdrawInstantlyFrom(from, _amount, controlledToken, maximumExitFee);

        setUint(setId, _amount);

        _eventName = "LogWithdrawInstantlyFrom(address,address,uint256,address,uint256,uint256,uint256)";
        _eventParam = abi.encode(address(prizePool), address(from), _amount, address(controlledToken), maximumExitFee, getId, setId);
    }

    /**
     * @dev Claim token from a Token Faucet
     * @notice Claim token from a Token Faucet
     * @param tokenFaucet TokenFaucet address
     * @param user The user to claim tokens for
    */
    function claim (
        address tokenFaucet,
        address user
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        TokenFaucetInterface tokenFaucetContract = TokenFaucetInterface(tokenFaucet);

        tokenFaucetContract.claim(user);

        _eventName = "LogClaim(address,address)";
        _eventParam = abi.encode(address(tokenFaucet), address(user));
    }

    /**
     * @dev Runs claim on all passed comptrollers for a user.
     * @notice Runs claim on all passed comptrollers for a user.
     * @param tokenFaucetProxyFactory The TokenFaucetProxyFactory address
     * @param user The user to claim tokens for
     * @param tokenFaucets The tokenFaucets to call claim on.
    */
    function claimAll (
        address tokenFaucetProxyFactory,
        address user,
        TokenFaucetInterface[] calldata tokenFaucets
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        TokenFaucetProxyFactoryInterface tokenFaucetProxyFactoryContract = TokenFaucetProxyFactoryInterface(tokenFaucetProxyFactory);

        tokenFaucetProxyFactoryContract.claimAll(user, tokenFaucets);

        _eventName = "LogClaimAll(address,address,TokenFaucetInterface[])";
        _eventParam = abi.encode(address(tokenFaucetProxyFactory), address(user), tokenFaucets);
    }
}

contract ConnectV2PoolTogether is PoolTogetherResolver {
    string public constant name = "PoolTogether-v1";
}