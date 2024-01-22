// SPDX-License-Identifier: GPL-2.0-only
pragma solidity =0.8.19;

library EventsLib {
    // --- Events related to staking
    event StakePositionUpdated(
        address indexed msgSender,
        address indexed user,
        uint256 lastUpdateTime,
        uint256 lastMaxLockDuration,
        uint256 stakedBalance,
        uint256 maxStakeDebt,
        uint256 portalEnergy,
        uint256 availableToWithdraw
    );

    // --- Events related to internal exchange PSM vs. portalEnergy ---
    event PortalEnergyBuyExecuted(address indexed msgSender, address indexed user, uint256 amount);
    event PortalEnergySellExecuted(address indexed msgSender, address indexed receiver, uint256 amount);

    // --- Events related to minting and burning portalEnergyToken ---
    event PortalEnergyMinted(address indexed msgSender, address recipient, uint256 amount);
    event PortalEnergyBurned(address indexed msgSender, address recipient, uint256 amount);
}
