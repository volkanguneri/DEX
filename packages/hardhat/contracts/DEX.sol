// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title DEX Template
 * @author stevepham.eth and m00npapi.eth
 * @notice Empty DEX.sol that just outlines what features could be part of the challenge (up to you!)
 * @dev We want to create an automatic market where our contract will hold reserves of both ETH and 🎈 Balloons. These reserves will provide liquidity that allows anyone to swap between the assets.
 * NOTE: functions outlined here are what work with the front end of this challenge. Also return variable names need to be specified exactly may be referenced (It may be helpful to cross reference with front-end code function calls).
 */
contract DEX {
	using SafeMath for uint256;
	/* ========== GLOBAL VARIABLES ========== */

	IERC20 token; //instantiates the imported contract

	uint256 public totalLiquidity;
	mapping(address => uint256) public liquidity;

	/* CUSTOM ERORS */
	error contractHasAlreadyLiquidity();
	error TransferFailed();
	error InsufficientInput();
	error InsufficientLiquidity();

	/* ========== EVENTS ========== */

	/**
	 * @notice Emitted when ethToToken() swap transacted
	 */
	event EthToTokenSwap(
		address swapper,
		uint256 tokenOutput,
		uint256 ethInput
	);

	/**
	 * @notice Emitted when tokenToEth() swap transacted
	 */
	event TokenToEthSwap(
		address swapper,
		uint256 tokensInput,
		uint256 ethOutput
	);

	/**
	 * @notice Emitted when liquidity provided to DEX and mints LPTs.
	 */
	event LiquidityProvided(
		address liquidityProvider,
		uint256 liquidityMinted,
		uint256 ethInput,
		uint256 tokensInput
	);

	/**
	 * @notice Emitted when liquidity removed from DEX and decreases LPT count within DEX.
	 */
	event LiquidityRemoved(
		address liquidityRemover,
		uint256 liquidityWithdrawn,
		uint256 tokensOutput,
		uint256 ethOutput
	);

	/* ========== CONSTRUCTOR ========== */

	constructor(address token_addr) {
		token = IERC20(token_addr); //specifies the token address that will hook into the interface and be used through the variable 'token'
	}

	/* ========== MUTATIVE FUNCTIONS ========== */

	/**
	 * @notice initializes amount of tokens that will be transferred to the DEX itself from the erc20 contract mintee (and only them based on how Balloons.sol is written). Loads contract up with both ETH and Balloons.
	 * @param tokens amount to be transferred to DEX
	 * @return totalLiquidity is the number of LPTs minting as a result of deposits made to DEX contract
	 * NOTE: since ratio is 1:1, this is fine to initialize the totalLiquidity (wrt to balloons) as equal to eth balance of contract.
	 */
	function init(uint256 tokens) public payable returns (uint256) {
		if (totalLiquidity != 0) revert contractHasAlreadyLiquidity();
		totalLiquidity = address(this).balance;
		liquidity[msg.sender] = totalLiquidity;
		if (!token.transferFrom(msg.sender, address(this), tokens))
			revert TransferFailed();
		return totalLiquidity;
	}

	/**
	 * @notice returns yOutput, or yDelta for xInput (or xDelta)
	 * @dev Follow along with the [original tutorial](https://medium.com/@austin_48503/%EF%B8%8F-minimum-viable-exchange-d84f30bd0c90) Price section for an understanding of the DEX's pricing model and for a price function to add to your contract. You may need to update the Solidity syntax (e.g. use + instead of .add, * instead of .mul, etc). Deploy when you are done.
	 */
	function price(
		uint256 xInput,
		uint256 xReserves,
		uint256 yReserves
	) public pure returns (uint256 yOutput) {
		if (xInput == 0) revert InsufficientInput();
		if (xReserves == 0 && yReserves == 0) revert InsufficientLiquidity();
		uint256 xInputWithFee = xInput.mul(997);
		uint256 numerator = xInputWithFee.mul(yReserves);
		uint256 denominator = xReserves.mul(1000).add(xInputWithFee);
		return numerator / denominator;
	}

	/**
	 * @notice returns liquidity for a user.
	 * NOTE: this is not needed typically due to the `liquidity()` mapping variable being public and having a getter as a result. This is left though as it is used within the front end code (App.jsx).
	 * NOTE: if you are using a mapping liquidity, then you can use `return liquidity[lp]` to get the liquidity for a user.
	 * NOTE: if you will be submitting the challenge make sure to implement this function as it is used in the tests.
	 */
	function getLiquidity(address lp) public view returns (uint256) {
		return liquidity[lp];
	}

	/**
	 * @notice Sends Ether to DEX in exchange for $BAL tokens.
	 * @return tokenOutput Amount of $BAL tokens received.
	 */
	function ethToToken() external payable returns (uint256 tokenOutput) {
		if (msg.value == 0) revert InsufficientInput();
		// Calculate token output based on current liquidity and token reserves
		uint256 eth_reserve = address(this).balance - msg.value;
		uint256 token_reserve = token.balanceOf(address(this));
		tokenOutput = price(msg.value, eth_reserve, token_reserve);
		// Transfer the calculated amount of token to the user
		if (!token.transfer(msg.sender, tokenOutput)) revert TransferFailed();
		emit EthToTokenSwap(msg.sender, tokenOutput, msg.value);
		return tokenOutput;
	}

	/**
	 * @notice Sends $BAL tokens to DEX in exchange for Ether.
	 * @param tokenInput Amount of $BAL tokens to exchange for Ether.
	 * @return ethOutput Amount of Ether received.
	 */
	function tokenToEth(uint256 tokenInput) public returns (uint256 ethOutput) {
		uint256 token_reserve = token.balanceOf(address(this));
		uint256 eth_reserve = address(this).balance;
		ethOutput = price(tokenInput, token_reserve, eth_reserve);
		// Transfer the calculated amount of token from user to the contract
		if (!token.transferFrom(msg.sender, address(this), tokenInput))
			revert TransferFailed();
		// Transfer the calculated amount of Ether from contract to the user
		(bool success, ) = msg.sender.call{ value: ethOutput }("");
		require(success, "TransferFailed");
		emit TokenToEthSwap(msg.sender, tokenInput, ethOutput);
		return ethOutput;
	}

	/**
	 * @notice allows deposits of $BAL and $ETH to liquidity pool
	 * NOTE: parameter is the msg.value sent with this function call. That amount is used to determine the amount of $BAL needed as well and taken from the depositor.
	 * NOTE: user has to make sure to give DEX approval to spend their tokens on their behalf by calling approve function prior to this function call.
	 * NOTE: Equal parts of both assets will be removed from the user's wallet with respect to the price outlined by the AMM.
	 */
	function deposit() public payable returns (uint256 tokensDeposited) {
		if (msg.value == 0) revert InsufficientInput();
		uint256 eth_reserve = address(this).balance.sub(msg.value);
		uint256 token_reserve = token.balanceOf(address(this));
		uint256 tokenDeposit;
		uint256 liquidityMinted;
		if (eth_reserve == 0 || token_reserve == 0)
			revert InsufficientLiquidity();
		tokenDeposit = msg.value.mul(token_reserve).div(eth_reserve).add(1);
		liquidityMinted = msg.value.mul(totalLiquidity).div(eth_reserve);
		liquidity[msg.sender] += liquidityMinted;
		totalLiquidity += liquidityMinted;
		if (!token.transferFrom(msg.sender, address(this), tokenDeposit))
			revert TransferFailed();
		emit LiquidityProvided(
			msg.sender,
			liquidityMinted,
			msg.value,
			tokenDeposit
		);
		return tokenDeposit;
	}

	/**
	 * @notice allows withdrawal of $BAL and $ETH from liquidity pool
	 * NOTE: with this current code, the msg caller could end up getting very little back if the liquidity is super low in the pool. I guess they could see that with the UI.
	 */
	function withdraw(
		uint256 amount
	) public returns (uint256 eth_amount, uint256 token_amount) {
		if (amount > liquidity[msg.sender]) revert InsufficientInput();
		uint256 eth_reserve = address(this).balance;
		uint256 token_reserve = token.balanceOf(address(this));
		uint256 ethWithdrawn;
		uint256 tokenAmount;
		ethWithdrawn = amount.mul(eth_reserve).div(totalLiquidity);
		tokenAmount = amount.mul(token_reserve).div(totalLiquidity);
		liquidity[msg.sender] -= ethWithdrawn;
		totalLiquidity -= ethWithdrawn;
		// Transfer the calculated amount of Ether from contract to the user
		(bool success, ) = msg.sender.call{ value: ethWithdrawn }("");
		require(success, "TransferFailed");
		// Transfer the calculated amount of Token from contract to the user
		require(token.transfer(msg.sender, tokenAmount));
		emit LiquidityRemoved(msg.sender, amount, tokenAmount, ethWithdrawn);
		return (ethWithdrawn, tokenAmount);
	}
}
