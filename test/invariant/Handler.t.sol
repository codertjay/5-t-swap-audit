// SPDX-License-Identifier:  MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {TSwapPool} from "../../src/TSwapPool.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    TSwapPool pool;
    ERC20Mock weth;
    ERC20Mock poolToken;

    address liquidityProvider = makeAddr("lp");
    address swapper = makeAddr("swapper");

    // Ghost variables
    int256 public  startingY;
    int256 public  startingX;

    int256  public expectedDeltaY;
    int256 public  expectedDeltaX;

    int256 public  actualDeltaX;
    int256  public actualDeltaY;



    constructor(TSwapPool _pool) {
        pool = _pool;
        weth = ERC20Mock(_pool.getWeth());
        poolToken = ERC20Mock(_pool.getPoolToken());
    }

    function swapToolTokenForWethBasedOnOutputWeth(uint256 outputWethAmount) public {
        if (weth.balanceOf(address(pool)) <= pool.getMinimumWethDepositAmount()) {
            return;
        }
        outputWethAmount = bound(outputWethAmount, pool.getMinimumWethDepositAmount(), weth.balanceOf(address(pool)));
        // If these two values are the same, we will divide by 0
        if (outputWethAmount == weth.balanceOf(address(pool))) {
            return;
        }
        uint256 poolTokenAmount = pool.getInputAmountBasedOnOutput(
            outputWethAmount, // outputAmount
            poolToken.balanceOf(address(pool)), // inputReserves
            weth.balanceOf(address(pool)) // outputReserves
        );
        if (poolTokenAmount > type(uint64).max) {
            return;
        }
        // We * -1 since we are removing WETH from the system
        startingY = int256(weth.balanceOf(address(pool)));
        startingX = int256(poolToken.balanceOf(address(pool)));

        expectedDeltaY = int256(outputWethAmount) * - 1;
        expectedDeltaX = int256(poolTokenAmount);

        // Mint any necessary amount of pool tokens
        if (poolToken.balanceOf(swapper) < poolTokenAmount) {
            poolToken.mint(swapper, poolTokenAmount - poolToken.balanceOf(swapper) + 1);
        }

        vm.startPrank(swapper);
        // Approve tokens so they can be pulled by the pool during the swap
        poolToken.approve(address(pool), type(uint256).max);

        // Execute swap, giving pool tokens, receiving WETH
        pool.swapExactOutput({
            inputToken: poolToken,
            outputToken: weth,
            outputAmount: outputWethAmount,
            deadline: uint64(block.timestamp)
        });
        vm.stopPrank();

        // Actual
        uint256 endingY = weth.balanceOf(address(pool));
        uint256 endingX = poolToken.balanceOf(address(pool));

        actualDeltaY = int256(endingY) - int256(startingY);
        actualDeltaX = int256(endingX) - int256(startingX);
    }

    // deposit, swapExactOutput
    function deposit(uint256 wethAmountToDeposit) public {
        if (wethAmountToDeposit == 0) {
            return;
        }
        // Make sure it's a reasonable amount
        wethAmountToDeposit = bound(wethAmountToDeposit, pool.getMinimumWethDepositAmount(), type(uint64).max);
        uint256 amountPoolTokensToDepositBasedOnWeth = pool.getPoolTokensToDepositBasedOnWeth(wethAmountToDeposit);

        startingY = int256(weth.balanceOf(address(pool)));
        startingX = int256(poolToken.balanceOf(address(pool)));

        console2.log("The starting Y ", startingY);
        console2.log("The starting X ", startingX);

        expectedDeltaY = int256(wethAmountToDeposit);
        expectedDeltaX = int256(amountPoolTokensToDepositBasedOnWeth);

        console2.log("The ExpectedDelta Y ", expectedDeltaY);
        console2.log("The expectedDelta X ", expectedDeltaX);

        vm.startPrank(liquidityProvider);

        weth.mint(liquidityProvider, wethAmountToDeposit);
        poolToken.mint(liquidityProvider, amountPoolTokensToDepositBasedOnWeth);

        weth.approve(address(pool), wethAmountToDeposit);
        poolToken.approve(address(pool), amountPoolTokensToDepositBasedOnWeth);

        pool.deposit({
            wethToDeposit: wethAmountToDeposit,
            minimumLiquidityTokensToMint: pool.getMinimumWethDepositAmount(),
            maximumPoolTokensToDeposit: amountPoolTokensToDepositBasedOnWeth,
            deadline: uint64(block.timestamp)});

        vm.stopPrank();

        uint256 endingY = weth.balanceOf(address(pool));
        uint256 endingX = poolToken.balanceOf(address(pool));


        console2.log("The ending Y ", endingY);
        console2.log("The ending X ", endingX);

        if (uint256(startingY) > endingY) {
            console2.log("Funny starting Y is is greater than ending y ");
        }

        actualDeltaY = int256(endingY) - int256(startingY);
        actualDeltaX = int256(endingX) - int256(startingX);
    }

}