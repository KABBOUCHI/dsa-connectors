pragma solidity ^0.7.0;

interface AaveIncentivesInterface {
    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to,
        bool stake
    ) external returns (uint256);
}