// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusNebulaOracle} from "./interfaces/ICygnusNebulaOracle.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";

// Libraries
import {PRBMath, PRBMathUD60x18} from "./libraries/PRBMathUD60x18.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";
import {IDexPair} from "./interfaces/IDexPair.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

/**
 *  @title  CygnusNebulaOracle
 *  @author CygnusDAO
 *  @notice Oracle used by Cygnus that returns the price of 1 LP Token in the denomination token. In case need
 *          different implementation just update the denomination variable `denominationAggregator`
 *          and `denominationToken` with token. We used AGGREGATOR_DECIMALS as a constant for chainlink prices
 *          which are denominated in USD as all aggregators return prices in 8 decimals and saves us gas when
 *          getting the LP token price.
 *  @notice Implementation of fair lp token pricing using Chainlink price feeds
 *          https://blog.alphaventuredao.io/fair-lp-token-pricing/
 */
contract CygnusNebulaOracle is ICygnusNebulaOracle, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 Library for advanced fixed-point math that works with uint256 numbers
     */
    using PRBMathUD60x18 for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Internal record of all initialized oracles
     */
    mapping(address => CygnusNebula) internal nebulas;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    address[] public override allNebulas;

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    string public constant override name = "Cygnus-Nebula: Constant-Product LP Oracle";

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    string public constant override symbol = "CygNebula";

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    string public constant override version = "1.0.0";

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    uint256 public constant override SECONDS_PER_YEAR = 31536000;

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    uint256 public constant override AGGREGATOR_DECIMALS = 8;

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    IERC20 public immutable override denominationToken;

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    uint8 public immutable override decimals;

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    AggregatorV3Interface public immutable override denominationAggregator;

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    address public override admin;

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    address public override pendingAdmin;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs a new Oracle instance.
     *  @param denomination The token address that the oracle denominates the price of the LP in. It is used to
     *         determine the decimals for the price returned by this oracle. For example, if the denomination
     *         token is USDC, the oracle will return prices with 6 decimals. If the denomination token is DAI,
     *         the oracle will return prices with 18 decimals.
     *  @param denominationPrice The price aggregator for the denomination token.
     *        This is the token that the LP Token will be priced in.
     */
    constructor(IERC20 denomination, AggregatorV3Interface denominationPrice) {
        // Assign the admin
        admin = msg.sender;

        // Set the denomination token
        denominationToken = denomination;

        // Determine the number of decimals for the oracle based on the denomination token
        decimals = denomination.decimals();

        // Set the price aggregator for the denomination token
        denominationAggregator = AggregatorV3Interface(denominationPrice);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier cygnusAdmin Modifier for admin control only 👽
     */
    modifier cygnusAdmin() {
        isCygnusAdmin();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Internal check for admin control only 👽
     */
    function isCygnusAdmin() internal view {
        /// @custom:error MsgSenderNotAdmin Avoid unless caller is Cygnus Admin
        if (msg.sender != admin) {
            revert CygnusNebulaOracle__MsgSenderNotAdmin({sender: msg.sender});
        }
    }

    /**
     *  @notice Gets the price of a chainlink aggregator
     *  @param priceFeed Chainlink aggregator price feed
     *  @return The price of the token adjusted to 18 decimals
     */
    function getPriceInternal(AggregatorV3Interface priceFeed) public view returns (uint256) {
        // Get latest round from the price feed
        (, int256 price, , , ) = priceFeed.latestRoundData();

        // Return the price adjusted to 18 decimals
        return uint256(price) * 10 ** (18 - AGGREGATOR_DECIMALS);
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function getNebula(address lpTokenPair) public view override returns (CygnusNebula memory) {
        return nebulas[lpTokenPair];
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function nebulaSize() public view override returns (uint88) {
        // Return how many LP Tokens we are tracking
        return uint88(allNebulas.length);
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function getAnnualizedBaseRate(
        uint256 exchangeRateLast,
        uint256 exchangeRateCurrent,
        uint256 timeElapsed
    ) public pure override returns (uint256) {
        // Get the natural logarithm of last exchange rate
        uint256 logRateLast = exchangeRateLast.ln();

        // Get the natural logarithm of current exchange rate
        uint256 logRateCurrent = exchangeRateCurrent.ln();

        // Get the log rate difference between the exchange rates
        uint256 logRateDiff = logRateCurrent - logRateLast;

        // The log APR is = (lorRateDif * 1 year) / time since last update
        uint256 logAprInYear = (logRateDiff * SECONDS_PER_YEAR) / timeElapsed;

        // Get the natural exponent of the log APR and substract 1
        uint256 annualizedApr = logAprInYear.exp() - 1e18;

        // Returns the annualized APR, taking into account time since last update
        return annualizedApr;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function denominationTokenPrice() external view override returns (uint256) {
        // Price of the denomination token in 18 decimals
        uint256 denomPrice = getPriceInternal(denominationAggregator);

        // Return in oracle decimals
        return denomPrice / (10 ** (18 - decimals));
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function lpTokenPriceUsd(address lpTokenPair) external view override returns (uint256 lpTokenPrice) {
        // Load to storage for gas savings
        CygnusNebula storage cygnusNebula = nebulas[lpTokenPair];

        /// @custom:error PairNotInitialized Avoid getting price unless lpTokenPair's price is being tracked
        if (!cygnusNebula.initialized) {
            revert CygnusNebulaOracle__PairNotInitialized({lpTokenPair: lpTokenPair});
        }

        // 1. Get price of each of the LP token assets adjusted to 18 decimals
        // Price of token0
        uint256 price0 = getPriceInternal(cygnusNebula.priceFeeds[0]);

        // Price of token1
        uint256 price1 = getPriceInternal(cygnusNebula.priceFeeds[1]);

        // 2. Get the reserves of tokenA and tokenB to compute k
        (uint112 reserves0, uint112 reserves1, ) = IDexPair(lpTokenPair).getReserves();

        // Adjusted with token0 decimals
        uint256 value0 = (price0 * reserves0) / (10 ** cygnusNebula.poolTokensDecimals[0]);

        // Adjust with token1 decimals
        uint256 value1 = (price1 * reserves1) / (10 ** cygnusNebula.poolTokensDecimals[1]);

        // 3. Get total Supply (always 18 decimals)
        uint256 supply = IDexPair(lpTokenPair).totalSupply();

        // 4. Compute the price of the LP Token denominated in USD
        // LP Price = 2 * Math.sqrt((reserves0 * price0) * (reserve1 * price1)) / totalSupply
        uint256 lpPriceUsd = (2e18 * value0.gm(value1)) / supply;

        // 5. Get the price of the denomination token
        uint256 denomPrice = getPriceInternal(denominationAggregator);

        // 6. Return the price of the LP Token expressed in the denomination token
        lpTokenPrice = lpPriceUsd.div(denomPrice * 10 ** (18 - decimals));
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function assetPricesUsd(address lpTokenPair) external view override returns (uint256[] memory) {
        // Load to storage for gas savings
        CygnusNebula storage cygnusNebula = nebulas[lpTokenPair];

        /// @custom:error PairNotInitialized Avoid getting price unless lpTokenPair's price is being tracked
        if (!cygnusNebula.initialized) {
            revert CygnusNebulaOracle__PairNotInitialized({lpTokenPair: lpTokenPair});
        }

        // Price of denom token
        uint256 denomPrice = getPriceInternal(denominationAggregator);

        // Create new array of poolTokens.length to return
        uint256[] memory prices = new uint256[](cygnusNebula.poolTokens.length);

        // Loop through each token
        for (uint256 i = 0; i < cygnusNebula.poolTokens.length; i++) {
            // Get the price from chainlink from cached price feeds
            uint256 assetPrice = getPriceInternal(cygnusNebula.priceFeeds[i]);

            // Express asset price in denom token
            prices[i] = assetPrice.div(denomPrice * 10 ** (18 - decimals));
        }

        // Return uint256[] of token prices denominated in denom token and oracle decimals
        return prices;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebulaOracle
     *  @custom:security non-reentrant only-admin
     */
    function initializeNebula(
        address lpTokenPair,
        AggregatorV3Interface[] calldata aggregators
    ) external override nonReentrant cygnusAdmin {
        // Load the CygnusNebula instance for the LP Token pair into storage
        CygnusNebula storage cygnusNebula = nebulas[lpTokenPair];

        // If the LP Token pair is already being tracked by an oracle, revert with an error message
        if (cygnusNebula.initialized) {
            revert CygnusNebulaOracle__PairAlreadyInitialized({lpTokenPair: lpTokenPair});
        }

        // Create a memory array of tokens with the same length as the number of price aggregators
        IERC20[] memory poolTokens = new IERC20[](aggregators.length);

        // Create a memory array for the decimals of each token
        uint256[] memory tokenDecimals = new uint256[](aggregators.length);

        // Create a memory array for the decimals of each price feed
        uint256[] memory priceDecimals = new uint256[](aggregators.length);

        // Get the first token in the LP Token pair and add it to the poolTokens array
        poolTokens[0] = IERC20(IDexPair(lpTokenPair).token0());

        // Get the second token in the LP Token pair and add it to the poolTokens array
        poolTokens[1] = IERC20(IDexPair(lpTokenPair).token1());

        // Loop through each one
        for (uint256 i = 0; i < aggregators.length; i++) {
            // Get the decimals for token `i`
            tokenDecimals[i] = poolTokens[i].decimals();

            // Chainlink price feed decimals
            priceDecimals[i] = aggregators[i].decimals();
        }

        // Assign an ID to the new oracle
        cygnusNebula.oracleId = nebulaSize();

        // Set the user-friendly name of the new oracle to the name of the LP Token pair
        cygnusNebula.name = IERC20(lpTokenPair).name();

        // Store the address of the LP Token pair
        cygnusNebula.underlying = lpTokenPair;

        // Store the addresses of the tokens in the LP Token pair
        cygnusNebula.poolTokens = poolTokens;

        // Store the number of decimals for each token in the LP Token pair
        cygnusNebula.poolTokensDecimals = tokenDecimals;

        // Store the price aggregator interfaces for the tokens in the LP Token pair
        cygnusNebula.priceFeeds = aggregators;

        // Store the decimals for each aggregator
        cygnusNebula.priceFeedsDecimals = priceDecimals;

        // Set the status of the new oracle to initialized
        cygnusNebula.initialized = true;

        // Add the LP Token pair to the list of all tracked LP Token pairs
        allNebulas.push(lpTokenPair);

        /// @custom:event InitializeCygnusNebula
        emit InitializeCygnusNebula(
            true,
            cygnusNebula.oracleId,
            lpTokenPair,
            poolTokens,
            tokenDecimals,
            aggregators,
            priceDecimals
        );
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     *  @custom:security non-reentrant only-admin
     */
    function setOraclePendingAdmin(address newPendingAdmin) external override nonReentrant cygnusAdmin {
        // Pending admin initial is always zero
        /// @custom:error PendingAdminAlreadySet Avoid setting the same pending admin twice
        if (newPendingAdmin == pendingAdmin) {
            revert CygnusNebulaOracle__PendingAdminAlreadySet({pendingAdmin: newPendingAdmin});
        }

        // Assign address of the requested admin
        pendingAdmin = newPendingAdmin;

        /// @custom:event NewOraclePendingAdmin
        emit NewOraclePendingAdmin(admin, newPendingAdmin);
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     *  @custom:security non-reentrant only-admin
     */
    function setOracleAdmin() external override nonReentrant cygnusAdmin {
        /// @custom:error AdminCantBeZero Avoid settings the admin to the zero address
        if (pendingAdmin == address(0)) {
            revert CygnusNebulaOracle__AdminCantBeZero({pendingAdmin: pendingAdmin});
        }

        // Address of the Admin up until now
        address oldAdmin = admin;

        // Assign new admin
        admin = pendingAdmin;

        // Gas refund
        delete pendingAdmin;

        // @custom:event NewOracleAdmin
        emit NewOracleAdmin(oldAdmin, admin);
    }
}
