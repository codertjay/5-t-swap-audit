// SPDX-License-Identifier:  MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {PoolFactory} from "../../src/PoolFactory.sol";
import {TSwapPool} from "../../src/TSwapPool.sol";
import {Handler} from "./Handler.t.sol";

contract Invariant is StdInvariant, Test {

    Handler handler;

// these pools have 2 assets
    ERC20Mock poolToken;
    ERC20Mock weth;

// we are gonna need the contracts
    PoolFactory factory;
    TSwapPool pool; // poolToken / weth

    int256 constant STARTING_X = 100e18;  // starting ERC20 / pooltoken
    int256 constant STARTING_Y = 150e18;  // starting WETH / pooltoken




    function setUp() public {
        poolToken = new ERC20Mock();
        weth = new ERC20Mock();
        factory = new PoolFactory(address(weth));
        pool = TSwapPool(factory.createPool(address(poolToken)));

// create these initial x & y balances
        poolToken.mint(address(this), uint256(STARTING_X));
        weth.mint(address(this), uint256(STARTING_Y));

        poolToken.approve(address(pool), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);

// Deposit into the pool, give the starting X & Y balances
        pool.deposit(
            uint256(STARTING_Y),
            uint256(STARTING_Y),
            uint256(STARTING_X),
            uint64(block.timestamp)
        );

        handler = new Handler(pool);
        bytes4[]  memory selectors = new bytes4[](2);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.swapToolTokenForWethBasedOnOutputWeth.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        targetContract(address(handler));

    }

    function statefulFuzz_constantProductFormulaStaysTheSameX() public {
        //        assert()
        // The change in the pool size of WETH should follow this function;
        // ∆x = (β/(1-β)) * (1/γ) * x
        // ∆y = (αγ/1+αγ) * y
        // ??????

        assertEq(handler.actualDeltaX(), handler.expectedDeltaX());
    }

    function statefulFuzz_constantProductFormulaStaysTheSameY() public {
        //        assert()
        // The change in the pool size of WETH should follow this function;
        // ∆x = (β/(1-β)) * (1/γ) * x
        // ∆y = (αγ/1+αγ) * y
        // ??????

        assertEq(handler.actualDeltaY(), handler.expectedDeltaY());
    }


}
