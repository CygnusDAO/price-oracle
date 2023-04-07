// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

// Dependencies
import {ICygnusNebulaOracle} from "./interfaces/ICygnusNebulaOracle.sol";
import {Context} from "./utils/Context.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";
import {ERC20Normalizer} from "./utils/ERC20Normalizer.sol";

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
 *          and `denominationToken` with token
 *  @notice Implementation of fair lp token pricing using Chainlink price feeds
 *          https://blog.alphaventuredao.io/fair-lp-token-pricing/
 */
contract CygnusNebulaOracle is ICygnusNebulaOracle, Context, ReentrancyGuard, ERC20Normalizer {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library FixedPointMathLib Arithmetic library with operations for fixed-point numbers
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
     *  @notice Constructs the Oracle
     *  @param denomination The denomination token, used to get the decimals that this oracle retursn the price in.
     *         ie If denomination token is USDC, the oracle will return the price in 6 decimals, if denomination
     *         token is DAI, the oracle will return the price in 18 decimals.
     *  @param denominationPrice The denomination token this oracle returns the prices in
     */
    constructor(IERC20 denomination, AggregatorV3Interface denominationPrice) {
        // Assign admin
        admin = _msgSender();

        // Denomination token
        denominationToken = denomination;

        // Decimals for the oracle based on the denomination token
        decimals = denomination.decimals();

        // Assign the denomination the LP Token will be priced in
        denominationAggregator = AggregatorV3Interface(denominationPrice);

        // Cache scalar of denom token price
        computeScalar(IERC20(address(denominationPrice)));
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
        if (_msgSender() != admin) {
            revert CygnusNebulaOracle__MsgSenderNotAdmin(_msgSender());
        }
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function nebulaSize() public view override returns (uint24) {
        // Return how many LP Tokens we are tracking
        return uint24(allNebulas.length);
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
        // Chainlink price feed for the LP denomination token
        (, int256 latestRoundUsd, , , ) = denominationAggregator.latestRoundData();

        // Return price without adjusting decimals - not used by this contract, we keep it here to quickly check
        // in case something goes wrong
        return uint256(latestRoundUsd);
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function getNebula(address lpTokenPair) external view override returns (CygnusNebula memory) {
        return nebulas[lpTokenPair];
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function lpTokenPriceUsd(address lpTokenPair) external view override returns (uint256 lpTokenPrice) {
        // Load to memory
        CygnusNebula memory cygnusNebula = nebulas[lpTokenPair];

        /// custom:error PairNotInitialized Avoid getting price unless lpTokenPair's price is being tracked
        if (!cygnusNebula.initialized) {
            revert CygnusNebulaOracle__PairNotInitialized(lpTokenPair);
        }

        // 1. Get reserves of tokenA and tokenB to compute k
        (uint112 reservesTokenA, uint112 reservesTokenB /* Timestamp */, ) = IDexPair(lpTokenPair).getReserves();

        // Adjust reserves tokenA with cached scalar
        uint256 adjustedReservesA = normalize(cygnusNebula.poolTokens[0], reservesTokenA);

        // Adjust reserves tokenB with cached scalar
        uint256 adjustedReservesB = normalize(cygnusNebula.poolTokens[1], reservesTokenB);

        // Geometric mean of reservesA and reservesB
        uint256 productReserves = adjustedReservesA.gm(adjustedReservesB);

        // 2. Get prices of tokenA and tokenB from Chainlink; token0 price
        (, int256 priceA, , , ) = cygnusNebula.priceFeeds[0].latestRoundData();

        // token1 price
        (, int256 priceB, , , ) = cygnusNebula.priceFeeds[1].latestRoundData();

        // Adjust price of tokenA to 18 decimals
        uint256 adjustedPriceA = normalize(IERC20(address(cygnusNebula.priceFeeds[0])), uint256(priceA));

        // Adjust price of tokenB to 18 decimals
        uint256 adjustedPriceB = normalize(IERC20(address(cygnusNebula.priceFeeds[1])), uint256(priceB));

        // Geometric mean of priceA and priceB
        uint256 productPrice = adjustedPriceA.gm(adjustedPriceB);

        // 3. Get the price of denomination token
        (, int256 latestRoundUsd, , , ) = denominationAggregator.latestRoundData();

        // Adjust price of denom token to 18 decimals
        uint256 adjustedUsdPrice = normalize(IERC20(address(denominationAggregator)), uint256(latestRoundUsd));

        // 4. Get total supply of the underlying LP Token
        uint256 totalSupply = IDexPair(lpTokenPair).totalSupply();

        // LP Token price denominated in USD
        uint256 lpPrice = PRBMath.mulDiv(productReserves, productPrice, totalSupply) * 2;

        // 5. Return LP Token price expressed in denomination token
        lpTokenPrice = lpPrice.div(adjustedUsdPrice) / (10 ** (18 - decimals));
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function assetPricesUsd(
        address lpTokenPair
    ) external view override returns (uint256 tokenPriceA, uint256 tokenPriceB) {
        // Load to memory
        CygnusNebula memory cygnusNebula = nebulas[lpTokenPair];

        /// custom:error PairNotInitialized Avoid getting price unless lpTokenPair's price is being tracked
        if (!cygnusNebula.initialized) {
            revert CygnusNebulaOracle__PairNotInitialized(lpTokenPair);
        }

        // Chainlink price feed for this lpTokens token0
        (, int256 priceA, , , ) = cygnusNebula.priceFeeds[0].latestRoundData();

        // Chainlink price feed for this lpTokens token1
        (, int256 priceB, , , ) = cygnusNebula.priceFeeds[1].latestRoundData();

        // Adjust price Token A to 18 decimals
        uint256 adjustedPriceA = normalize(IERC20(address(cygnusNebula.priceFeeds[0])), uint256(priceA));

        // Adjust price Token B to 18 decimals
        uint256 adjustedPriceB = normalize(IERC20(address(cygnusNebula.priceFeeds[1])), uint256(priceB));

        // Chainlink price feed for denomination token
        (, int256 latestRoundUsd, , , ) = denominationAggregator.latestRoundData();

        // Adjust price to 18 decimals
        uint256 adjustedUsdPrice = normalize(IERC20(address(denominationAggregator)), uint256(latestRoundUsd));

        // Return token0's price in denom token
        tokenPriceA = adjustedPriceA.div(adjustedUsdPrice) / (10 ** (18 - decimals));

        // Return token1's price in denom token
        tokenPriceB = adjustedPriceB.div(adjustedUsdPrice) / (10 ** (18 - decimals));
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
        // Load to storage
        CygnusNebula storage cygnusNebula = nebulas[lpTokenPair];

        /// @custom:error PairIsinitialized Avoid duplicate oracle
        if (cygnusNebula.initialized) {
            revert CygnusNebulaOracle__PairAlreadyInitialized(lpTokenPair);
        }

        // Create memory array of tokens with pool tokens length
        IERC20[] memory poolTokens = new IERC20[](aggregators.length);

        // Token0 from the LP
        poolTokens[0] = IERC20(IDexPair(lpTokenPair).token0());

        // Token1 from the LP
        poolTokens[1] = IERC20(IDexPair(lpTokenPair).token1());

        // Token0 cache scalar
        computeScalar(poolTokens[0]);

        // Token1 cache scalar
        computeScalar(poolTokens[1]);

        // AggregatorA cache scalar
        computeScalar(IERC20(address(aggregators[0])));

        // AggregatorB cache scalar
        computeScalar(IERC20(address(aggregators[1])));

        // Assign id
        cygnusNebula.oracleId = nebulaSize();

        // Store LP Token address
        cygnusNebula.underlying = lpTokenPair;

        // Tokens addresses
        cygnusNebula.poolTokens = poolTokens;

        // Tokens prices
        cygnusNebula.priceFeeds = aggregators;

        // Store oracle status
        cygnusNebula.initialized = true;

        // Add to list
        allNebulas.push(lpTokenPair);

        /// @custom:event InitializeCygnusNebula
        emit InitializeCygnusNebula(true, cygnusNebula.oracleId, lpTokenPair, poolTokens, aggregators);
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     *  @custom:security non-reentrant only-admin
     */
    function setOraclePendingAdmin(address newPendingAdmin) external override nonReentrant cygnusAdmin {
        // Pending admin initial is always zero
        /// @custom:error PendingAdminAlreadySet Avoid setting the same pending admin twice
        if (newPendingAdmin == pendingAdmin) {
            revert CygnusNebulaOracle__PendingAdminAlreadySet(newPendingAdmin);
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
            revert CygnusNebulaOracle__AdminCantBeZero(pendingAdmin);
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
