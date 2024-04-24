// SPDX-License-Identifier: GPL-2.0-only
pragma solidity =0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IMintBurnToken} from "./interfaces/IMintBurnToken.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPortalV2MultiAsset} from "./interfaces/IPortalV2MultiAsset.sol";
import {IAdapterV1, Account, SwapData} from "./interfaces/IAdapterV1.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {IAggregationRouterV6, SwapDescription, IAggregationExecutor} from "./interfaces/IAggregationRouterV6.sol";
import {IRamsesFactory, IRamsesRouter, IRamsesPair} from "./interfaces/IRamses.sol";

/// @title Adapter V1 contract for Portals V2
/// @author Possum Labs
/**
 * @notice This contract accepts and returns user deposits of a single asset
 * The deposits are redirected to a connected Portal contract
 * Users accrue portalEnergy points over time while staking their tokens in the Adapter
 * portalEnergy can be exchanged for PSM tokens via the virtual LP of the connected Portals
 * When selling portalEnergy, users can choose to receive any DEX traded token by routing PSM through 1Inch
 * Users can also opt to receive ETH/PSM V2 LP tokens on Ramses
 * portalEnergy can be minted as standard ERC20 token
 * PortalEnergy Tokens can be burned to increase a recipient portalEnergy balance in the Adapter
 */
