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
import {IOneInchV5AggregationRouter, SwapDescription} from "./interfaces/IOneInchV5AggregationRouter.sol";
import {IRamsesFactory, IRamsesRouter, IRamsesPair} from "./interfaces/IRamses.sol";
import "./libraries/ConstantsLib.sol";

contract AdapterV1 is ReentrancyGuard {
    constructor(address _PORTAL_ADDRESS) {
        PORTAL = IPortalV2MultiAsset(_PORTAL_ADDRESS);
        setUp();
    }

    // ============================================
    // ==               VARIABLES                ==
    // ============================================
    using SafeERC20 for IERC20;

    IPortalV2MultiAsset public immutable PORTAL; // The connected Portal contract
    IERC20 public constant PSM = IERC20(PSM_TOKEN_ADDRESS); // the ERC20 representation of PSM token
    IERC20 constant WETH = IERC20(WETH_ADDRESS); // the ERC20 representation of WETH token
    address public constant OWNER = 0xAb845D09933f52af5642FC87Dd8FBbf553fd7B33;

    IMintBurnToken public portalEnergyToken; // The ERC20 representation of portalEnergy
    IERC20 public principalToken; // The staking token of the Portal
    uint256 denominator;

    IRamsesFactory public constant RAMSES_FACTORY =
        IRamsesFactory(RAMSES_FACTORY_ADDRESS); // Interface of Ramses Factory
    IRamsesRouter public constant RAMSES_ROUTER =
        IRamsesRouter(RAMSES_ROUTER_ADDRESS); // Interface of Ramses Router
    IOneInchV5AggregationRouter public constant ONE_INCH_V5_AGGREGATION_ROUTER =
        IOneInchV5AggregationRouter(
            ONE_INCH_V5_AGGREGATION_ROUTER_CONTRACT_ADDRESS
        ); // Interface of 1inchRouter

    uint256 public totalPrincipalStaked; // Amount of principal staked by all users of the Adapter
    mapping(address => Account) public accounts; // Associate users with their stake position

    address public migrationDestination; // Contract with new Adapter version
    uint256 public votesForMigration; // Track the votes for migrating to a new Adapter
    bool public inMigration; // True if the Adapter entered voting state to migrate
    bool public successMigrated; // True if the migration was executed by minting stake NFT to new Adapter
    mapping(address user => uint256 voteCount) public voted; // Track if a user has voted for migration

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
    /// @dev Allow the contract owner to propose a new Adapter contract for migration
    /// @dev The current value of migrationDestination must be the zero address
    function proposeMigrationDestination(
        address _adapter
    ) external onlyOwner notMigrating {
        migrationDestination = _adapter;
    }

    /// @dev Allow users to accept the proposed contract to migrate
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
        if (votesForMigration > totalPrincipalStaked / 2) {
            /// @dev Mint an NFT to the new Adapter that holds the current Adapter stake information
            PORTAL.mintNFTposition(migrationDestination);
            successMigrated = true;
        }
    }

    /// @dev This function can only be called by the migration address
    /// @dev Transfer user stake information to the new contract (new Adapter)
    function migrateStake(
        address _user
    )
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
        (
            lastUpdateTime,
            lastMaxLockDuration,
            stakedBalance,
            maxStakeDebt,
            portalEnergy,
            ,

        ) = getUpdateAccount(_user, 0, true);

        /// @dev delete the account of the user in this Adapter
        delete accounts[msg.sender];
    }

    // ============================================
    // ==           STAKING & UNSTAKING          ==
    // ============================================
    /// @notice Simulate updating a user stake position and return the values without updating the struct
    /// @dev Return the simulated up-to-date user stake information
    /// @dev Consider changes from staking or unstaking including burning amount of PE tokens
    /// @dev Attempt to burn Portal Energy Tokens if user unstakes more than available to withdraw
    /// @param _user The user whose stake position is to be updated
    /// @param _amount The amount to add or subtract from the user's stake position
    /// @param _isPositiveAmount True for staking (add), false for unstaking (subtract)
    function getUpdateAccount(
        address _user,
        uint256 _amount,
        bool _isPositiveAmount
    )
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
        uint256 maxLockDifference = maxLockDuration -
            account.lastMaxLockDuration;
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
            portalEnergyNetChange =
                ((portalEnergyEarned + portalEnergyIncrease) * 1e18) /
                denominator;
        }

        /// @dev Calculate the adjustment of Portal Energy from balance change
        uint256 portalEnergyAdjustment = adjustedPE / denominator;

        /// @dev Calculate the amount of Portal Energy Tokens to be burned for unstaking the amount
        portalEnergyTokensRequired = !isPositive &&
            portalEnergyAdjustment >
            (account.portalEnergy + portalEnergyNetChange)
            ? portalEnergyAdjustment -
                (account.portalEnergy + portalEnergyNetChange)
            : 0;

        /// @dev Set the last update time to the current timestamp
        lastUpdateTime = block.timestamp;

        /// @dev Update the last maxLockDuration
        lastMaxLockDuration = maxLockDuration;

        /// @dev Update the user's staked balance and consider stake or unstake
        stakedBalance = isPositive
            ? stakedBalance + amount
            : stakedBalance - amount;

        /// @dev Update the user's max stake debt
        maxStakeDebt = (stakedBalance * maxLockDuration * 1e18) / denominator;

        /// @dev Update the user's portalEnergy and account for stake or unstake
        /// @dev This will be 0 if Portal Energy Tokens must be burned
        portalEnergy = isPositive
            ? account.portalEnergy +
                portalEnergyNetChange +
                portalEnergyAdjustment
            : account.portalEnergy +
                portalEnergyTokensRequired +
                portalEnergyNetChange -
                portalEnergyAdjustment;

        /// @dev Update amount available to withdraw
        availableToWithdraw = portalEnergy >= maxStakeDebt
            ? stakedBalance
            : (stakedBalance * portalEnergy) / maxStakeDebt;
    }

    /// @notice Update user data to the current state
    /// @dev This function updates the user data to the current state
    /// @dev It takes memory inputs and stores them into the user account struct
    /// @param _user The user whose data is to be updated
    /// @param _stakedBalance The current Staked Balance of the user
    /// @param _maxStakeDebt The current maximum Stake Debt of the user
    /// @param _portalEnergy The current Portal Energy of the user
    function _updateAccount(
        address _user,
        uint256 _stakedBalance,
        uint256 _maxStakeDebt,
        uint256 _portalEnergy
    ) private {
        /// @dev Get maxLockDuration from portal
        uint256 maxLockDuration = PORTAL.maxLockDuration();

        /// @dev Update the user´s account data
        Account storage account = accounts[_user];
        account.lastUpdateTime = block.timestamp;
        account.lastMaxLockDuration = maxLockDuration;
        account.stakedBalance = _stakedBalance;
        account.maxStakeDebt = _maxStakeDebt;
        account.portalEnergy = _portalEnergy;

        /// @dev Emit an event with the updated stake information
        emit EventsLib.StakePositionUpdated(
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
    /// @dev Can only be called if LP is active (indirect condition)
    /// @dev Does not follow CEI pattern for optimisation reasons. The handled tokens are trusted.
    /// @dev Update the user account
    /// @dev Update the global tracker of staked principal
    /// @dev Stake the principal into the connected Portal
    /// @param _amount The amount of tokens to stake
    function stake(uint256 _amount) external payable notMigrating nonReentrant {
        /// @dev Rely on input validation from Portal

        /// @dev Get the current state of the user stake in Adapter
        (
            ,
            ,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy,
            ,

        ) = getUpdateAccount(msg.sender, _amount, true);

        /// @dev Update the user stake struct
        _updateAccount(msg.sender, stakedBalance, maxStakeDebt, portalEnergy);

        /// @dev Update the global tracker of staked principal
        totalPrincipalStaked = totalPrincipalStaked + _amount;

        /// @dev Trigger the stake transaction in the Portal & send tokens
        if (address(principalToken) == address(0)) {
            PORTAL.stake{value: _amount}(_amount);
        } else {
            principalToken.safeTransferFrom(msg.sender, address(this), _amount);
            PORTAL.stake(_amount);
        }

        /// @dev Emit event that principal has been staked
        emit EventsLib.PrincipalStaked(msg.sender, _amount);
    }

    /// @notice Serve unstaking requests & withdraw principal from yield source
    /// @dev This function allows users to unstake their tokens
    /// @dev Update the user account
    /// @dev Update the global tracker of staked principal
    /// @dev Burn Portal Energy Tokens from caller to top up account balance if required
    /// @dev Withdraw the matching amount of principal from the yield source (external protocol)
    /// @dev Send the principal tokens to the user
    /// @param _amount The amount of tokens to unstake
    function unstake(uint256 _amount) external nonReentrant {
        /// @dev Rely on input validation from Portal

        /// @dev If the staker had voted for migration, deduct the vote
        if (voted[msg.sender] > 0) {
            voted[msg.sender] = 0;
            votesForMigration -= accounts[msg.sender].stakedBalance;
        }

        /// @dev Get the current state of the user stake
        /// @dev Throws if caller tries to unstake more than stake balance
        /// @dev Will burn Portal Energy tokens if account has insufficient Portal Energy
        (
            ,
            ,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy,
            ,
            uint256 portalEnergyTokensRequired
        ) = getUpdateAccount(msg.sender, _amount, false);

        /// @dev Update the user stake struct
        _updateAccount(msg.sender, stakedBalance, maxStakeDebt, portalEnergy);

        /// @dev Update the global tracker of staked principal
        totalPrincipalStaked -= _amount;

        /// @dev Take Portal Energy Tokens from the user if required
        if (portalEnergyTokensRequired > 0) {
            portalEnergyToken.transferFrom(
                msg.sender,
                address(this),
                portalEnergyTokensRequired
            );

            /// @dev Burn the Portal Energy Tokens to top up PE balance of the Adapter
            PORTAL.burnPortalEnergyToken(
                address(this),
                portalEnergyTokensRequired
            );
        }

        /// @dev Withdraw principal from the Portal to the Adapter
        PORTAL.unstake(_amount);

        /// @dev Send tokens to the user
        if (address(principalToken) == address(0)) {
            (bool sent, ) = payable(msg.sender).call{value: _amount}("");
            if (!sent) {
                revert ErrorsLib.FailedToSendNativeToken();
            }
        } else {
            IERC20(principalToken).safeTransfer(msg.sender, _amount);
        }

        emit EventsLib.PrincipalUnstaked(msg.sender, _amount);
    }

    // ============================================
    // ==          TRADE PORTAL ENERGY           ==
    // ============================================
    /// @notice Users sell PSM into the Adapter to top up portalEnergy balance (Adapter) of a recipient
    /// @dev This function allows users to sell PSM tokens to the contract to increase a recipient portalEnergy
    /// @dev Get the correct price from the quote function
    /// @dev Increase the portalEnergy (Adapter) of the recipient by the amount of portalEnergy received
    /// @dev Transfer the PSM tokens from the caller to the contract, then to the Portal
    /// @param _recipient The recipient of the Portal Energy credit
    /// @param _amountInputPSM The amount of PSM tokens to sell
    /// @param _minReceived The minimum amount of portalEnergy to receive
    /// @param _deadline The unix timestamp that marks the deadline for order execution
    function buyPortalEnergy(
        address _recipient,
        uint256 _amountInputPSM,
        uint256 _minReceived,
        uint256 _deadline
    ) external notMigrating {
        /// @dev Rely on input validation from Portal

        /// @dev Get the amount of portalEnergy received based on the amount of PSM tokens sold
        uint256 amountReceived = PORTAL.quoteBuyPortalEnergy(_amountInputPSM);

        /// @dev Increase the portalEnergy of the recipient by the amount of portalEnergy received
        accounts[_recipient].portalEnergy += amountReceived;

        /// @dev Send PSM from caller to Adapter, then trigger the transaction in the Portal
        /// @dev Approvals are set with different function to save gas
        PSM.transferFrom(msg.sender, address(this), _amountInputPSM);
        PORTAL.buyPortalEnergy(
            address(this),
            _amountInputPSM,
            _minReceived,
            _deadline
        );
    }

    /// @notice Users sell portalEnergy into the Adapter to receive PSM to a recipient address
    /// @dev This function allows users to sell portalEnergy to the Adapter to increase a recipient PSM
    /// @dev Get the output amount from the quote function
    /// @dev Reduce the portalEnergy balance of the caller by the amount of portalEnergy sold
    /// @dev Send PSM to the recipient
    /// @param _recipient The recipient of the PSM tokens
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
        bytes calldata _actionData
    ) external notMigrating {
        /// @dev Validate additional input arguments, let rest float up from Portal
        if (_mode > 2) revert ErrorsLib.InvalidMode();

        /// @dev Get the current state of user stake in Adapter
        (
            ,
            ,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy,
            ,

        ) = getUpdateAccount(msg.sender, 0, true);

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
        PORTAL.sellPortalEnergy(
            address(this),
            _amountInputPE,
            _minReceived,
            _deadline
        );

        /// @dev Assemble the swap data from API to use 1Inch Router
        SwapData memory swap = SwapData(
            _recipient,
            amountReceived,
            _actionData
        );

        /// @dev Transfer PSM, or add liquidity, or exchange on 1Inch and transfer output token
        if (_mode == 0) {
            PSM.safeTransfer(_recipient, amountReceived);
        } else if (_mode == 1) {
            addLiquidity(swap);
        } else {
            swapOneInch(swap, false);
        }
    }

    // ============================================
    // ==         External Integrations          ==
    // ============================================

    function swapOneInch(SwapData memory _swap, bool _forLiquidity) internal {
        /// @dev decode the data for getting _executor, _description, _data.
        (
            address _executor,
            SwapDescription memory _description,
            bytes memory _data,
            ,

        ) = abi.decode(
                _swap.actionData,
                (address, SwapDescription, bytes, uint256, uint256)
            );

        /// @dev Swap via the 1Inch Router
        /// @dev Allowance is increased in separate function to save gas
        (, uint256 spentAmount_) = ONE_INCH_V5_AGGREGATION_ROUTER.swap(
            _executor,
            _description,
            "",
            _data
        );

        /// @dev Send remaining tokens back to user if not called from addLiquidity
        if (!_forLiquidity) {
            uint256 remainAmount = _swap.psmAmount - spentAmount_;
            if (remainAmount > 0) PSM.safeTransfer(msg.sender, remainAmount);
        }
    }

    /// @dev Given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quoteLiquidity(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        if (amountA == 0) revert ErrorsLib.InvalidAmount();
        if (reserveA == 0 || reserveB == 0)
            revert ErrorsLib.InsufficientReserves();
        amountB = (amountA * reserveB) / reserveA;
    }

    /// @dev This function is called when mode = 1 in sellPortalEnergy
    /// @dev Sell some amount of PSM for WETH, then pair in Ramses Pool2
    function addLiquidity(SwapData memory _swap) internal {
        swapOneInch(_swap, true);

        /// @dev Decode the data for getting minPSM and minWETH.
        (, , , uint256 minPSM, uint256 minWeth) = abi.decode(
            _swap.actionData,
            (address, SwapDescription, bytes, uint256, uint256)
        );

        /// @dev This contract shouldn't hold any token, so we pass all tokens.
        uint256 PSMBalance = PSM.balanceOf(address(this));
        uint256 WETHBalance = WETH.balanceOf(address(this));

        /// @dev Get the correct amount of PSM and WETH to add to the Ramses Pool2
        (uint256 amountPSM, uint256 amountWETH) = _addLiquidity(
            PSMBalance,
            WETHBalance,
            minPSM,
            minWeth
        );
        address pair = RAMSES_FACTORY.getPair(
            PSM_TOKEN_ADDRESS,
            WETH_ADDRESS,
            false
        );
        PSM.safeTransfer(pair, amountPSM);
        WETH.safeTransfer(pair, amountWETH);
        IRamsesPair(pair).mint(_swap.recevier);

        uint256 remainPSM = PSMBalance - amountPSM;
        uint256 remainWETH = WETHBalance - amountWETH;
        if (remainPSM > 0) PSM.safeTransfer(msg.sender, PSMBalance);
        if (remainWETH > 0) WETH.safeTransfer(msg.sender, WETHBalance);
    }

    function _addLiquidity(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal view returns (uint256 amountA, uint256 amountB) {
        if (amountADesired < amountAMin) revert ErrorsLib.InvalidAmount();
        if (amountBDesired < amountBMin) revert ErrorsLib.InvalidAmount();

        /// @dev Get the pair
        address pair = RAMSES_FACTORY.getPair(
            PSM_TOKEN_ADDRESS,
            WETH_ADDRESS,
            false
        );

        /// @dev Get the reserves of the pair
        (uint256 reserveA, uint256 reserveB, ) = IRamsesPair(pair)
            .getReserves();

        /// @dev Calculate how much PSM and WETH are required
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = quoteLiquidity(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin)
                    revert ErrorsLib.InvalidAmount();
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quoteLiquidity(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                if (amountAOptimal > amountADesired)
                    revert ErrorsLib.InvalidAmount();
                if (amountAOptimal < amountAMin)
                    revert ErrorsLib.InvalidAmount();
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    // ============================================
    // ==                GENERAL                 ==
    // ============================================
    /// @notice Users can burn their PortalEnergyTokens to increase their portalEnergy in the Adapter
    /// @dev This function allows users to convert Portal Energy Tokens into internal Adapter PE
    /// @dev Burn Portal Energy Tokens of caller and increase portalEnergy in Adapter
    /// @param _amount The amount of portalEnergyToken to burn
    function burnPortalEnergyToken(uint256 _amount) external notMigrating {
        /// @dev Rely on input validation of the Portal

        /// @dev Increase the portalEnergy of the recipient by the amount of portalEnergyToken burned
        accounts[msg.sender].portalEnergy += _amount;

        /// @dev Transfer Portal Energy Tokens to Adapter so that they can be burned
        portalEnergyToken.transferFrom(msg.sender, address(this), _amount);

        /// @dev Burn portalEnergyToken from the Adapter
        PORTAL.burnPortalEnergyToken(address(this), _amount);
    }

    /// @notice Users can mint Portal Energy Tokens using their internal balance
    /// @dev This function controls the minting of Portal Energy Token
    /// @dev Decrease portalEnergy of caller and instruct Portal to mint Portal Energy Tokens to the caller
    /// @param _amount The amount of portalEnergyToken to mint
    function mintPortalEnergyToken(uint256 _amount) external {
        /// @dev Rely on input validation of the Portal

        /// @dev Get the current state of the user stake
        (
            ,
            ,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy,
            ,

        ) = getUpdateAccount(msg.sender, 0, true);

        /// @dev Check that the caller has sufficient portalEnergy to mint the amount of portalEnergyToken
        if (portalEnergy < _amount) {
            revert ErrorsLib.InsufficientBalance();
        }

        /// @dev Reduce the portalEnergy of the caller by the amount of minted tokens
        portalEnergy -= _amount;

        /// @dev Update the user stake struct
        _updateAccount(msg.sender, stakedBalance, maxStakeDebt, portalEnergy);

        /// @dev Mint portal energy tokens to the recipient's wallet
        PORTAL.mintPortalEnergyToken(msg.sender, _amount);
    }

    /// @dev Increase token spending allowances of Adapter holdings
    function increaseAllowances() external {
        PSM.approve(address(PORTAL), MAX_UINT);
        PSM.approve(ONE_INCH_V5_AGGREGATION_ROUTER_CONTRACT_ADDRESS, MAX_UINT);
        portalEnergyToken.approve(address(PORTAL), MAX_UINT);
        /// @dev For ERC20 that require allowance to be 0 before increasing (e.g. USDT) add the following:
        /// principalToken.approve(address(PORTAL), 0);
        principalToken.safeIncreaseAllowance(address(PORTAL), MAX_UINT);
    }

    /// @dev Initialize important variables, called by the constructor
    function setUp() internal {
        principalToken = IERC20(address(PORTAL.PRINCIPAL_TOKEN_ADDRESS()));
        portalEnergyToken = IMintBurnToken(address(PORTAL.portalEnergyToken()));
        denominator = SECONDS_PER_YEAR * PORTAL.DECIMALS_ADJUSTMENT();
    }

    receive() external payable {}

    fallback() external payable {}
}
