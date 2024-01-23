// SPDX-License-Identifier: GPL-2.0-only
pragma solidity =0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IHlpPortal} from "./interfaces/IHlpPortal.sol";
import {IAdapter, Account} from "./interfaces/IAdapter.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {IOneInchV5AggregationRouter, SwapDescription} from "./interfaces/IOneInchV5AggregationRouter.sol";
import "./libraries/ConstantsLib.sol";

contract Adapter is ReentrancyGuard {
    IHlpPortal constant _HLP_PORTAL = IHlpPortal(HLP_PORTAL_ADDRESS); // Portal
    IERC20 constant _PSM_TOKEN = IERC20(PSM_TOKEN_ADDRESS); // the ERC20 representation of PSM token
    IERC20 constant _ENERGY_TOKEN = IERC20(ENERGY_TOKEN_ADDRESS); // the ERC20 representation of portalEnergy
    IERC20 constant _HLP_TOKEN = IERC20(HLP_TOKEN_ADDRESS); // the ERC20 representation of principal token
    IOneInchV5AggregationRouter constant _ONE_INCH_V5_AGGREGATION_ROUTER_CONTRACT =
    IOneInchV5AggregationRouter(ONE_INCH_V5_AGGREGATION_ROUTER_CONTRACT_ADDRESS); // Interface of 1inch

    uint256 public totalPrincipalStaked; // shows how much principal is staked by all users combined

    mapping(address => Account) public accounts; // Associate users with their stake position

    constructor() {}

    modifier existingAccount(address _user) {
        if(!accounts[_user].isExist) revert ErrorsLib.AccountDoesNotExist();
        _;
    }

    using SafeERC20 for IERC20;

    // ============================================
    // ==           STAKING & UNSTAKING          ==
    // ============================================
    /// @notice Update user data to the current state
    /// @dev This function updates the user data to the current state
    /// @dev It calculates the accrued portalEnergy since the last update
    /// @dev It calculates the added portalEnergy due to increased stake balance
    /// @dev It updates the last update time stamp
    /// @dev It updates the user's staked balance
    /// @dev It updates the user's maxStakeDebt
    /// @dev It updates the user's portalEnergy
    /// @dev It updates the amount available to unstake
    /// @param _user The user whose data is to be updated
    /// @param _amount The amount to be added to the user's staked balance
    function _updateAccount(address _user, uint256 _amount) internal view returns (Account memory user) {
        /// @dev catch maxLockDuration from portal
        uint256 maxLockDuration = _HLP_PORTAL.maxLockDuration();

        Account memory account = accounts[_user];

        /// @dev Calculate the accrued portalEnergy since the last update
        uint256 portalEnergyEarned = (account.stakedBalance * (block.timestamp - account.lastUpdateTime) * WAD)
            / (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT);

        /// @dev Calculate the increase of portalEnergy due to balance increase
        uint256 portalEnergyIncrease = (
            (account.stakedBalance * (maxLockDuration - account.lastMaxLockDuration) + (_amount * maxLockDuration))
                * WAD
        ) / (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT);

        /// @dev Update the user's staked balance
        uint256 stakedBalance = account.stakedBalance + _amount;

        /// @dev Update the user's maxStakeDebt based on added stake amount and current maxLockDuration
        uint256 maxStakeDebt = (stakedBalance * maxLockDuration * WAD) / (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT);

        /// @dev Update the user's portalEnergy
        uint256 portalEnergy = account.portalEnergy + portalEnergyEarned + portalEnergyIncrease;

        /// @dev Update the amount available to unstake
        uint256 availableToWithdraw =
            portalEnergy >= maxStakeDebt ? stakedBalance : (stakedBalance * portalEnergy) / maxStakeDebt;

        /// @dev update user
        user = Account(
            true, block.timestamp, maxLockDuration, stakedBalance, maxStakeDebt, portalEnergy, availableToWithdraw
        );
    }

    /// @notice create new user data
    /// @param _amount The amount to be added to the user's staked balance
    function _createAccount(uint256 _amount) internal view returns (Account memory user) {
        /// @dev catch maxLockDuration from portal
        uint256 maxLockDuration = _HLP_PORTAL.maxLockDuration();

        /// @dev Update the user's maxStakeDebt based on added stake amount and current maxLockDuration
        uint256 maxStakeDebt = (_amount * maxLockDuration * WAD) / (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT);

        /// @dev create new user
        user = Account(true, block.timestamp, maxLockDuration, _amount, maxStakeDebt, maxStakeDebt, _amount);
    }

    /// @notice Stake the principal token into the Adapter & redirect principal to Portal
    /// @dev This function allows users to stake their principal tokens into the Adapter
    /// @dev It transfers the user's principal tokens to the contract
    /// @dev It updates the total stake balance
    /// @dev It stakes the principal into the Portal
    /// @dev It checks if the user has a staking position, else it initializes a new stake
    /// @dev It emits an event with the updated stake information
    /// @param _amount The amount of tokens to stake
    /// @param _user The user whom staked for
    function stake(address _user, uint256 _amount) external nonReentrant {
        if(_user == address(0)) revert ErrorsLib.InvalidInput();
        if(_amount == 0) revert ErrorsLib.InvalidInput();

        Account memory account = accounts[_user].isExist ? _updateAccount(_user, _amount) : _createAccount(_amount);
        accounts[_user] = account;

        /// @dev Update the global tracker of staked principal
        totalPrincipalStaked = totalPrincipalStaked + _amount;

        emit EventsLib.StakePositionUpdated(
            msg.sender,
            _user,
            block.timestamp,
            account.lastMaxLockDuration,
            account.stakedBalance,
            account.maxStakeDebt,
            account.portalEnergy,
            account.availableToWithdraw
        );

        _HLP_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
        _HLP_TOKEN.approve(HLP_PORTAL_ADDRESS, _amount);
        _HLP_PORTAL.stake(_amount);
    }

    /// @notice Serve unstaking requests & withdraw principal from portal
    /// @dev This function allows users to unstake their tokens and withdraw the principal from the portal
    /// @dev It checks if the user has a stake and updates the user's stake data
    /// @dev It checks if the amount to be unstaked is less than or equal to the available withdrawable balance and the staked balance
    /// @dev It withdraws the matching amount of principal from the portal (external protocol)
    /// @dev It updates the user's staked balance
    /// @dev It updates the user's maximum stake debt
    /// @dev It updates the user's withdrawable balance
    /// @dev It updates the global tracker of staked principal
    /// @dev It sends the principal tokens to the user
    /// @dev It emits an event with the updated stake information
    /// @param _amount The amount of tokens to unstake
    function unstake(uint256 _amount) external nonReentrant existingAccount(msg.sender) {
        if(_amount == 0) revert ErrorsLib.InvalidInput();

        Account memory account = _updateAccount(msg.sender, 0);
        if(_amount > account.availableToWithdraw) revert ErrorsLib.InsufficientToWithdraw();

        /// @dev Update the user's stake info & cache to memory
        uint256 maxLockDuration = _HLP_PORTAL.maxLockDuration();
        uint256 stakedBalance = account.stakedBalance -= _amount;
        uint256 maxStakeDebt =
            account.maxStakeDebt = (stakedBalance * maxLockDuration * WAD) / (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT);
        uint256 portalEnergy =
            account.portalEnergy -= (_amount * maxLockDuration * WAD) / (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT);
        uint256 availableToWithdraw = account.availableToWithdraw =
            portalEnergy >= maxStakeDebt ? stakedBalance : (stakedBalance * portalEnergy) / maxStakeDebt;

        Account memory user = Account(
            true, block.timestamp, maxLockDuration, stakedBalance, maxStakeDebt, portalEnergy, availableToWithdraw
        );
        accounts[msg.sender] = user;

        /// @dev Update the global tracker of staked principal
        totalPrincipalStaked -= _amount;

        /// @dev Emit an event with the updated stake information
        emit EventsLib.StakePositionUpdated(
            msg.sender,
            msg.sender,
            block.timestamp,
            maxLockDuration,
            stakedBalance,
            maxStakeDebt,
            portalEnergy,
            availableToWithdraw
        );

        uint256 balanceBefore = _HLP_TOKEN.balanceOf(address(this));
        _HLP_PORTAL.unstake(_amount);
        uint256 balanceAfter = _HLP_TOKEN.balanceOf(address(this));
        uint256 availableAmount = balanceAfter - balanceBefore;

        /// @dev Send the principal tokens to the user
        _HLP_TOKEN.safeTransfer(msg.sender, availableAmount);
    }

    /// @dev As HLP Portal has trade time lock, check it here.
    function _checkLastTrade() internal view returns (bool) {
        return (block.timestamp - _HLP_PORTAL.lastTradeTime(address(this))) >= TRADE_TIMELOCK;
    }

    /// @notice Force unstaking via burning portalEnergyToken from user wallet to decrease debt sufficiently
    /// @dev This function allows users to force unstake all their tokens by burning portalEnergyToken from their wallet
    /// @dev It checks if the user has a stake and updates the user's stake data
    /// @dev It calculates how many portalEnergyToken must be burned from the user's wallet, if any
    /// @dev It burns the appropriate portalEnergyToken from the user's wallet to increase portalEnergy sufficiently
    /// @dev It withdraws the principal from the Portal to pay the user
    /// @dev It updates the user's information
    /// @dev It sends the full stake balance to the msg.sender
    /// @dev It emits an event with the updated stake information
    function forceUnstakeAll() external nonReentrant existingAccount(msg.sender) {
        /// @dev Update the user's stake data
        Account memory account = _updateAccount(msg.sender, 0);
        /// @dev Initialize cached variable
        uint256 portalEnergy = account.portalEnergy;
        uint256 maxStakeDebt = account.maxStakeDebt;

        /// @dev Calculate how many portalEnergyToken must be burned from the user's wallet, if any
        if (portalEnergy < maxStakeDebt) {
            uint256 remainingDebt = maxStakeDebt - portalEnergy;
            /// @dev Require that the user has enough Portal Energy Tokens
            if(_ENERGY_TOKEN.balanceOf(address(msg.sender)) < remainingDebt) revert ErrorsLib.InsufficientPEtokens();
            if(!_checkLastTrade()) revert ErrorsLib.TradeTimelockActive();
            /// @dev Burn the appropriate portalEnergyToken from the user's wallet to increase portalEnergy sufficiently
            _ENERGY_TOKEN.safeTransferFrom(msg.sender, address(this), remainingDebt);
            _ENERGY_TOKEN.approve(HLP_PORTAL_ADDRESS, remainingDebt);
            _HLP_PORTAL.burnPortalEnergyToken(address(this), remainingDebt);
            portalEnergy += remainingDebt;
        }

        /// @dev Update the user's stake info
        uint256 maxLockDuration = _HLP_PORTAL.maxLockDuration();
        uint256 balance = account.stakedBalance;
        portalEnergy -= (balance * maxLockDuration * WAD) / (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT);

        Account memory user = Account(true, block.timestamp, maxLockDuration, 0, 0, portalEnergy, 0);
        accounts[msg.sender] = user;

        /// @dev Update the global tracker of staked principal
        totalPrincipalStaked -= balance;
        /// @dev Emit an event with the updated stake information
        emit EventsLib.StakePositionUpdated(
            msg.sender, msg.sender, block.timestamp, maxLockDuration, 0, 0, portalEnergy, 0
        );

        /// @dev Send the user´s staked balance to the user
        uint256 balanceBefore = _HLP_TOKEN.balanceOf(address(this));
        _HLP_PORTAL.unstake(balance);
        uint256 balanceAfter = _HLP_TOKEN.balanceOf(address(this));
        uint256 availableAmount = balanceAfter - balanceBefore;
        _HLP_TOKEN.safeTransfer(msg.sender, availableAmount);
    }

    // ============================================
    // ==           GENERAL FUNCTIONS            ==
    // ============================================
    /// @notice Mint portalEnergyToken to recipient and decrease portalEnergy of caller equally
    /// @dev Contract must be owner of the portalEnergyToken
    /// @param _recipient The recipient of the portalEnergyToken
    /// @param _amount The amount of portalEnergyToken to mint
    function mintPortalEnergyToken(address _recipient, uint256 _amount)
        external
        nonReentrant
        existingAccount(msg.sender)
    {
        if(_amount == 0) revert ErrorsLib.InvalidInput();
        if(_recipient == address(0)) revert ErrorsLib.InvalidInput();
        if(!_checkLastTrade()) revert ErrorsLib.TradeTimelockActive();
        Account memory account = _updateAccount(msg.sender, 0);
        if(account.portalEnergy < _amount) revert ErrorsLib.InsufficientBalance();

        /// @dev Reduce the portalEnergy of the caller by the amount of portal energy tokens to be minted
        account.portalEnergy = account.portalEnergy - _amount;
        accounts[msg.sender] = account;

        /// @dev Mint portal energy tokens to the recipient's wallet
        _HLP_PORTAL.mintPortalEnergyToken(_recipient, _amount);

        /// @dev Emit the event that the ERC20 representation has been minted to recipient
        emit EventsLib.PortalEnergyMinted(msg.sender, _recipient, _amount);
    }

    /// @notice Burn portalEnergyToken from user wallet and increase portalEnergy of recipient equally
    /// @param _recipient The recipient of the portalEnergy increase
    /// @param _amount The amount of portalEnergyToken to burn
    function burnPortalEnergyToken(address _recipient, uint256 _amount)
        external
        nonReentrant
        existingAccount(_recipient)
    {
        if(_recipient == address(0)) revert ErrorsLib.InvalidInput();
        if(_amount == 0) revert ErrorsLib.InvalidInput();
        if(!_checkLastTrade()) revert ErrorsLib.TradeTimelockActive();

        /// @dev Require that the caller has sufficient tokens to burn
        if(_ENERGY_TOKEN.balanceOf(msg.sender) < _amount) revert ErrorsLib.InsufficientBalance();

        _ENERGY_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
        _ENERGY_TOKEN.approve(HLP_PORTAL_ADDRESS, _amount);
        _HLP_PORTAL.burnPortalEnergyToken(address(this), _amount);

        /// @dev Increase the portalEnergy of the recipient by the amount of portalEnergyToken burned
        accounts[_recipient].portalEnergy += _amount;

        /// @dev Emit the event that the ERC20 representation has been burned and value accrued to recipient
        emit EventsLib.PortalEnergyBurned(msg.sender, _recipient, _amount);
    }

    // ============================================
    // ==               INTERNAL LP              ==
    // ============================================
    /// @notice Sell PSM into contract to top up portalEnergy balance
    /// @dev This function allows users to sell PSM tokens to the contract to increase their portalEnergy
    /// @dev It checks if the user has a stake and updates the stake data
    /// @dev It checks if the user has enough PSM tokens
    /// @dev It calculates the amount of portalEnergy received based on the amount of PSM tokens sold
    /// @dev It checks if the amount of portalEnergy received is greater than or equal to the minimum expected output
    /// @dev It transfers the PSM tokens from the user to the contract
    /// @dev It increases the portalEnergy of the user by the amount of portalEnergy received
    /// @dev It buys Energy from Portal and add to user account
    /// @dev It emits a portalEnergyBuyExecuted event
    /// @param _user The user whom received energy
    /// @param _amount The amount of PSM tokens to sell
    /// @param _minReceived The minimum amount of portalEnergy to receive
    function buyPortalEnergy(address _user, uint256 _amount, uint256 _minReceived, uint256 _deadline)
        external
        nonReentrant
        existingAccount(_user)
    {
        if(_amount == 0) revert ErrorsLib.InvalidInput();
        if(_minReceived == 0) revert ErrorsLib.InvalidInput();
        if(_deadline < block.timestamp) revert ErrorsLib.DeadlineExpired();
        if(!_checkLastTrade()) revert ErrorsLib.TradeTimelockActive();
        if(_PSM_TOKEN.balanceOf(msg.sender) < _amount) revert ErrorsLib.InsufficientBalance();
        uint256 amountReceived = _HLP_PORTAL.quoteBuyPortalEnergy(_amount);
        if(amountReceived < _minReceived) revert ErrorsLib.InvalidOutput();
        /// @dev Update the stake data of the user
        Account memory account = _updateAccount(_user, 0);

        account.portalEnergy = account.portalEnergy + amountReceived;
        accounts[_user] = account;

        emit EventsLib.PortalEnergyBuyExecuted(msg.sender, _user, amountReceived);

        _PSM_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
        _PSM_TOKEN.approve(HLP_PORTAL_ADDRESS, _amount);
        _HLP_PORTAL.buyPortalEnergy(_amount, _minReceived, _deadline);
    }

    function swapOneInch(bytes calldata _actionData) internal returns(uint256) {
        /// @dev decode the data.
        (address _executor, SwapDescription memory _description, bytes memory _data) = abi.decode(_actionData, (address, SwapDescription, bytes));

        /// @dev do the swap.
        IERC20(_description.srcToken).approve(ONE_INCH_V5_AGGREGATION_ROUTER_CONTRACT_ADDRESS, _description.amount);
        (uint256 returnAmount_,) = _ONE_INCH_V5_AGGREGATION_ROUTER_CONTRACT.swap(_executor, _description, "", _data);
        return returnAmount_;
    }
    /// @notice Sell portalEnergy into contract to receive PSM
    /// @dev This function allows users to sell their portalEnergy to the contract to receive PSM tokens
    /// @dev It checks if the user has a stake and updates the stake data
    /// @dev It checks if the user has enough portalEnergy to sell
    /// @dev It updates the output token reserve and calculates the reserve of portalEnergy (Input)
    /// @dev It calculates the amount of output token received based on the amount of portalEnergy sold
    /// @dev It checks if the amount of output token received is greater than or equal to the minimum expected output
    /// @dev It reduces the portalEnergy balance of the user by the amount of portalEnergy sold
    /// @dev It sends the output token to the user
    /// @dev It emits a portalEnergySellExecuted event
    /// @param _receiver The address for sending tokens
    /// @param _amount The amount of portalEnergy to sell
    /// @param _minReceivedPSM The minimum amount of PSM tokens to receive
    function sellPortalEnergy(
        address payable _receiver,
        uint256 _amount,
        uint256 _minReceivedPSM,
        uint256 _deadline,
        bool _psm,
        bytes calldata _actionData
    ) external nonReentrant existingAccount(msg.sender) returns (uint256) {
        /// @dev validated input arguments
        if (_receiver == address(0)) revert ErrorsLib.InvalidInput();
        if (_amount == 0) revert ErrorsLib.InvalidInput();
        if (_minReceivedPSM == 0) revert ErrorsLib.InvalidInput();
        if(_deadline < block.timestamp) revert ErrorsLib.DeadlineExpired();
        if(!_checkLastTrade()) revert ErrorsLib.TradeTimelockActive();
        Account memory account = _updateAccount(msg.sender, 0);
        if(account.portalEnergy < _amount) revert ErrorsLib.InsufficientBalance();
        uint256 amountReceived = _HLP_PORTAL.quoteSellPortalEnergy(_amount);
        if(amountReceived < _minReceivedPSM) revert ErrorsLib.InvalidOutput();

        /// @dev Update the stake data of the user
        account.portalEnergy = account.portalEnergy - _amount;
        accounts[msg.sender] = account;

        emit EventsLib.PortalEnergySellExecuted(msg.sender, _receiver, amountReceived);

        /// @dev Sell energy in Portal and get PSM
        _HLP_PORTAL.sellPortalEnergy(_amount, _minReceivedPSM, _deadline);

        /// @dev If wanted token is PSM, transfer it
        if (_psm) {
            _PSM_TOKEN.safeTransfer(_receiver, amountReceived);
            return amountReceived;
        }
        /// @dev If wanted token is Other than PSM.
        return swapOneInch(_actionData);
    }

    // ============================================
    // ==               LIQUIDITY                ==
    // ============================================

    // function addLiquidity() external {}

    // ============================================
    // ==              VIEW EXTERNAL             ==
    // ============================================

    /// @notice Simulate updating a user stake position and return the values without updating the struct
    /// @param _user The user whose stake position is to be updated
    /// @param _amount The amount to add to the user's stake position
    /// @dev Returns the simulated up-to-date user stake information
    function getUpdateAccount(address _user, uint256 _amount)
        public
        view
        existingAccount(_user)
        returns (address, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        Account memory account = _updateAccount(_user, _amount);
        return (
            _user,
            account.lastUpdateTime,
            account.lastMaxLockDuration,
            account.stakedBalance,
            account.maxStakeDebt,
            account.portalEnergy,
            account.availableToWithdraw
        );
    }

    /// @notice Simulate forced unstake and return the number of portal energy tokens to be burned
    /// @param _user The user whose stake position is to be updated for the simulation
    /// @return portalEnergyTokenToBurn Returns the number of portal energy tokens to be burned for a full unstake
    function quoteforceUnstakeAll(address _user) external view returns (uint256 portalEnergyTokenToBurn) {
        /// @dev Get the relevant data from the simulated account update
        (,,,, uint256 maxStakeDebt, uint256 portalEnergy,) = getUpdateAccount(_user, 0);

        /// @dev Calculate how many portal energy tokens must be burned for a full unstake
        if (maxStakeDebt > portalEnergy) {
            portalEnergyTokenToBurn = maxStakeDebt - portalEnergy;
        }
    }

    /// @notice Simulate buying portalEnergy (output) with PSM tokens (input) and return amount received (output)
    /// @dev This function allows the caller to simulate a portalEnergy buy order of any size
    function quoteBuyPortalEnergy(uint256 _amountInput) external view returns (uint256) {
        return _HLP_PORTAL.quoteBuyPortalEnergy(_amountInput);
    }

    /// @notice Simulate selling portalEnergy (input) against PSM tokens (output) and return amount received (output)
    /// @dev This function allows the caller to simulate a portalEnergy sell order of any size
    function quoteSellPortalEnergy(uint256 _amountInput) external view returns (uint256) {
        return _HLP_PORTAL.quoteSellPortalEnergy(_amountInput);
    }

    // receive() external payable {}
    // fallback() external payable {}
}
