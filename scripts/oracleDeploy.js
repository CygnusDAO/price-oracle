// Deployment of oracle to get prices of assets denominated in DAI
async function main() {
    // Chainlink's DAI aggregator address on Avalanche
    let daiCLinkAggregator = '0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300';

    // Factory
    let CygnusOracle = await ethers.getContractFactory('ChainlinkNebulaOracle');

    // Deploy oracle with DAI aggregator
    let cygnusOracle = await CygnusOracle.deploy(daiCLinkAggregator);

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
