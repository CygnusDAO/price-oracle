// Deployment of oracle to get prices of assets denominated in DAI
async function main() {
    // Chainlink's DAI aggregator address on Avalanche
    let usdcChainlinkAggregator = '0xF096872672F44d6EBA71458D74fe67F9a77a23B9';

    // Factory
    let CygnusOracle = await ethers.getContractFactory('ChainlinkNebulaOracle');

    // Deploy oracle with DAI aggregator
    let cygnusOracle = await CygnusOracle.deploy(usdcChainlinkAggregator);

    console.log('Oracle deployed to: ', cygnusOracle.address);

    console.log('Deploy transaction: ', cygnusOracle.deployTransaction.hash);

    await cygnusOracle.deployed();

    console.log('Success');
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
