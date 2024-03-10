// SPDX-License-Identifier: GPL-2.0-only
pragma solidity =0.8.19;

// ============================================
// ==           PE ERC20 MANAGEMENT          ==
// ============================================

function mintPortalEnergyToken(address _recipient, uint256 _amount) external {
    /// @dev Rely on input validation from Portal

    /// @dev Get the current state of the user stake
    (
        address user,
        ,
        ,
        uint256 stakedBalance,
        uint256 maxStakeDebt,
        uint256 portalEnergy,

    ) = getUpdateAccount(msg.sender, 0, true);

    /// @dev Check that the caller has sufficient portalEnergy to mint the amount of portalEnergyToken
    if (portalEnergy < _amount) {
        revert ErrorsLib.InsufficientBalance();
    }

    /// @dev Reduce the portalEnergy of the caller by the amount of minted tokens
    portalEnergy -= _amount;

    /// @dev Update the user stake struct
    _updateAccount(user, stakedBalance, maxStakeDebt, portalEnergy);

    /// @dev Mint portal energy tokens to the recipient's wallet
    PORTAL.mintPortalEnergyToken(_recipient, _amount);
}

function burnPortalEnergyToken(address _recipient, uint256 _amount) external {
    /// @dev Check for zero value inputs
    if (_amount == 0) {
        revert ErrorsLib.InvalidAmount();
    }
    if (_recipient == address(0)) {
        revert ErrorsLib.InvalidAddress();
    }

    /// @dev Increase the portalEnergy of the recipient (in Adapter) by the amount of portalEnergyToken burned
    accounts[_recipient].portalEnergy += _amount;

    /// @dev Burn portalEnergyToken from the caller's wallet
    IERC20(address(portalEnergyToken)).safeTransferFrom(
        msg.sender,
        address(this),
        _amount
    );
    PORTAL.burnPortalEnergyToken(address(this), _amount);
}

// ============================================
// ==         RAMSES LP MANAGEMENT           ==
// ============================================

function addLiquidityWETH(
    address _receiver,
    uint256 _amountPSMDesired,
    uint256 _amountWETHDesired,
    uint256 _amountPSMMin,
    uint256 _amountWETHMin,
    uint256 _deadline
)
    external
    nonReentrant
    returns (uint256 amountPSM, uint256 amountWETH, uint256 liquidity)
{
    /// @dev validated input arguments
    if (_receiver == address(0)) revert ErrorsLib.InvalidAddress();

    (amountPSM, amountWETH) = _addLiquidity(
        _amountPSMDesired,
        _amountWETHDesired,
        _amountPSMMin,
        _amountWETHMin
    );
    address pair = RAMSES_FACTORY.getPair(
        PSM_TOKEN_ADDRESS,
        WETH_ADDRESS,
        false
    );
    PSM.safeTransferFrom(msg.sender, pair, amountPSM);
    WETH.safeTransferFrom(msg.sender, pair, amountWETH);
    liquidity = IRamsesPair(pair).mint(_receiver);
}

function addLiquidityETH(
    address _receiver,
    uint256 _amountPSMDesired,
    uint256 _amountPSMMin,
    uint256 _amountETHMin,
    uint256 _deadline
)
    external
    payable
    nonReentrant
    returns (uint256 amountPSM, uint256 amountETH, uint256 liquidity)
{
    /// @dev validated input arguments
    if (_receiver == address(0)) revert ErrorsLib.InvalidAddress();

    (amountPSM, amountETH) = _addLiquidity(
        _amountPSMDesired,
        msg.value,
        _amountPSMMin,
        _amountETHMin
    );
    address pair = RAMSES_FACTORY.getPair(
        PSM_TOKEN_ADDRESS,
        WETH_ADDRESS,
        false
    );

    IWETH(WETH_ADDRESS).deposit{value: amountETH}();

    PSM.safeTransferFrom(msg.sender, pair, amountPSM);
    WETH.safeTransfer(pair, amountETH);
    liquidity = IRamsesPair(pair).mint(_receiver);
    // refund dust eth, if any
    if (msg.value > amountETH) {
        (bool success, ) = msg.sender.call{value: msg.value - amountETH}(
            new bytes(0)
        );
        if (!success) revert ErrorsLib.FailedToSendNativeToken();
    }
}

function removeLiquidityWETH(
    address _receiver,
    uint256 _liquidity,
    uint256 _amountPSMMin,
    uint256 _amountWETHMin,
    uint256 _deadline
) public nonReentrant returns (uint256 amountPSM, uint256 amountWETH) {
    /// @dev validated input arguments
    if (_receiver == address(0)) revert ErrorsLib.InvalidAddress();

    address pair = RAMSES_FACTORY.getPair(
        PSM_TOKEN_ADDRESS,
        WETH_ADDRESS,
        false
    );
    IERC20(pair).safeTransferFrom(msg.sender, pair, _liquidity); // send liquidity to pair
    (amountPSM, amountWETH) = IRamsesPair(pair).burn(_receiver);
    if (_amountPSMMin >= amountPSM) revert ErrorsLib.InsufficientReceived();
    if (_amountWETHMin >= amountWETH) revert ErrorsLib.InsufficientReceived();
}

function removeLiquidityETH(
    address _receiver,
    uint256 _liquidity,
    uint256 _amountPSMMin,
    uint256 _amountETHMin,
    uint256 _deadline
) external returns (uint256 amountPSM, uint256 amountETH) {
    (amountPSM, amountETH) = removeLiquidityWETH(
        address(this),
        _liquidity,
        _amountPSMMin,
        _amountETHMin,
        _deadline
    );
    IWETH(WETH_ADDRESS).withdrawTo(_receiver, amountETH);
    PSM.safeTransfer(_receiver, amountPSM);
}