contract AdapterV1 is ReentrancyGuard {
    constructor(address _PORTAL_ADDRESS) {
        PORTAL = IPortalV2MultiAsset(_PORTAL_ADDRESS);
        setUp();
    }

    // ============================================
    // ==               VARIABLES                ==
    // ============================================
    using SafeERC20 for IERC20;

    address constant PSM_TOKEN_ADDRESS = 0x17A8541B82BF67e10B0874284b4Ae66858cb1fd5;
    address constant ONE_INCH_V6_AGGREGATION_ROUTER_CONTRACT_ADDRESS = 0x111111125421cA6dc452d289314280a0f8842A65;
    address constant WETH_ADDRESS = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant RAMSES_FACTORY_ADDRESS = 0xAAA20D08e59F6561f242b08513D36266C5A29415;
    address constant RAMSES_ROUTER_ADDRESS = 0xAAA87963EFeB6f7E0a2711F397663105Acb1805e;
    uint256 constant WAD = 1e18;
    uint256 constant SECONDS_PER_YEAR = 31536000;
    uint256 constant MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    IPortalV2MultiAsset public immutable PORTAL; // The connected Portal contract
    IERC20 public constant PSM = IERC20(PSM_TOKEN_ADDRESS); // the ERC20 representation of PSM token
    IERC20 constant WETH = IERC20(WETH_ADDRESS); // the ERC20 representation of WETH token
    address public constant OWNER = 0xAb845D09933f52af5642FC87Dd8FBbf553fd7B33;

    IMintBurnToken public portalEnergyToken; // The ERC20 representation of portalEnergy
    IERC20 public principalToken; // The staking token of the Portal
    uint256 denominator; // Used in calculation related to earning portalEnergy

    IRamsesFactory public constant RAMSES_FACTORY = IRamsesFactory(RAMSES_FACTORY_ADDRESS); // Interface of Ramses Factory
    IRamsesRouter public constant RAMSES_ROUTER = IRamsesRouter(RAMSES_ROUTER_ADDRESS); // Interface of Ramses Router
    IAggregationRouterV6 public constant ONE_INCH_V6_AGGREGATION_ROUTER =
        IAggregationRouterV6(ONE_INCH_V6_AGGREGATION_ROUTER_CONTRACT_ADDRESS); // Interface of 1inchRouter

    uint256 public totalPrincipalStaked; // Amount of principal staked by all users of the Adapter
    mapping(address => Account) public accounts; // Associate users with their stake position

    address public migrationDestination; // The new Adapter version
    uint256 public votesForMigration; // Track the yes-votes for migrating to a new Adapter
    bool public successMigrated; // True if the migration was executed by minting the stake NFT to the new Adapter
    mapping(address user => uint256 voteCount) public voted; // Track user votes for migration
    uint256 public constant TIMELOCK = 604800; // 7 Days delay before migration can be executed
    uint256 migrationTime;

    // ============================================
    // ==               MODIFIERS                ==
    // ============================================
    modifier onlyOwner() {
        if (msg.sender != OWNER) {
            revert ErrorsLib.notOwner();
        }
        _;
    }

    modifier notMigrating() {
        if (migrationDestination != address(0)) {
            revert ErrorsLib.isMigrating();
        }
        _;
    }

    modifier isMigrating() {
        if (migrationDestination == address(0)) {
            revert ErrorsLib.notMigrating();
        }
        _;
    }

    // ============================================
    // ==          MIGRATION MANAGEMENT          ==
    // ============================================
    /// @notice Set the destination address when migrating to a new Adapter contract
    /// @dev Allow the contract owner to propose a new Adapter contract for migration
    /// @dev The current value of migrationDestination must be the zero address
    function proposeMigrationDestination(address _adapter) external onlyOwner notMigrating {
        migrationDestination = _adapter;
    }

    /// @notice Capital based voting process to accept the migration contract
    /// @dev Allow users to accept the proposed migration contract
    /// @dev Can only be called if a destination was proposed, i.e. migration is ongoing
    function acceptMigrationDestination() external isMigrating {
        /// @dev Get user stake balance which equals voting power
        Account memory account = accounts[msg.sender];

        /// @dev Ensure that users can only add their current stake balance to votes
        if (voted[msg.sender] == 0) {
            /// @dev Increase the total number of acceptance votes and votes of the user by user stake balance
            votesForMigration += account.stakedBalance;
            voted[msg.sender] = account.stakedBalance;
        }

        /// @dev Check if the votes are in favour of migrating (>50% of capital)
        if (votesForMigration > totalPrincipalStaked / 2 && migrationTime == 0) {
            migrationTime = block.timestamp + TIMELOCK;
        }
    }

    /// @notice This function mints the Portal NFT and transfers user stakes to a new Adapter
    /// @dev Timelock protected function that can only be called once to move capital to a new Adapter
    function executeMigration() external isMigrating {
        /// @dev Ensure that the timelock has passed
        if (block.timestamp < migrationTime) {
            revert ErrorsLib.isTimeLocked();
        }

        /// @dev Ensure that the migration (minting of NFT) can only be performed once
        if (successMigrated == true) {
            revert ErrorsLib.hasMigrated();
        }

        /// @dev Mint an NFT to the new Adapter that holds the current Adapter stake information
        /// @dev IMPORTANT: The migration contract must be able to receive ERC721 tokens
        successMigrated = true;
        PORTAL.mintNFTposition(migrationDestination);
    }

    /// @notice Function to enable the new Adapter to move over account information of users
    /// @dev This function can only be called by the migration address
    /// @dev Transfer user stake information to the new contract (new Adapter)
    function migrateStake(address _user)
        external
        returns (
            uint256 lastUpdateTime,
            uint256 lastMaxLockDuration,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy
        )
    {
        /// @dev Check that the Migration is successfull
        if (successMigrated == false) {
            revert ErrorsLib.migrationVotePending();
        }

        /// @dev Check that the caller is the new Adapter contract
        if (msg.sender != migrationDestination) {
            revert ErrorsLib.notCalledByDestination();
        }

        /// @dev Get the current state of the user stake in Adapter and return
        (lastUpdateTime, lastMaxLockDuration, stakedBalance, maxStakeDebt, portalEnergy,,) =
            getUpdateAccount(_user, 0, true);

        /// @dev delete the account of the user in this Adapter
        delete accounts[_user];
    }

    // ============================================
    // ==           STAKING & UNSTAKING          ==
    // ============================================
    /// @notice Simulate updating a user stake position and return the values without updating the struct
    /// @dev Return the simulated up-to-date user stake information
    /// @dev Consider changes from staking or unstaking including burning amount of PE tokens
    /// @param _user The user whose stake position is to be updated
    /// @param _amount The amount to add or subtract from the user's stake position
    /// @param _isPositiveAmount True for staking (add), false for unstaking (subtract)
    function getUpdateAccount(address _user, uint256 _amount, bool _isPositiveAmount)
        public
        view
        returns (
            uint256 lastUpdateTime,
            uint256 lastMaxLockDuration,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy,
            uint256 availableToWithdraw,
            uint256 portalEnergyTokensRequired
        )
    {
        /// @dev Get maxLockDuration from portal
        uint256 maxLockDuration = PORTAL.maxLockDuration();

        /// @dev Load user account into memory
        Account memory account = accounts[_user];

        /// @dev initialize helper variables
        uint256 amount = _amount; // to avoid stack too deep issue
        bool isPositive = _isPositiveAmount; // to avoid stack too deep issue
        uint256 portalEnergyNetChange;
        uint256 timePassed = block.timestamp - account.lastUpdateTime;
        uint256 maxLockDifference = maxLockDuration - account.lastMaxLockDuration;
        uint256 adjustedPE = amount * maxLockDuration * 1e18;
        stakedBalance = account.stakedBalance;

        /// @dev Check that the Stake Balance is sufficient for unstaking the amount
        if (!isPositive && amount > stakedBalance) {
            revert ErrorsLib.InsufficientStakeBalance();
        }

        /// @dev Check the user account state based on lastUpdateTime
        /// @dev If this variable is 0, the user never staked and could not earn PE
        if (account.lastUpdateTime > 0) {
            /// @dev Calculate the Portal Energy earned since the last update
            uint256 portalEnergyEarned = stakedBalance * timePassed;

            /// @dev Calculate the gain of Portal Energy from maxLockDuration increase
            uint256 portalEnergyIncrease = stakedBalance * maxLockDifference;

            /// @dev Summarize Portal Energy changes and divide by common denominator
            portalEnergyNetChange = ((portalEnergyEarned + portalEnergyIncrease) * 1e18) / denominator;
        }

        /// @dev Calculate the adjustment of Portal Energy from balance change
        uint256 portalEnergyAdjustment = adjustedPE / denominator;

        /// @dev Calculate the amount of Portal Energy Tokens to be burned for unstaking the amount
        portalEnergyTokensRequired = !isPositive
            && portalEnergyAdjustment > (account.portalEnergy + portalEnergyNetChange)
            ? portalEnergyAdjustment - (account.portalEnergy + portalEnergyNetChange)
            : 0;

        /// @dev Set the last update time to the current timestamp
        lastUpdateTime = block.timestamp;

        /// @dev Update the last maxLockDuration
        lastMaxLockDuration = maxLockDuration;

        /// @dev Update the user's staked balance and consider stake or unstake
        stakedBalance = isPositive ? stakedBalance + amount : stakedBalance - amount;

        /// @dev Update the user's max stake debt
        maxStakeDebt = (stakedBalance * maxLockDuration * 1e18) / denominator;

        /// @dev Update the user's portalEnergy and account for stake or unstake
        /// @dev This will be 0 if Portal Energy Tokens must be burned
        portalEnergy = isPositive
            ? account.portalEnergy + portalEnergyNetChange + portalEnergyAdjustment
            : account.portalEnergy + portalEnergyTokensRequired + portalEnergyNetChange - portalEnergyAdjustment;

        /// @dev Update amount available to withdraw
        availableToWithdraw =
            portalEnergy >= maxStakeDebt ? stakedBalance : (stakedBalance * portalEnergy) / maxStakeDebt;
    }

    /// @notice Update user account to the current state
    /// @dev This function updates the user accout to the current state
    /// @dev It takes memory inputs and stores them into the user account struct
    /// @param _user The user whose account is to be updated
    /// @param _stakedBalance The current Staked Balance of the user
    /// @param _maxStakeDebt The current maximum Stake Debt of the user
    /// @param _portalEnergy The current Portal Energy of the user
    function _updateAccount(address _user, uint256 _stakedBalance, uint256 _maxStakeDebt, uint256 _portalEnergy)
        private
    {
        /// @dev Get maxLockDuration from portal
        uint256 maxLockDuration = PORTAL.maxLockDuration();

        /// @dev Update the user account data
        Account storage account = accounts[_user];
        account.lastUpdateTime = block.timestamp;
        account.lastMaxLockDuration = maxLockDuration;
        account.stakedBalance = _stakedBalance;
        account.maxStakeDebt = _maxStakeDebt;
        account.portalEnergy = _portalEnergy;

        /// @dev Emit an event with the updated account information
        emit EventsLib.AdapterPositionUpdated(
            _user,
            account.lastUpdateTime,
            account.lastMaxLockDuration,
            account.stakedBalance,
            account.maxStakeDebt,
            account.portalEnergy
        );
    }

    /// @notice Stake the principal token into the Adapter and then into Portal
    /// @dev This function allows users to stake their principal tokens into the Adapter
    /// @dev Can only be called if the virtual LP is active (indirect condition)
    /// @dev Cannot be called after a migration destination was proposed (withdraw-only mode)
    /// @dev Update the user account
    /// @dev Update the global tracker of staked principal
    /// @dev Stake the principal into the connected Portal
    /// @param _amount The amount of tokens to stake
    function stake(uint256 _amount) external payable notMigrating nonReentrant {
        /// @dev Rely on input validation from Portal

        /// @dev Avoid tricking the function when ETH is the principal token by inserting fake _amount
        if (address(principalToken) == address(0)) {
            _amount = msg.value;
        }

        /// @dev Get the current state of the user stake in Adapter
        (,, uint256 stakedBalance, uint256 maxStakeDebt, uint256 portalEnergy,,) =
            getUpdateAccount(msg.sender, _amount, true);

        /// @dev Update the user stake struct
        _updateAccount(msg.sender, stakedBalance, maxStakeDebt, portalEnergy);

        /// @dev Update the global tracker of staked principal
        totalPrincipalStaked = totalPrincipalStaked + _amount;

        /// @dev Trigger the stake transaction in the Portal & send tokens
        if (address(principalToken) == address(0)) {
            PORTAL.stake{value: _amount}(_amount);
        } else {
            if (msg.value > 0) {
                revert ErrorsLib.NativeTokenNotAllowed();
            }
            principalToken.safeTransferFrom(msg.sender, address(this), _amount);
            PORTAL.stake(_amount);
        }

        /// @dev Emit event that principal has been staked
        emit EventsLib.AdapterStaked(msg.sender, _amount);
    }

    /// @notice Serve unstaking requests & withdraw principal from the connected Portal
    /// @dev This function allows users to unstake their tokens
    /// @dev Cannot be called after migration was executed (indirect condition, Adapter has no funds in Portal)
    /// @dev Update the user account
    /// @dev Update the global tracker of staked principal
    /// @dev Burn Portal Energy Tokens from caller to top up account balance if required
    /// @dev Withdraw principal from the connected Portal
    /// @dev Send the principal tokens to the user
    /// @param _amount The amount of tokens to unstake
    function unstake(uint256 _amount) external nonReentrant {
        /// @dev Rely on input validation from Portal

        /// @dev If the staker had voted for migration, reset the vote
        if (voted[msg.sender] > 0) {
            votesForMigration -= voted[msg.sender];
            voted[msg.sender] = 0;
        }

        /// @dev Get the current state of the user stake
        /// @dev Throws if caller tries to unstake more than stake balance
        /// @dev Will burn Portal Energy tokens if account has insufficient Portal Energy
        (,, uint256 stakedBalance, uint256 maxStakeDebt, uint256 portalEnergy,, uint256 portalEnergyTokensRequired) =
            getUpdateAccount(msg.sender, _amount, false);

        /// @dev Update the user stake struct
        _updateAccount(msg.sender, stakedBalance, maxStakeDebt, portalEnergy);

        /// @dev Update the global tracker of staked principal
        totalPrincipalStaked -= _amount;

        /// @dev Take Portal Energy Tokens from the user if required
        if (portalEnergyTokensRequired > 0) {
            portalEnergyToken.transferFrom(msg.sender, address(this), portalEnergyTokensRequired);

            /// @dev Burn the Portal Energy Tokens to top up PE balance of the Adapter
            PORTAL.burnPortalEnergyToken(address(this), portalEnergyTokensRequired);
        }

        /// @dev Withdraw principal from the Portal to the Adapter
        PORTAL.unstake(_amount);

        /// @dev Send the received token balance to the user
        if (address(principalToken) == address(0)) {
            (bool sent,) = payable(msg.sender).call{value: address(this).balance}("");
            if (!sent) {
                revert ErrorsLib.FailedToSendNativeToken();
            }
        } else {
            IERC20(principalToken).safeTransfer(msg.sender, principalToken.balanceOf(address(this)));
        }

        /// @dev Emit the event that funds have been unstaked
        emit EventsLib.AdapterUnstaked(msg.sender, _amount);
    }

    // ============================================
    // ==          TRADE PORTAL ENERGY           ==
    // ============================================
    /// @notice Users sell PSM into the Adapter to top up portalEnergy balance of a recipient in the Adapter
    /// @dev This function allows users to sell PSM tokens to the contract to increase a recipient portalEnergy
    /// @dev Get the correct price from the quote function of the Portal
    /// @dev Increase the portalEnergy (in Adapter) of the recipient by the amount of portalEnergy received
    /// @dev Transfer the PSM tokens from the caller to the contract, then to the Portal
    /// @param _recipient The recipient of the Portal Energy credit
    /// @param _amountInputPSM The amount of PSM tokens to sell
    /// @param _minReceived The minimum amount of portalEnergy to receive
    /// @param _deadline The unix timestamp that marks the deadline for order execution

    function buyPortalEnergy(address _recipient, uint256 _amountInputPSM, uint256 _minReceived, uint256 _deadline)
        external
        notMigrating
    {
        /// @dev Rely on amount input validation from Portal

        /// @dev validate the recipient address
        if (_recipient == address(0)) {
            revert ErrorsLib.InvalidAddress();
        }

        /// @dev Get the amount of portalEnergy received based on the amount of PSM tokens sold
        uint256 amountReceived = PORTAL.quoteBuyPortalEnergy(_amountInputPSM);

        /// @dev Increase the portalEnergy of the recipient by the amount of portalEnergy received
        accounts[_recipient].portalEnergy += amountReceived;

        /// @dev Send PSM from caller to Adapter, then trigger the transaction in the Portal
        /// @dev Approvals are set with different function to save gas
        PSM.transferFrom(msg.sender, address(this), _amountInputPSM);
        PORTAL.buyPortalEnergy(address(this), _amountInputPSM, _minReceived, _deadline);

        /// @dev Emit the event that Portal Energy has been purchased
        emit EventsLib.AdapterEnergyBuyExecuted(msg.sender, _recipient, amountReceived);
    }

    /// @notice Users sell portalEnergy into the Adapter to receive upfront yield
    /// @dev This function allows users to sell portalEnergy to the Adapter with different swap modes
    /// @dev Get the output amount from the quote function
    /// @dev Reduce the portalEnergy balance of the caller by the amount of portalEnergy sold
    /// @dev Perform the type of exchange according to selected mode
    /// @param _recipient The recipient of the output tokens
    /// @param _amountInputPE The amount of Portal Energy to sell (Adapter)
    /// @param _minReceived The minimum amount of PSM to receive
    /// @param _deadline The unix timestamp that marks the deadline for order execution
    /// @param _mode The trading mode of the swap. 0 = PSM, 1 = ETH/PSM LP, 2 = 1Inch swap
    /// @param _actionData Data required for the 1Inch Router, received by 1Inch API
    function sellPortalEnergy(
        address payable _recipient,
        uint256 _amountInputPE,
        uint256 _minReceived,
        uint256 _deadline,
        uint256 _mode,
        bytes calldata _actionData,
        uint256 _minPSMForLiquidiy,
        uint256 _minWethForLiquidiy
    ) external notMigrating {
        /// @dev Only validate additional input arguments, let other checks float up from Portal
        if (_mode > 2) revert ErrorsLib.InvalidMode();

        /// @dev Get the current state of user stake in Adapter
        (,, uint256 stakedBalance, uint256 maxStakeDebt, uint256 portalEnergy,,) = getUpdateAccount(msg.sender, 0, true);

        /// @dev Check that the user has enough portalEnergy to sell
        if (portalEnergy < _amountInputPE) {
            revert ErrorsLib.InsufficientBalance();
        }

        /// @dev Get the amount of PSM received based on the amount of portalEnergy sold
        uint256 amountReceived = PORTAL.quoteSellPortalEnergy(_amountInputPE);

        /// @dev Update the stake data of the user
        portalEnergy -= _amountInputPE;

        /// @dev Update the user stake struct
        _updateAccount(msg.sender, stakedBalance, maxStakeDebt, portalEnergy);

        /// @dev Sell energy in Portal and get PSM
        PORTAL.sellPortalEnergy(address(this), _amountInputPE, _minReceived, _deadline);

        /// @dev Assemble the swap data from API to use 1Inch Router
        SwapData memory swap = SwapData(_recipient, amountReceived, _actionData);

        /// @dev Transfer PSM, or add liquidity, or exchange on 1Inch and transfer output token
        if (_mode == 0) {
            PSM.safeTransfer(_recipient, amountReceived);
        } else if (_mode == 1) {
            addLiquidity(swap, _minPSMForLiquidiy, _minWethForLiquidiy);
        } else {
            swapOneInch(swap, false);
        }

        /// @dev Emit the event that Portal Energy has been sold
        emit EventsLib.AdapterEnergySellExecuted(msg.sender, _recipient, _amountInputPE);
    }

    // ============================================
    // ==         External Integrations          ==
    // ============================================
    /// @dev This internal function assembles the swap via the 1Inch router from API data
    function swapOneInch(SwapData memory _swap, bool _forLiquidity) internal {
        /// @dev decode the data for getting _executor, _description, _data.
        (address _executor, SwapDescription memory _description, bytes memory _data) =
            abi.decode(_swap.actionData, (address, SwapDescription, bytes));

        /// @dev Swap via the 1Inch Router
        /// @dev Allowance is increased in separate function to save gas
        (, uint256 spentAmount_) =
            ONE_INCH_V6_AGGREGATION_ROUTER.swap(IAggregationExecutor(_executor), _description, _data);

        /// @dev Send remaining tokens back to user if not called from addLiquidity
        if (!_forLiquidity) {
            uint256 remainAmount = _swap.psmAmount - spentAmount_;
            if (remainAmount > 0) PSM.safeTransfer(msg.sender, remainAmount);
        }
    }

    /// @dev Given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    /// @dev This is used to determine how many assets must be supplied to a Pool2 LP
    function quoteLiquidity(uint256 amountA, uint256 reserveA, uint256 reserveB)
        internal
        pure
        returns (uint256 amountB)
    {
        if (amountA == 0) revert ErrorsLib.InvalidAmount();
        if (reserveA == 0 || reserveB == 0) {
            revert ErrorsLib.InsufficientReserves();
        }

        amountB = (amountA * reserveB) / reserveA;
    }

    /// @dev This function is called when mode = 1 in sellPortalEnergy
    /// @dev Sell some amount of PSM for WETH, then pair in Ramses Pool2
    function addLiquidity(SwapData memory _swap, uint256 _minPSMForLiquidiy, uint256 _minWethForLiquidiy) internal {
        swapOneInch(_swap, true);

        /// @dev Decode the swap data for getting minPSM and minWETH.
        // (,,, uint256 minPSM, uint256 minWeth) =
        //     abi.decode(_swap.actionData, (address, SwapDescription, bytes, uint256, uint256));

        /// @dev This contract shouldn't hold any token, so we pass all tokens.
        uint256 PSMBalance = PSM.balanceOf(address(this));
        uint256 WETHBalance = WETH.balanceOf(address(this));

        /// @dev Get the correct amount of PSM and WETH to add to the Ramses Pool2
        (uint256 amountPSM, uint256 amountWETH) =
            _addLiquidity(PSMBalance, WETHBalance, _minPSMForLiquidiy, _minWethForLiquidiy);

        /// @dev Get the pair address of the ETH/PSM Pool2 LP
        address pair = RAMSES_FACTORY.getPair(PSM_TOKEN_ADDRESS, WETH_ADDRESS, false);

        /// @dev Transfer tokens to the LP and mint LP shares to the user
        /// @dev Uses the low level mint function of the pair implementation
        /// @dev Assumes that the pair already exists which is the case
        PSM.safeTransfer(pair, amountPSM);
        WETH.safeTransfer(pair, amountWETH);
        IRamsesPair(pair).mint(_swap.receiver);

        /// @dev Return remaining tokens to the caller
        if (PSM.balanceOf(address(this)) > 0) PSM.transfer(_swap.receiver, PSM.balanceOf(address(this)));
        if (WETH.balanceOf(address(this)) > 0) WETH.transfer(_swap.receiver, WETH.balanceOf(address(this)));
    }

    /// @dev Calculate the required token amounts of PSM and WETH to add liquidity
    function _addLiquidity(uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin)
        internal
        view
        returns (uint256 amountA, uint256 amountB)
    {
        if (amountADesired < amountAMin) revert ErrorsLib.InvalidAmount();
        if (amountBDesired < amountBMin) revert ErrorsLib.InvalidAmount();

        /// @dev Get the pair address
        address pair = RAMSES_FACTORY.getPair(PSM_TOKEN_ADDRESS, WETH_ADDRESS, false);

        /// @dev Get the reserves of the pair
        (uint256 reserveA, uint256 reserveB,) = IRamsesPair(pair).getReserves();

        /// @dev Calculate how much PSM and WETH are required
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = quoteLiquidity(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) {
                    revert ErrorsLib.InvalidAmount();
                }
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quoteLiquidity(amountBDesired, reserveB, reserveA);
                if (amountAOptimal > amountADesired) {
                    revert ErrorsLib.InvalidAmount();
                }
                if (amountAOptimal < amountAMin) {
                    revert ErrorsLib.InvalidAmount();
                }
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    // ============================================
    // ==           PE ERC20 MANAGEMENT          ==
    // ============================================
    /// @notice Users can burn their PortalEnergyTokens to increase their portalEnergy in the Adapter
    /// @dev This function allows users to convert Portal Energy Tokens into internal Adapter PE
    /// @dev Burn Portal Energy Tokens of caller and increase portalEnergy in Adapter
    /// @param _amount The amount of portalEnergyToken to burn

    function burnPortalEnergyToken(address _recipient, uint256 _amount) external notMigrating {
        /// @dev Rely on input validation of the Portal

        /// @dev validate the recipient address
        if (_recipient == address(0)) {
            revert ErrorsLib.InvalidAddress();
        }

        /// @dev Increase the portalEnergy of the recipient by the amount of portalEnergyToken burned
        accounts[_recipient].portalEnergy += _amount;

        /// @dev Transfer Portal Energy Tokens to Adapter so that they can be burned
        portalEnergyToken.transferFrom(msg.sender, address(this), _amount);

        /// @dev Burn portalEnergyToken from the Adapter
        PORTAL.burnPortalEnergyToken(address(this), _amount);

        emit EventsLib.AdapterEnergyBurned(msg.sender, _recipient, _amount);
    }

    /// @notice Users can mint Portal Energy Tokens using their internal balance
    /// @dev This function controls the minting of Portal Energy Token
    /// @dev Decrease portalEnergy of caller and instruct Portal to mint Portal Energy Tokens to the recipient
    /// @param _amount The amount of portalEnergyToken to mint
    function mintPortalEnergyToken(address _recipient, uint256 _amount) external {
        /// @dev Rely on input validation of the Portal

        /// @dev Get the current state of the user stake
        (,, uint256 stakedBalance, uint256 maxStakeDebt, uint256 portalEnergy,,) = getUpdateAccount(msg.sender, 0, true);

        /// @dev Check that the caller has sufficient portalEnergy to mint the amount of portalEnergyToken
        if (portalEnergy < _amount) {
            revert ErrorsLib.InsufficientBalance();
        }

        /// @dev Reduce the portalEnergy of the caller by the amount of minted tokens
        portalEnergy -= _amount;

        /// @dev Update the user stake struct
        _updateAccount(msg.sender, stakedBalance, maxStakeDebt, portalEnergy);

        /// @dev Mint portal energy tokens to the recipient address
        PORTAL.mintPortalEnergyToken(_recipient, _amount);

        emit EventsLib.AdapterEnergyMinted(msg.sender, _recipient, _amount);
    }

    // ============================================
    // ==                GENERAL                 ==
    // ============================================
    /// @dev Increase token spending allowances of Adapter holdings
    function increaseAllowances() external {
        PSM.approve(address(PORTAL), MAX_UINT);
        PSM.approve(ONE_INCH_V6_AGGREGATION_ROUTER_CONTRACT_ADDRESS, MAX_UINT);
        portalEnergyToken.approve(address(PORTAL), MAX_UINT);

        /// @dev No approval required when transacting with ETH
        if (address(principalToken) != address(0)) {
            /// @dev For ERC20 that require allowance to be 0 before increasing (e.g. USDT) add the following:
            /// principalToken.approve(address(PORTAL), 0);
            principalToken.safeIncreaseAllowance(address(PORTAL), MAX_UINT);
        }
    }

    /// @dev Initialize important variables, called by the constructor
    function setUp() internal {
        if (PORTAL.PRINCIPAL_TOKEN_ADDRESS() != address(0)) {
            principalToken = IERC20(PORTAL.PRINCIPAL_TOKEN_ADDRESS());
        }
        if (address(PORTAL.portalEnergyToken()) == address(0)) {
            revert ErrorsLib.TokenNotSet();
        }
        portalEnergyToken = IMintBurnToken(address(PORTAL.portalEnergyToken()));
        denominator = SECONDS_PER_YEAR * PORTAL.DECIMALS_ADJUSTMENT();
    }

    receive() external payable {}

    fallback() external payable {}
}
