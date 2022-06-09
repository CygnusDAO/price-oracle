/** This is a description of the foo function. */
async function main() {

  let CygnusOracle = await ethers.getContractFactory('ChainlinkNebulaOracle');
  let cygnusOracle = await CygnusOracle.deploy('0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300');

  console.log('Oracle deployed to: ', cygnusOracle.address)

  console.log('Deploy transaction: ', cygnusOracle.deployTransaction.hash)

  await cygnusOracle.deployed();

  console.log('Success')
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });

