## High

### [H-1] `TswapPool::deposit` is missing deadline check causing transaction

to complete event after deadline

**Description:** The `deposit` function accepts a deadline parameter, which according to the documentation is
"The deadline for the transaction to be completed by". However this parameter is never used as a consequence, operations
that add
liquidity to the pool might be executed at unexepcted times, in market conditions where the deposit rate is unfavorable


<!-- MEV attacks -->


**Impact:** Transactions could be sent when marktet conditions are unvaroable to deposit even when a deadline
parameter .

**Proof of Concept:** The `deadline`  parameter is unused

**Recommended Mitigation:** Consider making the following change to the function

```diff
    function deposit(
        uint256 wethToDeposit,
        uint256 minimumLiquidityTokensToMint,
        uint256 maximumPoolTokensToDeposit,
    )
    external
   + revertIfDeadlinePassed(deadline)
    revertIfZero(wethToDeposit)
    returns (uint256 liquidityTokensToMint)
    {

```

### [H-2] Incorrect fee calculation `TswapPool::getInputAmountBasedOnOutput`  causes protocol to take too many tokens from users

**Description:** The `getInputAmountBasedOnOutput` function is intended to calculate the amount of tokens
the user should deposit given an amount of tokens. However, the function currently miscalculates the resulting amount.
when calculating the fee, it scales the amount by 10_000 instead of 1_000.

**Impact:** Protocol takes too many tokens from users, leading to a loss of funds for the user.

**Recommended Mitigation:**

```diff 
  function getInputAmountBasedOnOutput(
        uint256 outputAmount,
        uint256 inputReserves,
        uint256 outputReserves
    )
    public
    pure
    revertIfZero(outputAmount)
    revertIfZero(outputReserves)
    returns (uint256 inputAmount)
    {
     
    -    return ((inputReserves * outputAmount) * 10_000) /  ((outputReserves - outputAmount) * 997);
    +    return ((inputReserves * outputAmount) * 1000) /  ((outputReserves - outputAmount) * 997);
    }

```

### [H-3] Lack of slippage protection in `TswapPool::swapExactOutput` causes users to potentially receive way fewer tokens

**Description:** The `swapExactOutput` function does not include any sort of slippage protection. This function is
similar to what is done in
`TswapPool:swapExactInput`, where the function specifies a `minOutputAmount` the `swapExactOutput` function should
specify a `maxInputAmount`.

**Impact:** If market conditions change before the transaction processes, the user could get a worse much swap .

**Proof of Concept:**

1. The price of 1 weth now is 1,000 USDC
2. User inputs a `swapExactInput` looking for 1 WETH
    1. inputToken = USDC
    2. outputToken = WETH
    3. outputAmount = 1
    4. deadline = whatever
3. The function does not offer a maxInput amount
4. As the transaction is pending in the mempool, the market changes! and the price moves HUGE --> 1 Weth is not
   10,000 USDC. 10x more than the user expected
5. The transaction completes, but the user sent the protocol 10,000 USDC instead of the expected 1,000 USDC

**Recommended Mitigation:** We should include a `maxInputAmount` so the user only has to spend up to a
specific amount, and can predict how much they will spend onf the protocol.

```diff 
  function swapExactOutput(
        IERC20 inputToken, 
        + uint256 maxInputAmount,
        .
        .
        .
     inputAmount = getInputAmountBasedOnOutput(
            outputAmount,
            inputReserves,
            outputReserves
        );
    +    if (inputAmount > maxInputAmount) {
    +        revert ();
        }
      
        _swap(inputToken, inputAmount, outputToken, outputAmount);

```

### [H-4] `TswapPool::sellPoolTokens` mxmatches input and output tokens causing users to receive the incorrect amount of tokens

**Description:** The `sellPoolTokens` function is intended to allow users to easlily sell pool tokens and receive weth
in exchange. Users
indicate how many pool tokens they are willing to sell in the  `poolTokenAmount` parameter.
However, the function currently miscalculates the swapped amount.

This is due to the fact that the `swapExactOutput` function is called, where is the `swapExactInput` function is the one
that should be
called. Because users specify the exact amount of input tokens, not output

**Impact:** Users will swap the wrong amount of tokens, which is a severe disruption of protocol functionality

**Proof of Concept:**

**Recommended Mitigation:**

Consider changin the implementation to use `swapExactInput` instead of `swapExactOutput`
Not that this would also requre changing the `sellPoolTokens` function to accept a new (ie  `minWethToReceive` to be
passed to
`swapExactInput`)

```diff 
function sellPoolTokens(
        uint256 poolTokenAmount,
    +    uint256 minWethToReceive,
    ) external returns (uint256 wethAmount) {
        // pool token -> input
        // @audit this is wrong!!!
        // swapExactInput(minWethToReceive)

    -    return swapExactOutput( i_poolToken,i_wethToken, poolTokenAmount,uint64(block.timestamp)); 
    +   return swapExactInput( i_poolToken,poolTokenAmount, i_wethToken, minWethToReceive,uint64(block.timestamp)); 
        
    }

```

Additionally, it might be wise to add a deadline to the function, as there is currently no deadline 

### [H-5] In `TswapPool::_swap` the extra tokens given to  users after every `swapCount` breaks the protocol 
invariant of `x *y = k`

**Description:** The protocol follows a strict invariant of `x * y = k` where
 - `x` is the amount of tokens in the pool
 - `y`  The balance of weth 
 - `k` The constant product of the two balances 

This means, that whenevet the balances changes in the protocol, the ratio between the two amounts should remain constant, 
hence the `k`, However, this is broken due to the extra incentive in the `_swap function. meaning that slowly over time the protocol funds will be drained 

The followi block of code is responsible for the issues 
``javascript
   
   swap_count++;
   // Fee-on-transfer
   if (swap_count >= SWAP_COUNT_MAX) {
   swap_count = 0;
   outputToken.safeTransfer(msg.sender, 1_000_000_000_000_000_000);
   }
``


**Impact:** A use could malicious drain the protocol of funds bu doing a lot of swaps and collecting the extra incentive given out by the protocol, 
Most simply put the protocol core invariants is  broken. 

**Proof of Concept:**
1. A user swaps 10 times, and collects the extra incentive of `1_000_000_000_000_000_000` each time
2. The user continues to swap till all the protocol funds are drained

<details>
<summary>Proof of code </summary>
Place the following code in the `TswapPool.t.sol` 

``` javascript
      
      function testInvariantBroken() public {
            vm.startPrank(liquidityProvider);
            weth.approve(address(pool), 100e18);
            poolToken.approve(address(pool), 100e18);
            pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
            vm.stopPrank();

        uint256 outputWeth = 1e17;
        int256 startingY = int256(weth.balanceOf(address(pool)));

        int256 expectedDeltaY = int256(outputWeth) * - 1;


        vm.startPrank(user);
        // Approve tokens so they can be pulled by the pool during the swap
        poolToken.approve(address(pool), type(uint256).max);
        poolToken.mint(user, 100e18);
        pool.swapExactOutput({inputToken: poolToken, outputToken: weth, outputAmount: outputWeth, deadline: uint64(block.timestamp)});
        pool.swapExactOutput({inputToken: poolToken, outputToken: weth, outputAmount: outputWeth, deadline: uint64(block.timestamp)});
        pool.swapExactOutput({inputToken: poolToken, outputToken: weth, outputAmount: outputWeth, deadline: uint64(block.timestamp)});
        pool.swapExactOutput({inputToken: poolToken, outputToken: weth, outputAmount: outputWeth, deadline: uint64(block.timestamp)});
        pool.swapExactOutput({inputToken: poolToken, outputToken: weth, outputAmount: outputWeth, deadline: uint64(block.timestamp)});
        pool.swapExactOutput({inputToken: poolToken, outputToken: weth, outputAmount: outputWeth, deadline: uint64(block.timestamp)});
        pool.swapExactOutput({inputToken: poolToken, outputToken: weth, outputAmount: outputWeth, deadline: uint64(block.timestamp)});
        pool.swapExactOutput({inputToken: poolToken, outputToken: weth, outputAmount: outputWeth, deadline: uint64(block.timestamp)});
        pool.swapExactOutput({inputToken: poolToken, outputToken: weth, outputAmount: outputWeth, deadline: uint64(block.timestamp)});
        pool.swapExactOutput({inputToken: poolToken, outputToken: weth, outputAmount: outputWeth, deadline: uint64(block.timestamp)});
        vm.stopPrank();

        // Actual
        uint256 endingY = weth.balanceOf(address(pool));

        int256 actualDeltaY = int256(endingY) - int256(startingY);

        assertEq(actualDeltaY, expectedDeltaY);
    }
``` 
</details>

**Recommended Mitigation:** Remove  the extra incentive. If you want to keep this in, we should account for the change in the 
x * y= k protocol invariant. Or, we should set aside tokens in the same way we do with fees 

```diff

-   swap_count++;
-   // Fee-on-transfer
-   if (swap_count >= SWAP_COUNT_MAX) {
-   swap_count = 0;
-   outputToken.safeTransfer(msg.sender, 1_000_000_000_000_000_000);
-   }
```


## Low

### [L-1] `TSwapPool::LiquidityAdded` event  has paramters out of order causing event to emit incorrect information

**Description:** When the `liquidityAdded` event is emitted, the `TswapPool::_addLiquidityMintAndTransfer`
and `poolTokensDeposited` are emitted in the wrong order. This could cause off-chain tools to misinterpret the event.
The `poolTokensDeposited` value should go in the third parameter position

**Impact:** Event emission is incorrect, leading to off-chain functions potentially malfunctioning.

**Recommended Mitigation:**

```diff
    - event LiquidityAdded(msg.sender, poolTokensToDeposit,wethToDeposit);
    + event LiquidityAdded(msg.sender,wethToDeposit,poolTokensToDeposit);
```

### [L-#] Default value returned by  `TswapPool::swapExactInput` results in incorrect

return values given

**Description:** The `swapExactInput` function is expected to return the actual amount of tokens bough by the caller.
However, while it
declares the named return value `output` it is never assigned a value nor uses an explicit return statement.

**Impact:** The return value will always be 0, giving incorrect information to the caller.

**Proof of Concept:**

**Recommended Mitigation:**

```diff

{
        uint256 inputReserves = inputToken.balanceOf(address(this));
        uint256 outputReserves = outputToken.balanceOf(address(this));

   -     uint256 outputAmount = getOutputAmountBasedOnInput(
            inputAmount,
            inputReserves,
            outputReserves
        );
   +      output = getOutputAmountBasedOnInput(
            inputAmount,
            inputReserves,
            outputReserves
        );

    -    if (outputAmount < minOutputAmount) {
    -       revert TSwapPool__OutputTooLow(outputAmount, minOutputAmount);
        }
    +    if (output < minOutputAmount) {
    +       revert TSwapPool__OutputTooLow(output, minOutputAmount);
        }

    _    _swap(inputToken, inputAmount, outputToken, outputAmount);
     +   _swap(inputToken, inputAmount, outputToken, output);
    }

```

## Informational

### [I-1] `PoolFactory::PoolFactory__PoolDoesNotExist` is not used and this should be removed

 ```diff 
 - error  PoolFactory__PoolDoesNotExist(address tokenAddress);
 ```

### [I-2] Lacking zero address check

```diff
     constructor(address wethToken) {
 +      if( wethToken == address(0) ) {
 +          revert();
 +}
        i_wethToken = wethToken;
    }

```

### [I-3] `PoolFactory::createPool` should  use symbol not  name

```diff
 - string memory liquidityTokenSymbol = string.concat("ts", IERC20(tokenAddress).name());
 + string memory liquidityTokenSymbol = string.concat("ts", IERC20(tokenAddress).symbol());
 
```

### [I-4] Event is missing `indexed` fields

Index events fields make the fields more quickly accessible to off-chain tools that parse events. However
not that each index fields costs extra fas during emission, so it's not necessary best to index the maximum allowed per
event
( three fields). Each event should use three indexed fields if there are three or mere fields, and gas usage is not
all particular of concern for the events in question. if there are fewer than three fields, all of the fields should be
indexed .

- Found src/TswapPool.sol: 52
- Found src/PoolFactory.sol:  36
- Found src/TswapPool.sol: 57
- Found src/TswapPool.sol: 63