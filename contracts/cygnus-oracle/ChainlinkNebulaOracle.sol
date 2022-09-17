// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

// Dependencies
import { IChainlinkNebulaOracle } from "./interfaces/IChainlinkNebulaOracle.sol";
import { ReentrancyGuard } from "./utils/ReentrancyGuard.sol";
import { Context } from "./utils/Context.sol";
import { ERC20Normalizer } from "./utils/ERC20Normalizer.sol";

// Libraries
import { PRBMath, PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";

// Interfaces
import { AggregatorV3Interface } from "./interfaces/AggregatorV3Interface.sol";
import { IDexPair } from "./interfaces/IDexPair.sol";
import { IERC20 } from "./interfaces/IERC20.sol";

/**
 *  @title  ChainlinkNebulaOracle
 *  @author CygnusDAO
 *  @notice Oracle used by Cygnus that returns the price of 1 LP Token in USDC. In case need
 *          different implementation just update the denomination variable `usdc` with another price feed
 *  @notice Implementation of fair lp token pricing using Chainlink price feeds
 *          https://blog.alphaventuredao.io/fair-lp-token-pricing/
 */
contract ChainlinkNebulaOracle is IChainlinkNebulaOracle, Context, ReentrancyGuard, ERC20Normalizer {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 Fixed point 18 decimal math library, imports main library `PRBMath`
     */
    using PRBMathUD60x18 for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @custom:struct ChainlinkNebula Official record of all Chainlink oracles used by Cygnus
     *  @custom:member initialized Whether an LP Token is being tracked or not
     *  @custom:member oracleId The ID of the LP Token tracked by the oracle
     *  @custom:member underlying The address of the LP Token
     *  @custom:member priceFeedA The address of the Chainlink aggregator used for this LP Token's Token0
     *  @custom:member priceFeedB The address of the Chainlink aggregator used for this LP Token's Token1
     */
    struct ChainlinkNebula {
        bool initialized;
        uint24 oracleId;
        address underlying;
        AggregatorV3Interface priceFeedA;
        AggregatorV3Interface priceFeedB;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    mapping(address => ChainlinkNebula) public override getNebula;

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    address[] public override allNebulas;

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    string public constant override name = "Cygnus-Chainlink: LP Oracle";

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    string public constant override symbol = "CygNebula";

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    uint8 public constant override decimals = 6;

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    uint8 public constant override version = 1;

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    AggregatorV3Interface public immutable override usdc;

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    address public override admin;

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    address public override pendingAdmin;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Oracle
     *  @param priceDenominator The denomination token this oracle returns the prices in
     */
    constructor(AggregatorV3Interface priceDenominator) {
        // Assign admin
        admin = _msgSender();

        // Assign the denomination the LP Token will be priced in
        usdc = AggregatorV3Interface(priceDenominator);

        // get decimals of this aggregator - calculates only once and stores
        computeScalar(IERC20(address(priceDenominator)));
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
            revert ChainlinkNebulaOracle__MsgSenderNotAdmin(_msgSender());
        }
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    function nebulaSize() public view override returns (uint24) {
        // Return how many LP Tokens we are tracking
        return uint24(allNebulas.length);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    function usdcPrice() external view override returns (uint256) {
        // Chainlink price feed for the LP denomination token, in our case USDC
        (, int256 latestRoundUsdc, , , ) = usdc.latestRoundData();

        // Return price without adjusting decimals - not used by this contract, we keep it here to quickly checl
        // in case something goes wrong
        return uint256(latestRoundUsdc);
    }

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    function lpTokenPriceUsdc(address lpTokenPair) external view override returns (uint256 lpTokenPrice) {
        // Load to memory
        ChainlinkNebula memory cygnusNebula = getNebula[lpTokenPair];

        /// custom:error PairNotInitialized Avoid getting price unless lpTokenPair's price is being tracked
        if (!cygnusNebula.initialized) {
            revert ChainlinkNebulaOracle__PairNotInitialized(lpTokenPair);
        }

        // 1. Get reserves of Token A and Token B to compute k
        (
            uint112 reservesTokenA,
            uint112 reservesTokenB, /* Timestamp */

        ) = IDexPair(lpTokenPair).getReserves();

        // 2. Get total supply of the underlying LP Token
        uint256 totalSupply = IDexPair(lpTokenPair).totalSupply();

        // Adjust reserves Token A
        uint256 adjustedReservesA = normalize(IERC20(IDexPair(lpTokenPair).token0()), reservesTokenA);

        // Adjust reserves Token B
        uint256 adjustedReservesB = normalize(IERC20(IDexPair(lpTokenPair).token1()), reservesTokenB);

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

        // Chainlink price feed for denomination token, in cygnus' case USDC
        (, int256 latestRoundUsdc, , , ) = usdc.latestRoundData();

        // Adjust USDC price to 18 decimals
        uint256 adjustedUsdcPrice = normalize(IERC20(address(usdc)), uint256(latestRoundUsdc));

        // 4. Geometric mean of priceA and priceB
        uint256 productPrice = adjustedPriceA.gm(adjustedPriceB);

        // LP Token price denominated in USD
        uint256 lpTokenPriceUsd = PRBMath.mulDiv(productReserves, productPrice, totalSupply) * 2;

        // 5. Return LP Token price denominated in USDC
        lpTokenPrice = lpTokenPriceUsd.div(adjustedUsdcPrice) / 1e12;
    }

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     */
    function assetPricesUsdc(address lpTokenPair)
        external
        view
        override
        returns (uint256 tokenPriceA, uint256 tokenPriceB)
    {
        // Load to memory
        ChainlinkNebula memory cygnusNebula = getNebula[lpTokenPair];

        /// custom:error PairNotInitialized Avoid getting price unless lpTokenPair's price is being tracked
        if (!cygnusNebula.initialized) {
            revert ChainlinkNebulaOracle__PairNotInitialized(lpTokenPair);
        }

        // Chainlink price feed for this lpTokens token0
        (, int256 priceA, , , ) = cygnusNebula.priceFeedA.latestRoundData();

        // Chainlink price feed for this lpTokens token1
        (, int256 priceB, , , ) = cygnusNebula.priceFeedB.latestRoundData();

        // Chainlink price feed for denomination token, in cygnus' case USDC
        (, int256 latestRoundUsdc, , , ) = usdc.latestRoundData();

        // Adjust price Token A to 18 decimals
        uint256 adjustedPriceA = normalize(IERC20(address(cygnusNebula.priceFeedA)), uint256(priceA));

        // Adjust price Token B to 18 decimals
        uint256 adjustedPriceB = normalize(IERC20(address(cygnusNebula.priceFeedB)), uint256(priceB));

        // Adjust USDC price to 18 decimals
        uint256 adjustedUsdcPrice = normalize(IERC20(address(usdc)), uint256(latestRoundUsdc));

        // Return token0's price in USDC
        tokenPriceA = adjustedPriceA.div(adjustedUsdcPrice) / 1e12;

        // Return token1's price in USDC
        tokenPriceB = adjustedPriceB.div(adjustedUsdcPrice) / 1e12;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     *  @custom:security non-reentrant
     */
    function initializeNebula(
        address lpTokenPair,
        AggregatorV3Interface aggregatorA,
        AggregatorV3Interface aggregatorB
    ) external override nonReentrant cygnusAdmin {
        // Load to storage
        ChainlinkNebula storage cygnusNebula = getNebula[lpTokenPair];

        /// @custom:error PairIsinitialized Avoid duplicate oracle
        if (cygnusNebula.initialized) {
            revert ChainlinkNebulaOracle__PairAlreadyInitialized(lpTokenPair);
        }

        // Assign id
        cygnusNebula.oracleId = nebulaSize();

        // Store LP Token address
        cygnusNebula.underlying = lpTokenPair;

        // Store the chainlink's aggregator contract address for this LP Token's token0
        cygnusNebula.priceFeedA = aggregatorA;

        // Store the chainlink's aggregator contract address for this LP Token's token1
        cygnusNebula.priceFeedB = aggregatorB;

        // Store oracle status
        cygnusNebula.initialized = true;

        // Compute scalars for the LP Token and for Chainlink oracle aggregators

        // token0 scalar
        computeScalar(IERC20(IDexPair(lpTokenPair).token0()));

        // token1 scalar
        computeScalar(IERC20(IDexPair(lpTokenPair).token1()));

        // AggregatorA scalar
        computeScalar(IERC20(address(aggregatorA)));

        // AggregatorB scalar
        computeScalar(IERC20(address(aggregatorB)));

        // Add to list
        allNebulas.push(lpTokenPair);

        /// @custom:event InitializeChainlinkNebula
        emit InitializeChainlinkNebula(true, cygnusNebula.oracleId, lpTokenPair, aggregatorA, aggregatorB);
    }

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     *  @custom:security non-reentrant
     */
    function deleteNebula(address lpTokenPair) external override nonReentrant cygnusAdmin {
        /// @custom:error PairNotinitialized Avoid delete if not initialized
        if (!getNebula[lpTokenPair].initialized) {
            revert ChainlinkNebulaOracle__PairNotInitialized(lpTokenPair);
        }

        // Get the index of this oracle
        uint24 oracleId = getNebula[lpTokenPair].oracleId;

        // Get the first price feed for this oracle
        AggregatorV3Interface priceFeedA = getNebula[lpTokenPair].priceFeedA;

        // Get the second price feed for this oracle
        AggregatorV3Interface priceFeedB = getNebula[lpTokenPair].priceFeedB;

        // Delete from array and leave a gap as to not mix up IDs
        delete allNebulas[oracleId];

        // Delete from object
        delete getNebula[lpTokenPair];

        /// @custom:event DeleteChainlinkNebula
        emit DeleteChainlinkNebula(oracleId, lpTokenPair, priceFeedA, priceFeedB, _msgSender());
    }

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     *  @custom:security non-reentrant
     */
    function setOraclePendingAdmin(address newPendingAdmin) external override nonReentrant cygnusAdmin {
        // Pending admin initial is always zero
        /// @custom:error PendingAdminAlreadySet Avoid setting the same pending admin twice
        if (newPendingAdmin == pendingAdmin) {
            revert ChainlinkNebulaOracle__PendingAdminAlreadySet(newPendingAdmin);
        }

        // Assign address of the requested admin
        pendingAdmin = newPendingAdmin;

        /// @custom:event NewOraclePendingAdmin
        emit NewOraclePendingAdmin(admin, newPendingAdmin);
    }

    /**
     *  @inheritdoc IChainlinkNebulaOracle
     *  @custom:security non-reentrant
     */
    function setOracleAdmin() external override nonReentrant cygnusAdmin {
        /// @custom:error AdminCantBeZero Avoid settings the admin to the zero address
        if (pendingAdmin == address(0)) {
            revert ChainlinkNebulaOracle__AdminCantBeZero(pendingAdmin);
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
