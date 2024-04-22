// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

library EventsLib {
    event AdapterEnergyBuyExecuted(
        address indexed caller,
        address indexed recipient,
        uint256 amount
    );
    event AdapterEnergySellExecuted(
        address indexed caller,
        address indexed recipient,
        uint256 amount
    );

    // --- Events related to staking & unstaking ---
    event AdapterStaked(address indexed caller, uint256 amountStaked);
    event AdapterUnstaked(address indexed caller, uint256 amountUnstaked);

    event AdapterPositionUpdated(
        address indexed user,
        uint256 lastUpdateTime,
        uint256 lastMaxLockDuration,
        uint256 stakedBalance,
        uint256 maxStakeDebt,
        uint256 portalEnergy
    );

    // --- Events related to minting and burning PE ---

    event AdapterEnergyBurned(
        address indexed caller,
        address indexed recipient,
        uint256 amount
    );

    event AdapterEnergyMinted(
        address indexed caller,
        address indexed recipient,
        uint256 amount
    );
}
