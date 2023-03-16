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
     *  @custom:struct CygnusNebula Official record of all Chainlink oracles used by Cygnus
     *  @custom:member initialized Whether an LP Token is being tracked or not
     *  @custom:member oracleId The ID of the LP Token tracked by the oracle
     *  @custom:member underlying The address of the LP Token
     *  @custom:member priceFeedA The address of the Chainlink aggregator used for this LP Token's Token0
     *  @custom:member priceFeedB The address of the Chainlink aggregator used for this LP Token's Token1
     */
    struct CygnusNebula {
        bool initialized;
        uint88 oracleId;
        address underlying;
        IERC20 token0;
        IERC20 token1;
        AggregatorV3Interface priceFeedA;
        AggregatorV3Interface priceFeedB;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    mapping(address => CygnusNebula) public override getNebula;

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    address[] public override allNebulas;

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    string public constant override name = "Cygnus-Nebula: Chainlink LP Oracle";

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
    function getAnnualizedLogApr(
        uint256 exchangeRateLast,
        uint256 exchangeRateNow,
        uint256 timeElapsed
    ) public pure override returns (uint256) {
        // Get the natural logarithm of last exchange rate
        uint256 logRateYesterday = exchangeRateLast.ln();

        // Get the natural logarithm of current exchange rate
        uint256 logRateToday = exchangeRateNow.ln();

        // Get the log rate difference
        uint256 logRateDiff = logRateToday - logRateYesterday;

        // The log APR is = (lorRateDif * 1 year) / time since last update
        uint256 logAprInYear = (logRateDiff * SECONDS_PER_YEAR) / timeElapsed;

        // Get the natural exponent of the log APR
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
    function lpTokenPriceUsd(address lpTokenPair) external view override returns (uint256 lpTokenPrice) {
        // Load to memory
        CygnusNebula memory cygnusNebula = getNebula[lpTokenPair];

        /// custom:error PairNotInitialized Avoid getting price unless lpTokenPair's price is being tracked
        if (!cygnusNebula.initialized) {
            revert CygnusNebulaOracle__PairNotInitialized(lpTokenPair);
        }

        // 1. Get reserves of Token A and Token B to compute k
        (uint112 reservesTokenA, uint112 reservesTokenB /* Timestamp */, ) = IDexPair(lpTokenPair).getReserves();

        // 2. Get total supply of the underlying LP Token
        uint256 totalSupply = IDexPair(lpTokenPair).totalSupply();

        // Adjust reserves Token A with cached scalar
        uint256 adjustedReservesA = normalize(cygnusNebula.token0, reservesTokenA);

        // Adjust reserves Token B with cached scalar
        uint256 adjustedReservesB = normalize(cygnusNebula.token1, reservesTokenB);

        // 3. Geometric mean of reservesA and reservesB
        uint256 productReserves = adjustedReservesA.gm(adjustedReservesB);

        // Chainlink price feed for this lpTokens token0
        (, int256 priceA, , , ) = cygnusNebula.priceFeedA.latestRoundData();

        // Chainlink price feed for this lpTokens token1
        (, int256 priceB, , , ) = cygnusNebula.priceFeedB.latestRoundData();

        // Adjust price Token A to 18 decimals
        uint256 adjustedPriceA = normalize(IERC20(address(cygnusNebula.priceFeedA)), uint256(priceA));

        // Adjust price Token B to 18 decimals
        uint256 adjustedPriceB = normalize(IERC20(address(cygnusNebula.priceFeedB)), uint256(priceB));

        // Chainlink price feed for denomination token
        (, int256 latestRoundUsd, , , ) = denominationAggregator.latestRoundData();

        // Adjust price to 18 decimals
        uint256 adjustedUsdPrice = normalize(IERC20(address(denominationAggregator)), uint256(latestRoundUsd));

        // 4. Geometric mean of priceA and priceB
        uint256 productPrice = adjustedPriceA.gm(adjustedPriceB);

        // LP Token price denominated in USD
        uint256 lpPrice = PRBMath.mulDiv(productReserves, productPrice, totalSupply) * 2;

        // 5. Return LP Token price denominated in denomination token
        lpTokenPrice = lpPrice.div(adjustedUsdPrice) / (10 ** (18 - decimals));
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function assetPricesUsd(
        address lpTokenPair
    ) external view override returns (uint256 tokenPriceA, uint256 tokenPriceB) {
        // Load to memory
        CygnusNebula memory cygnusNebula = getNebula[lpTokenPair];

        /// custom:error PairNotInitialized Avoid getting price unless lpTokenPair's price is being tracked
        if (!cygnusNebula.initialized) {
            revert CygnusNebulaOracle__PairNotInitialized(lpTokenPair);
        }

        // Chainlink price feed for this lpTokens token0
        (, int256 priceA, , , ) = cygnusNebula.priceFeedA.latestRoundData();

        // Chainlink price feed for this lpTokens token1
        (, int256 priceB, , , ) = cygnusNebula.priceFeedB.latestRoundData();

        // Chainlink price feed for denomination token
        (, int256 latestRoundUsd, , , ) = denominationAggregator.latestRoundData();

        // Adjust price Token A to 18 decimals
        uint256 adjustedPriceA = normalize(IERC20(address(cygnusNebula.priceFeedA)), uint256(priceA));

        // Adjust price Token B to 18 decimals
        uint256 adjustedPriceB = normalize(IERC20(address(cygnusNebula.priceFeedB)), uint256(priceB));

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
        AggregatorV3Interface aggregatorA,
        AggregatorV3Interface aggregatorB
    ) external override nonReentrant cygnusAdmin {
        // Load to storage
        CygnusNebula storage cygnusNebula = getNebula[lpTokenPair];

        /// @custom:error PairIsinitialized Avoid duplicate oracle
        if (cygnusNebula.initialized) {
            revert CygnusNebulaOracle__PairAlreadyInitialized(lpTokenPair);
        }

        // Assign id
        cygnusNebula.oracleId = nebulaSize();

        // Store LP Token address
        cygnusNebula.underlying = lpTokenPair;

        // Cache scalars for the LP Token
        // Token0
        cygnusNebula.token0 = IERC20(IDexPair(lpTokenPair).token0());

        // Token0
        cygnusNebula.token1 = IERC20(IDexPair(lpTokenPair).token1());

        // token0 scalar
        computeScalar(cygnusNebula.token0);

        // token1 scalar
        computeScalar(cygnusNebula.token1);

        // Cache scalars for Chainlink oracle aggregators
        // Store the chainlink's aggregator contract address for this LP Token's token0
        cygnusNebula.priceFeedA = aggregatorA;

        // Store the chainlink's aggregator contract address for this LP Token's token1
        cygnusNebula.priceFeedB = aggregatorB;

        // AggregatorA scalar
        computeScalar(IERC20(address(aggregatorA)));

        // AggregatorB scalar
        computeScalar(IERC20(address(aggregatorB)));

        // Add to list
        allNebulas.push(lpTokenPair);

        // Store oracle status
        cygnusNebula.initialized = true;

        /// @custom:event InitializeCygnusNebula
        emit InitializeCygnusNebula(true, cygnusNebula.oracleId, lpTokenPair, aggregatorA, aggregatorB);
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
