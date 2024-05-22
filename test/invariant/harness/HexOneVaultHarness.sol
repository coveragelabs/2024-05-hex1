// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import {HexOneToken} from "../../../src/HexOneToken.sol";

import {ERC721} from "../../../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "../../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenUtils} from "../../../src/utils/TokenUtils.sol";

import {IHexOneVault} from "../../../src/interfaces/IHexOneVault.sol";
import {IHexOneToken} from "../../../src/interfaces/IHexOneToken.sol";
import {IHexOnePriceFeed} from "../../../src/interfaces/IHexOnePriceFeed.sol";
import {IHexToken} from "../../../src/interfaces/IHexToken.sol";

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IPulseXRouter02 as IPulseXRouter} from "../../../src/interfaces/pulsex/IPulseXRouter.sol";
import {IHedron} from "../../../src/interfaces/IHedron.sol";

/**
 *  @title Hex One Vault
 *  @dev turns hex stakes into nfts with hex one borrowing functionality.
 */
contract HexOneVaultHarness is ERC721, AccessControl, ReentrancyGuard, IHexOneVault {
    using SafeERC20 for IERC20;

    /// @dev access control bootstrap role.
    bytes32 public constant BOOTSTRAP_ROLE = keccak256("BOOTSTRAP_ROLE");

    /// @dev used to decode daily data.
    uint256 private constant HEARTS_UINT_SHIFT = 72;
    /// @dev bitmask to retrieve the first parameter of the encoded data.
    uint256 private constant HEARTS_MASK = (1 << HEARTS_UINT_SHIFT) - 1;

    /// @dev slot 0
    address public ROUTER_V2;
    /// @dev slot 1
    address public HX;
    /// @dev slot 2
    address public HDRN;
    /// @dev slot 3
    address public WPLS;
    /// @dev slot 4
    address public DAI;
    /// @dev slot 5
    address public USDC;
    /// @dev slot 6
    address public USDT;

    /// @dev duration of the hex stakes.
    uint16 public constant DURATION = 5555;
    /// @dev period after stake duration in which the stake becomes liquidatable.
    uint16 public constant GRACE_PERIOD = 7;
    /// @dev minimum healh ratio, if health ratio is below 250% in bps stakes become liquidatable.
    uint16 public constant MIN_HEALTH_RATIO = 25_000;
    /// @dev precision scale multipler, represents 100% in bps.
    uint16 public constant FIXED_POINT = 10_000;
    /// @dev represents the buyback fee of 1% in bps.
    uint16 public constant FEE = 100;

    /// @dev address of the price feed.
    address public immutable feed;
    /// @dev address of the hex one token.
    address public immutable hex1;

    /// @dev user => Stake
    mapping(uint256 => Stake) public stakes;
    /// @dev ever incrementing token id of stakes created in the vault.
    uint256 internal id;

    /// @dev flag that stores if the buyback status.
    bool public buybackEnabled;

    /**
     *  @dev gives bootstrap role to the msg.sender which is the bootstrap.
     *  @param _feed address of the price feed.
     *  @param _bootstrap address of the bootstrap.
     */
    constructor(address _feed, address _bootstrap) ERC721("HEX1 Debt Title", "HDT") {
        if (_feed == address(0)) revert ZeroAddress();
        if (_bootstrap == address(0)) revert ZeroAddress();

        feed = _feed;
        hex1 = address(new HexOneToken());

        _grantRole(BOOTSTRAP_ROLE, _bootstrap);
    }

    function initialize(
        address _routerV2,
        address _hex,
        address _hdrn,
        address _wpls,
        address _dai,
        address _usdc,
        address _usdt
    ) external {
        ROUTER_V2 = _routerV2;
        HX = _hex;
        HDRN = _hdrn;
        WPLS = _wpls;
        DAI = _dai;
        USDC = _usdc;
        USDT = _usdt;
    }

    /**
     *  @dev required by openzeppelin libraries.
     */
    function supportsInterface(bytes4 _interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(_interfaceId);
    }

    /**
     *  @dev returns the current day for the hex contract.
     */
    function currentDay() public view returns (uint256) {
        return IHexToken(HX).currentDay();
    }

    /**
     *  @dev returns the health ratio for a given token id.
     *  @param _id token id of the stake.
     */
    function healthRatio(uint256 _id) public view returns (uint256 ratio) {
        Stake memory stake = stakes[_id];

        uint256 hxAmount;
        if (currentDay() >= stake.end) {
            hxAmount = stake.amount + _accrued(_id, stake.start, stake.end);
        } else {
            hxAmount = stake.amount + _accrued(_id, stake.start, currentDay()) + _payout(_id);
        }

        if (stake.debt != 0) {
            ratio = (_hxQuote(hxAmount) * FIXED_POINT) / stake.debt;
        }
    }

    /**
     *  @dev returns the max borrowable amount in hex one for a given token id.
     *  @param _id token id of the stake.
     */
    function maxBorrowable(uint256 _id) public view returns (uint256 amount) {
        Stake memory stake = stakes[_id];

        uint256 hxQuote = _hxQuote(stake.amount);
        if (hxQuote > stake.debt) {
            amount = hxQuote - stake.debt;
        }
    }

    /**
     *  @dev enables hex one buyback functionality.
     *  @notice can only be called by the bootstrap once when the airdrop starts.
     */
    function enableBuyback() external onlyRole(BOOTSTRAP_ROLE) {
        buybackEnabled = true;
    }

    /**
     *  @dev creates an hex stake with a duration of 5555 days.
     *  @notice if buyback is enabled the resulting fee is used to buyback hex one in the market and burn.
     *  @param _amount amount of hex.
     */
    function deposit(uint256 _amount) external nonReentrant returns (uint256 tokenId) {
        if (_amount == 0) revert InvalidAmount();

        IERC20(HX).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 fee;
        if (buybackEnabled) {
            fee = _computeFee(_amount);
            _amount = _amount - fee;
        }

        tokenId = id++;

        _mint(msg.sender, tokenId);

        IHexToken(HX).stakeStart(_amount, DURATION);

        IHexToken.StakeStore memory stakeStore = IHexToken(HX).stakeLists(address(this), tokenId);
        stakes[tokenId] = Stake({
            debt: 0,
            amount: stakeStore.stakedHearts,
            shares: stakeStore.stakeShares,
            param: stakeStore.stakeId,
            start: stakeStore.lockedDay,
            end: stakeStore.lockedDay + DURATION
        });

        if (fee != 0) {
            _buyback(fee);
        }

        emit Deposited(msg.sender, tokenId, _amount);
    }

    /**
     *  @dev function to end an hex stake if stake is mature.
     *  @notice claims hedron tokens.
     *  @param _id token id of the stake.
     */
    function withdraw(uint256 _id) external nonReentrant returns (uint256 hxAmount, uint256 hdrnAmount) {
        if (msg.sender != ownerOf(_id)) revert InvalidOwner();

        Stake memory stake = stakes[_id];
        if (currentDay() < stake.end) revert StakeNotMature();

        _burn(_id);

        delete stakes[_id];

        if (stake.debt != 0) {
            IHexOneToken(hex1).burn(msg.sender, stake.debt);
            emit Repaid(msg.sender, _id, stake.debt);
        }

        hdrnAmount = _claimHdrn(_id, stake.param);
        hxAmount = _claimHx(_id, stake.param);

        IERC20(HDRN).safeTransfer(msg.sender, hdrnAmount);
        IERC20(HX).safeTransfer(msg.sender, hxAmount);

        emit Withdrawn(msg.sender, _id, hxAmount, hdrnAmount);
    }

    /**
     *  @dev function to liquidate stakes after stake duration + grace period has passed.
     *  @notice if stake has debt it must be repaid.
     *  @param _id token id of the stake.
     */
    function liquidate(uint256 _id) external nonReentrant returns (uint256 hxAmount, uint256 hdrnAmount) {
        Stake memory stake = stakes[_id];
        if (currentDay() < stake.end + GRACE_PERIOD) revert StakeNotLiquidatable();

        _burn(_id);

        delete stakes[_id];

        if (stake.debt != 0) {
            IHexOneToken(hex1).burn(msg.sender, stake.debt);
            emit Repaid(msg.sender, _id, stake.debt);
        }

        hdrnAmount = _claimHdrn(_id, stake.param);
        hxAmount = _claimHx(_id, stake.param);

        IERC20(HDRN).safeTransfer(msg.sender, hdrnAmount);
        IERC20(HX).safeTransfer(msg.sender, hxAmount);

        emit Liquidated(msg.sender, _id, hxAmount, hdrnAmount);
    }

    /**
     *  @dev function to repay hex one and reduce debt.
     *  @param _id token id of the stake.
     *  @param _amount amount of hex one to repay.
     */
    function repay(uint256 _id, uint256 _amount) external nonReentrant {
        if (msg.sender != ownerOf(_id)) revert InvalidOwner();
        if (_amount == 0) revert InvalidAmount();

        stakes[_id].debt -= _amount;

        IHexOneToken(hex1).burn(msg.sender, _amount);

        emit Repaid(msg.sender, _id, _amount);
    }

    /**
     *  @dev function to borrow agaisnt an hex stake.
     *  @notice reverts if the new debt amount results in a liquidatable stake.
     *  @param _id token id of the stake.
     *  @param _amount amount of hex one to borrow.
     */
    function borrow(uint256 _id, uint256 _amount) external nonReentrant {
        if (msg.sender != ownerOf(_id)) revert InvalidOwner();
        if (_amount == 0) revert InvalidAmount();

        Stake memory stake = stakes[_id];
        if (currentDay() >= stake.end) revert StakeMature();

        if (maxBorrowable(_id) < _amount) revert MaxBorrowExceeded();

        stakes[_id].debt += _amount;

        if (healthRatio(_id) < MIN_HEALTH_RATIO) revert HealthRatioTooLow();

        IHexOneToken(hex1).mint(msg.sender, _amount);

        emit Borrowed(msg.sender, _id, _amount);
    }

    /**
     *  @dev transfers stake ownership to the msg sender if stake healh ratio is below the minimium.
     *  @param _id token id of the stake.
     *  @param _amount amount of hex one to repay the debt.
     */
    function take(uint256 _id, uint256 _amount) external nonReentrant {
        Stake memory stake = stakes[_id];
        if (currentDay() >= stake.end + GRACE_PERIOD) revert StakeNotLiquidatable();

        if (healthRatio(_id) == 0 || healthRatio(_id) >= MIN_HEALTH_RATIO) {
            revert HealthRatioTooHigh();
        }

        uint256 minAmount = stake.debt / 2;
        if (_amount < minAmount) revert NotEnoughToTake();

        stakes[_id].debt -= _amount;

        if (healthRatio(_id) < MIN_HEALTH_RATIO) revert HealthRatioTooLow();

        _transfer(ownerOf(_id), msg.sender, _id);

        IHexOneToken(hex1).burn(msg.sender, _amount);

        emit Took(msg.sender, _id, _amount);
    }

    /**
     *  @dev buyback hex one in the market and burn it.
     *  @param _fee amount used to buyback.
     */
    function _buyback(uint256 _fee) private {
        IERC20(HX).approve(ROUTER_V2, _fee);

        address[] memory path = new address[](4);
        path[0] = HX;
        path[1] = WPLS;
        path[2] = DAI;
        path[3] = hex1;

        uint256[] memory amounts =
            IPulseXRouter(ROUTER_V2).swapExactTokensForTokens(_fee, 0, path, address(this), block.timestamp);

        IHexOneToken(hex1).burn(address(this), amounts[amounts.length - 1]);
    }

    /**
     *  @dev claim hex after stake duration has ended.
     *  @param _id token id of the stake.
     *  @param _param stake id param of the hex stake.
     */
    function _claimHx(uint256 _id, uint40 _param) private returns (uint256 hxAmount) {
        uint256 balanceBefore = IERC20(HX).balanceOf(address(this));
        IHexToken(HX).stakeEnd(_id, _param);
        uint256 balanceAfter = IERC20(HX).balanceOf(address(this));

        hxAmount = balanceAfter - balanceBefore;
    }

    /**
     *  @dev claim hedron after stake duration has ended.
     *  @param _id token id of the stake.
     *  @param _param stake id param of the hex stake.
     */
    function _claimHdrn(uint256 _id, uint40 _param) private returns (uint256 hdrnAmount) {
        hdrnAmount = IHedron(HDRN).mintNative(_id, _param);
    }

    /**
     *  @dev returns an hex quote in usd based on average price of three pairs.
     *  @param _amountIn amount of hex.
     */
    function _hxQuote(uint256 _amountIn) private view returns (uint256 hxQuote) {
        uint256 hexDaiQuote = _quote(HX, _amountIn, DAI);
        uint256 hexUsdcQuote = _convert(USDC, _quote(HX, _amountIn, USDC));
        uint256 hexUsdtQuote = _convert(USDT, _quote(HX, _amountIn, USDT));
        hxQuote = (hexDaiQuote + hexUsdcQuote + hexUsdtQuote) / 3;
    }

    /**
     *  @dev returns a quote based on the amount and tokens given as inputs.
     *  @param _tokenIn address of the token the amount in is.
     *  @param _amountIn amount we want a code quote for.
     *  @param _tokenOut address of the token the quote is returned.
     */
    function _quote(address _tokenIn, uint256 _amountIn, address _tokenOut) private view returns (uint256 amountOut) {
        amountOut = IHexOnePriceFeed(feed).quote(_tokenIn, _amountIn, _tokenOut);
    }

    /**
     *  @dev converts an amount for a given token to 18 decimals precision.
     *  @param _token token being converted.
     *  @param _amountIn amount being converted.
     */
    function _convert(address _token, uint256 _amountIn) private view returns (uint256 amountOut) {
        uint8 decimals = TokenUtils.expectDecimals(_token);
        if (decimals >= 18) {
            amountOut = _amountIn / (10 ** (decimals - 18));
        } else {
            amountOut = _amountIn * (10 ** (18 - decimals));
        }
    }

    /**
     *  @dev returns the already accrued hex payout for a given stake.
     *  @param _id token id of the stake.
     *  @param _start initial day stake was created.
     *  @param _end final or last day stake accrued rewards.
     */
    function _accrued(uint256 _id, uint256 _start, uint256 _end) private view returns (uint256 hxAccrued) {
        Stake memory stake = stakes[_id];

        if (currentDay() > stakes[_id].start) {
            uint256[] memory data = IHexToken(HX).dailyDataRange(_start, _end);

            uint256 length = data.length;
            for (uint256 i; i < length; ++i) {
                (uint256 payout, uint256 shares) = _decodeDailyData(data[i]);
                hxAccrued += (stake.shares * payout) / shares;
            }
        }
    }

    /**
     *  @dev estimates the future hex payout based on the last day hex daily data was updated.
     *  @notice the t-shares payout rate is used for the remaining days of the hex stake.
     *  @param _id token id of the stake.
     */
    function _payout(uint256 _id) private view returns (uint256 hxFuturePayout) {
        (uint256 payout, uint256 shares,) = IHexToken(HX).dailyData(_lastDataDay());

        Stake memory stake = stakes[_id];
        hxFuturePayout = (stake.shares * payout * (stake.end - currentDay())) / shares;
    }

    /**
     *  @dev returns the last day hex daily data was updated.
     */
    function _lastDataDay() private view returns (uint256 lastDay) {
        uint256[13] memory globalInfo = IHexToken(HX).globalInfo();
        lastDay = globalInfo[4] - 1;
    }

    /**
     *  @dev returns the the total payout and total shares of a given day.
     *  @notice first 72 bits store the total payout, and the second 72 bits store the total shares.
     *  @param _data encoded hex daily data.
     */
    function _decodeDailyData(uint256 _data) private pure returns (uint256 payout, uint256 shares) {
        payout = _data & HEARTS_MASK;
        shares = (_data >> HEARTS_UINT_SHIFT) & HEARTS_MASK;
    }

    /**
     *  @dev returns the resulting fee based on the deposited amount.
     *  @param _amount amount to compute the fee over.
     */
    function _computeFee(uint256 _amount) private pure returns (uint256 fee) {
        fee = (_amount * FEE) / FIXED_POINT;
    }
}
