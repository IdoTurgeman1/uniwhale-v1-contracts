// SPDX-License-Identifier: BUSL-1.1

import "./interfaces/AbstractERC20Stakeable.sol";
import "./interfaces/AbstractPool.sol";
import "./interfaces/AbstractRegistry.sol";
import "./interfaces/ISwapRouter.sol";
import "./libs/ERC20Fixed.sol";
import "./libs/Errors.sol";
import "./libs/math/FixedPoint.sol";
import "./utils/Allowlistable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

pragma solidity ^0.8.17;

contract LiquidityPool is
  AbstractPool,
  ERC20PausableUpgradeable,
  ReentrancyGuardUpgradeable,
  AbstractERC20Stakeable,
  Allowlistable
{
  using FixedPoint for uint256;
  using ERC20Fixed for ERC20PausableUpgradeable;
  using ERC20Fixed for ERC20;

  ISwapRouter public swapRouter; //settable

  // constant, subject to governance
  uint256 public mintFee;
  uint256 public burnFee;

  // variable
  uint256 public accruedFee;

  bool public transferrable;

  mapping(address => bool) public approvedToken;

  event SetSwapRouterEvent(ISwapRouter swapRouter);
  event CollectAccruedFeeEvent(uint256 accruedFee);
  event SetMintFeeEvent(uint256 mintFee);
  event SetBurnFeeEvent(uint256 burnFee);
  event SetTransferrableEvent(bool transferrable);
  event SetApprovedTokenEvent(address token, bool approved);

  function initialize(
    address _owner,
    string memory _name,
    string memory _symbol,
    ERC20 _baseToken,
    AbstractRegistry _registry,
    ISwapRouter _swapRouter
  ) public initializer {
    __ERC20_init(_name, _symbol);
    __ERC20Pausable_init();
    __AbstractPool_init(_owner, _baseToken, _registry);
    __AbstractERC20StakeableM_init();
    __ReentrancyGuard_init();

    swapRouter = _swapRouter;
    mintFee = 0;
    burnFee = 0;
    accruedFee = 0;
    transferrable = true;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  modifier canTransfer() {
    _require(transferrable, Errors.TRANSFER_NOT_ALLOWED);
    _;
  }

  // governance functions

  function onAllowlist() external onlyOwner {
    _onAllowlist();
  }

  function offAllowlist() external onlyOwner {
    _offAllowlist();
  }

  function addAllowlist(address[] memory _allowed) external onlyOwner {
    _addAllowlist(_allowed);
  }

  function removeAllowlist(address[] memory _removed) external onlyOwner {
    _removeAllowlist(_removed);
  }

  function approveToken(address token, bool approved) external onlyOwner {
    approvedToken[token] = approved;
    emit SetApprovedTokenEvent(token, approved);
  }

  function pauseStaking() external onlyOwner {
    _pauseStaking();
  }

  function unpauseStaking() external onlyOwner {
    _unpauseStaking();
  }

  function setTransferrable(bool _transferrable) external onlyOwner {
    transferrable = _transferrable;
    emit SetTransferrableEvent(transferrable);
  }

  function setSwapRouter(ISwapRouter _swapRouter) external onlyOwner {
    swapRouter = _swapRouter;
    emit SetSwapRouterEvent(swapRouter);
  }

  function setMintFee(uint256 _mintFee) external onlyOwner {
    // audit(B): L01
    _require(_mintFee <= 1e18, Errors.FEE_TOO_HIGH);
    mintFee = _mintFee;
    emit SetMintFeeEvent(mintFee);
  }

  function setBurnFee(uint256 _burnFee) external onlyOwner {
    // audit(B): L01
    _require(_burnFee <= 1e18, Errors.FEE_TOO_HIGH);
    burnFee = _burnFee;
    emit SetBurnFeeEvent(burnFee);
  }

  function collectAccruedFee() external onlyOwner nonReentrant {
    baseToken.transferFixed(msg.sender, accruedFee);
    accruedFee = 0;
    emit CollectAccruedFeeEvent(accruedFee);
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  function addRewardToken(IMintable _rewardToken) external onlyOwner {
    _addRewardToken(_rewardToken);
  }

  function removeRewardToken(IMintable _rewardToken) external onlyOwner {
    _removeRewardToken(_rewardToken);
  }

  // privilidged functions

  function transferBase(
    address _to,
    uint256 _amount
  ) external override onlyApproved {
    baseToken.transferFixed(_to, _amount);
  }

  function transferFromPool(
    address _token,
    address _to,
    uint256 _amount
  ) external override onlyApproved {
    _require(_token == address(baseToken), Errors.TOKEN_MISMATCH);
    baseToken.transferFixed(_to, _amount);
  }

  // external functions

  function stake(
    uint256 amount
  )
    external
    override
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    onlyAllowlisted
  {
    _stake(msg.sender, msg.sender, amount);
  }

  function unstake(
    uint256 amount
  )
    external
    override
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    onlyAllowlisted
  {
    _unstake(msg.sender, amount);
  }

  function claim()
    external
    override
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    onlyAllowlisted
  {
    _claim(msg.sender);
  }

  function mint(
    uint256 amountIn
  ) external whenNotPaused nonReentrant onlyAllowlisted {
    _mintFrom(msg.sender, msg.sender, amountIn, 0, address(baseToken), 0);
  }

  function mint(
    uint256 amountIn,
    uint256 amountOutMinimum,
    address tokenIn,
    uint24 poolFee
  ) external whenNotPaused nonReentrant onlyAllowlisted {
    _mintFrom(
      msg.sender,
      msg.sender,
      amountIn,
      amountOutMinimum,
      tokenIn,
      poolFee
    );
  }

  function mintAndStake(
    uint256 amountIn
  ) external whenNotPaused nonReentrant whenStakingNotPaused onlyAllowlisted {
    uint256 minted = _mintFrom(
      msg.sender,
      address(this),
      amountIn,
      0,
      address(baseToken),
      0
    );
    _stake(address(this), msg.sender, minted);
  }

  function mintAndStake(
    uint256 amountIn,
    uint256 amountOutMinimum,
    address tokenIn,
    uint24 poolFee
  ) external whenNotPaused nonReentrant whenStakingNotPaused onlyAllowlisted {
    uint256 minted = _mintFrom(
      msg.sender,
      address(this),
      amountIn,
      amountOutMinimum,
      tokenIn,
      poolFee
    );
    _stake(address(this), msg.sender, minted);
  }

  function burn(
    uint256 _amount
  ) external whenNotPaused nonReentrant onlyAllowlisted {
    _burn(_amount, 0, address(baseToken), 0);
  }

  function burn(
    uint256 _amount,
    uint256 amountOutMinimum,
    address tokenOut,
    uint24 poolFee
  ) external whenNotPaused nonReentrant onlyAllowlisted {
    _burn(_amount, amountOutMinimum, tokenOut, poolFee);
  }

  function unstakeAndBurn(
    uint256 amountIn
  ) external whenNotPaused nonReentrant whenStakingNotPaused onlyAllowlisted {
    _require(
      amountIn <= _stakedByStaker[msg.sender],
      Errors.INVALID_BURN_AMOUNT
    );
    _unstake(msg.sender, amountIn);
    _burn(amountIn, 0, address(baseToken), 0);
  }

  function unstakeAndBurn(
    uint256 amountIn,
    uint256 amountOutMinimum,
    address tokenOut,
    uint24 poolFee
  ) external whenNotPaused nonReentrant whenStakingNotPaused onlyAllowlisted {
    _require(
      amountIn <= _stakedByStaker[msg.sender],
      Errors.INVALID_BURN_AMOUNT
    );
    _unstake(msg.sender, amountIn);
    _burn(amountIn, amountOutMinimum, tokenOut, poolFee);
  }

  function getBaseBalance() external view returns (uint256) {
    return _getBaseBalance();
  }

  // internal functions

  function _mintFrom(
    address sender,
    address receiver,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address tokenIn,
    uint24 poolFee
  ) internal returns (uint256) {
    uint256 baseBalance = _getBaseBalance();
    uint256 balance = ERC20PausableUpgradeable(this).totalSupplyFixed();
    uint256 amountGross = amountIn;

    if (tokenIn == address(baseToken)) {
      baseToken.transferFromFixed(sender, address(this), amountGross);
    } else {
      _require(approvedToken[tokenIn], Errors.APPROVED_TOKEN_ONLY);
      ERC20(tokenIn).transferFromFixed(sender, address(this), amountIn);
      // audit(B): H02
      uint256 _amountIn = amountIn.min(
        ERC20(tokenIn).balanceOfFixed(address(this))
      );
      ERC20(tokenIn).approveFixed(address(swapRouter), _amountIn);

      amountGross = swapRouter.swapGivenIn(
        ISwapRouter.SwapGivenInInput(
          tokenIn,
          address(baseToken),
          amountIn,
          amountOutMinimum,
          poolFee
        )
      );
    }
    uint256 fee = amountGross.mulDown(mintFee);
    uint256 amountNet = amountGross.sub(fee);
    accruedFee += fee;
    uint256 returnBalance = baseBalance == 0
      ? amountNet
      : amountNet.mulDown(balance).divDown(baseBalance);

    // audit(B): H01
    _require(returnBalance != 0, Errors.INVALID_MINT_AMOUNT);

    _mint(receiver, returnBalance);

    return returnBalance;
  }

  function _burn(
    uint256 amountIn,
    uint256 amountOutMinimum,
    address tokenOut,
    uint24 poolFee
  ) internal {
    _require(
      amountIn <= ERC20PausableUpgradeable(this).balanceOfFixed(msg.sender),
      Errors.INVALID_BURN_AMOUNT
    );

    uint256 thisBalance = ERC20PausableUpgradeable(this).totalSupplyFixed();
    _require(thisBalance > 0, Errors.NOTHING_TO_BURN);

    uint256 baseBalance = _getBaseBalance();

    uint256 returnBalanceGross = amountIn.mulDown(baseBalance).divDown(
      thisBalance
    );

    _require(
      baseBalance.sub(registry.minCollateral()) >= returnBalanceGross,
      Errors.BURN_EXCEEDS_EXCESS
    );

    uint256 fee = returnBalanceGross.mulDown(burnFee);
    uint256 returnBalanceNet = returnBalanceGross.sub(fee);
    accruedFee += fee;

    _burn(msg.sender, amountIn);

    if (tokenOut == address(baseToken)) {
      baseToken.transferFixed(msg.sender, returnBalanceNet);
    } else {
      baseToken.approveFixed(address(swapRouter), returnBalanceNet);
      ERC20(tokenOut).transferFixed(
        msg.sender,
        swapRouter.swapGivenIn(
          ISwapRouter.SwapGivenInInput(
            address(baseToken),
            tokenOut,
            returnBalanceNet,
            amountOutMinimum,
            poolFee
          )
        )
      );
    }
  }

  function _transfer(
    address from,
    address to,
    uint256 amount
  ) internal override whenNotPaused canTransfer {
    super._transfer(from, to, amount);
  }

  function _getBaseBalance() private view returns (uint256) {
    return baseToken.balanceOfFixed(address(this)).sub(accruedFee);
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  )
    internal
    virtual
    override(ERC20Upgradeable, ERC20PausableUpgradeable)
    whenNotPaused
    canTransfer
  {
    super._beforeTokenTransfer(from, to, amount);
  }
}
