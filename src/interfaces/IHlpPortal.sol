// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

interface IHlpPortal {
    function stake(uint256 _amount) external;

    function unstake(uint256 _amount) external;

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

    function maxLockDuration() external view returns (uint256 maxLockDuration);

    function lastTradeTime(
        address _address
    ) external view returns (uint256 lastTradeTime);

    function getUpdateAccount(
        address _user,
        uint256 _amount
    )
        external
        view
        returns (address, uint256, uint256, uint256, uint256, uint256, uint256);
}
