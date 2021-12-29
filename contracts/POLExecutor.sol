// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@uniswap/lib/contracts/libraries/Babylonian.sol";

import "./interfaces/ITreasury.sol";
import "./interfaces/IUniswapV2Pair.sol";

interface IUniswapV2Router {
  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external returns (uint256[] memory amounts);
}

contract POLExecutor is Ownable {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  // The address of ALD Token.
  address private constant ald = 0xb26C4B3Ca601136Daf98593feAeff9E0CA702a8D;
  // The address of USDC Token.
  address private constant usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  // The address of WETH Token.
  address private constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  // The address of Aladdin DAO treasury.
  address private constant treasury = 0x5aa403275cdf5a487D195E8306FD0628D4F5747B;
  // The address of ALD/WETH pair.
  address private constant aldweth = 0xED6c2F053AF48Cba6cBC0958124671376f01A903;
  // The address of ALD/USDC pair.
  address private constant aldusdc = 0xaAa2bB0212Ec7190dC7142cD730173b0A788eC31;

  /// Mapping from whilelist address to status, true: whitelist, false: not whitelist.
  mapping(address => bool) public whitelist;

  modifier onlyWhitelist() {
    require(whitelist[msg.sender], "POLExecutor: only whitelist");
    _;
  }

  function updateWhitelist(address[] memory list, bool status) external onlyOwner {
    for (uint256 i = 0; i < list.length; i++) {
      whitelist[list[i]] = status;
    }
  }

  /// @dev Withdraw token from treasury and buy ald token.
  /// @param token The address of token to withdraw.
  /// @param amount The amount of token to withdraw.
  /// @param router The address of router to use, usually uniswap or sushiswap.
  /// @param toUSDC The path from token to USDC.
  /// @param toWETH The path from token to WETH.
  /// @param minALDAmount The minimum amount of ALD should buy.
  function withdrawAndSwapToALD(
    address token,
    uint256 amount,
    address router,
    address[] calldata toUSDC,
    address[] calldata toWETH,
    uint256 minALDAmount
  ) external onlyWhitelist {
    require(token != ald, "POLExecutor: token should not be ald");

    ITreasury(treasury).withdraw(token, amount);
    uint256 aldAmount;

    // swap to usdc and then to ald
    uint256 usdcAmount;
    if (token == usdc) {
      usdcAmount = amount / 2;
    } else {
      require(toUSDC[toUSDC.length - 1] == usdc, "POLExecutor: invalid toUSDC path");
      usdcAmount = _swapTo(token, amount / 2, router, toUSDC);
    }
    amount = amount - amount / 2;
    if (usdcAmount > 0) {
      aldAmount = aldAmount.add(_swapToALD(aldusdc, usdc, usdcAmount));
    }
    // swap to weth and then to ald
    uint256 wethAmount;
    if (token == weth) {
      wethAmount = amount;
    } else {
      require(toWETH[toWETH.length - 1] == weth, "POLExecutor: invalid toUSDC path");
      wethAmount = _swapTo(token, amount, router, toWETH);
    }
    if (wethAmount > 0) {
      aldAmount = aldAmount.add(_swapToALD(aldweth, weth, wethAmount));
    }

    require(aldAmount >= minALDAmount, "POLExecutor: not enough ald amount");
  }

  /// @dev Withdraw token from treasury, swap and add liquidity
  /// @param token The address of token to withdraw.
  /// @param amount The amount of token to withdraw.
  /// @param router The address of router to use, usually uniswap or sushiswap.
  /// @param toUSDC The path from token to USDC.
  /// @param toWETH The path from token to WETH.
  /// @param minALDUSDCLP The minimum amount of ALD USDC LP should get.
  /// @param minALDWETHLP The minimum amount of ALD USDC LP should get.
  function withdrawAndSwapToLP(
    address token,
    uint256 amount,
    address router,
    address[] calldata toUSDC,
    address[] calldata toWETH,
    uint256 minALDUSDCLP,
    uint256 minALDWETHLP
  ) external onlyWhitelist {
    require(whitelist[msg.sender], "POLExecutor: only whitelist");
    ITreasury(treasury).withdraw(token, amount);

    // swap to usdc and then to aldusdc lp
    uint256 usdcAmount;
    if (token == usdc) {
      usdcAmount = amount / 2;
    } else {
      require(toUSDC[toUSDC.length - 1] == usdc, "POLExecutor: invalid toUSDC path");
      usdcAmount = _swapTo(token, amount / 2, router, toUSDC);
    }
    amount = amount - amount / 2;
    if (usdcAmount > 0) {
      uint256 lpAmount = _swapToLP(aldusdc, usdc, usdcAmount);
      require(lpAmount >= minALDUSDCLP, "not enough ALDUSDC LP");
    }

    // swap to weth and then to aldweth lp
    uint256 wethAmount;
    if (token == weth) {
      wethAmount = amount;
    } else {
      require(toWETH[toWETH.length - 1] == weth, "POLExecutor: invalid toUSDC path");
      wethAmount = _swapTo(token, amount, router, toWETH);
    }
    if (wethAmount > 0) {
      uint256 lpAmount = _swapToLP(aldweth, weth, wethAmount);
      require(lpAmount >= minALDWETHLP, "not enough ALDWETH LP");
    }
  }

  /// @dev Withdraw ALD from treasury, swap and add liquidity.
  /// @param amount The amount of ald token to withdraw.
  /// @param minALDUSDCLP The minimum amount of ALD USDC LP should get.
  /// @param minALDWETHLP The minimum amount of ALD USDC LP should get.
  function withdrawALDAndSwapToLP(
    uint256 amount,
    uint256 minALDUSDCLP,
    uint256 minALDWETHLP
  ) external onlyWhitelist {
    require(whitelist[msg.sender], "POLExecutor: only whitelist");
    ITreasury(treasury).manage(ald, amount);

    uint256 aldusdcAmount = _swapToLP(aldusdc, ald, amount / 2);
    require(aldusdcAmount >= minALDUSDCLP, "POLExecutor: not enough ALDUSDC LP");

    uint256 aldwethAmount = _swapToLP(aldweth, ald, amount - amount / 2);
    require(aldwethAmount >= minALDWETHLP, "POLExecutor: not enough ALDWETH LP");
  }

  /// @dev Withdraw ALD and token from treasury, and then add liquidity.
  /// @param aldAmount The amount of ald token to withdraw.
  /// @param token The address of other token, should be usdc or weth.
  /// @param minLPAmount The minimum lp amount should get.
  function withdrawAndAddLiquidity(
    uint256 aldAmount,
    address token,
    uint256 minLPAmount
  ) external onlyWhitelist {
    address pair;
    uint256 reserve0;
    uint256 reserve1;
    if (token == usdc) {
      (reserve0, reserve1, ) = IUniswapV2Pair(aldusdc).getReserves();
      pair = aldusdc;
    } else if (token == weth) {
      (reserve0, reserve1, ) = IUniswapV2Pair(aldweth).getReserves();
      pair = aldweth;
    } else {
      revert("POLExecutor: token not supported");
    }
    if (ald > token) {
      (reserve0, reserve1) = (reserve1, reserve0);
    }
    uint256 tokenAmount = aldAmount.mul(reserve1).div(reserve0);

    ITreasury(treasury).manage(ald, aldAmount);
    ITreasury(treasury).withdraw(token, tokenAmount);
    IERC20(ald).safeTransfer(pair, aldAmount);
    IERC20(token).safeTransfer(pair, tokenAmount);

    uint256 lpAmount = IUniswapV2Pair(pair).mint(treasury);
    require(lpAmount >= minLPAmount, "POLExecutor: not enough lp");
  }

  function _ensureAllowance(
    address token,
    address spender,
    uint256 amount
  ) internal {
    if (IERC20(token).allowance(address(this), spender) < amount) {
      IERC20(token).safeApprove(spender, 0);
      IERC20(token).safeApprove(spender, amount);
    }
  }

  function _swapTo(
    address token,
    uint256 amount,
    address router,
    address[] memory path
  ) internal returns (uint256) {
    require(path.length >= 2 && path[0] == token, "POLExecutor: invalid swap path");
    _ensureAllowance(token, router, amount);
    uint256[] memory amounts = IUniswapV2Router(router).swapExactTokensForTokens(
      amount,
      0,
      path,
      address(this),
      block.timestamp
    );
    return amounts[amounts.length - 1];
  }

  function _swapToALD(
    address pair,
    address token,
    uint256 amount
  ) internal returns (uint256) {
    uint256 rIn;
    uint256 rOut;
    if (ald < token) {
      (rOut, rIn, ) = IUniswapV2Pair(pair).getReserves();
    } else {
      (rIn, rOut, ) = IUniswapV2Pair(pair).getReserves();
    }
    uint256 amountWithFee = amount.mul(997);
    uint256 output = rOut.mul(amountWithFee).div(rIn.mul(1000).add(amountWithFee));
    IERC20(token).safeTransfer(pair, amount);
    if (ald < token) {
      IUniswapV2Pair(pair).swap(output, 0, treasury, new bytes(0));
    } else {
      IUniswapV2Pair(pair).swap(0, output, treasury, new bytes(0));
    }
    return output;
  }

  function _swapToLP(
    address pair,
    address token,
    uint256 amount
  ) internal returns (uint256) {
    // first swap some part of token to other token.
    uint256 rIn;
    uint256 rOut;
    address token0 = IUniswapV2Pair(pair).token0();
    address token1 = IUniswapV2Pair(pair).token1();
    if (token0 == token) {
      (rIn, rOut, ) = IUniswapV2Pair(pair).getReserves();
    } else {
      (rOut, rIn, ) = IUniswapV2Pair(pair).getReserves();
    }
    // (amount - x) : x * rOut * 997 / (rIn * 1000 + 997 * x) = (rIn + amount) : rOut
    // => 997 * x^2 + 1997 * rIn * x - rIn * amount * 1000 = 0
    // => x = (sqrt(rIn^2 * 3988009 + 3988000 * amount * rIn) - 1997 * rIn) / 1994
    uint256 swapAmount = Babylonian.sqrt(rIn.mul(amount.mul(3988000).add(rIn.mul(3988009)))).sub(rIn.mul(1997)) / 1994;
    uint256 amountWithFee = swapAmount.mul(997);
    uint256 output = rOut.mul(amountWithFee).div(rIn.mul(1000).add(amountWithFee));
    IERC20(token).safeTransfer(pair, swapAmount);
    if (token0 == token) {
      IUniswapV2Pair(pair).swap(0, output, address(this), new bytes(0));
      IERC20(token1).safeTransfer(pair, output);
    } else {
      IUniswapV2Pair(pair).swap(output, 0, address(this), new bytes(0));
      IERC20(token0).safeTransfer(pair, output);
    }

    // then add liquidity
    IERC20(token).safeTransfer(pair, amount.sub(swapAmount));
    return IUniswapV2Pair(pair).mint(treasury);
  }
}
