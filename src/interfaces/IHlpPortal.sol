// SPDX-License-Identifier: GPL-2.0-only
pragma solidity =0.8.19;

interface IHlpPortal {
    function stake(uint256 _amount) external;

    function unstake(uint256 _amount) external;

    function forceUnstakeAll() external;

    function buyPortalEnergy(
        uint256 _amountInput,
        uint256 _minReceived,
        uint256 _deadline
    ) external;

    function sellPortalEnergy(
        uint256 _amountInput,
        uint256 _minReceived,
        uint256 _deadline
    ) external;

    function quoteBuyPortalEnergy(
        uint256 _amountInput
    ) external view returns (uint256);

    function quoteSellPortalEnergy(
        uint256 _amountInput
    ) external view returns (uint256);

    function mintPortalEnergyToken(
        address _recipient,
        uint256 _amount
    ) external;

    function burnPortalEnergyToken(
        address _recipient,
        uint256 _amount
    ) external;

    function getUpdateAccount(
        address _user,
        uint256 _amount
    )
        external
        view
        returns (
            address user,
            uint256 lastUpdateTime,
            uint256 lastMaxLockDuration,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy,
            uint256 availableToWithdraw
        );

    function quoteforceUnstakeAll(
        address _user
    ) external view returns (uint256 portalEnergyTokenToBurn);

    function maxLockDuration() external view returns (uint256 maxLockDuration);

    function lastTradeTime(
        address _address
    ) external view returns (uint256 lastTradeTime);
}
