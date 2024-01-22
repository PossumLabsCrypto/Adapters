// SPDX-License-Identifier: GPL-2.0-only
pragma solidity =0.8.19;

struct Account {
    bool isExist;
    uint256 lastUpdateTime;
    uint256 lastMaxLockDuration;
    uint256 stakedBalance;
    uint256 maxStakeDebt;
    uint256 portalEnergy;
    uint256 availableToWithdraw;
}

interface IAdapter {

    function stake(address _receiver, uint256 _amount) external;

    function unstake(uint256 _amount) external;

    function forceUnstakeAll(address _receiver) external;

    function mintPortalEnergyToken(address _recipient, uint256 _amount) external;

    function burnPortalEnergyToken(address _recipient, uint256 _amount) external;

    function buyPortalEnergy(address _user, uint256 _amount, uint256 _minReceived, uint256 _deadline) external;

    function sellPortalEnergy(address _receiver, uint256 _amount, uint256 _minReceived, uint256 _deadline) external;

    function getUpdateAccount(address _user, uint256 _amount)
        external
        view
        returns (address, uint256, uint256, uint256, uint256, uint256, uint256);

    function quoteforceUnstakeAll(address _user) external view returns (uint256 portalEnergyTokenToBurn);

    function quoteBuyPortalEnergy(uint256 _amountInput) external view returns (uint256);

    function quoteSellPortalEnergy(uint256 _amountInput) external view returns (uint256);
}
