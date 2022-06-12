// Hardhat
require('solidity-coverage');
require('hardhat-contract-sizer');
require('@nomiclabs/hardhat-waffle');

// JS
const path = require('path')
require('dotenv').config({ path: path.resolve(__dirname, './.env') });
const { PRIVATE_KEY } = process.env;

module.exports = {
    solidity: {
        version: '0.8.4',
        settings: {
            optimizer: {
                enabled: true,
                runs: 800,
            },
        },
    },
    gasReporter: {
        enabled: process.env.REPORT_GAS ? false : true,
    },
    networks: {
        avalancheFujiTestnet: {
            url: 'https://api.avax-test.network/ext/bc/C/rpc',
            chainId: 43113,
            accounts: [`0x${process.env.PRIVATE_KEY}`],
            forking: {
                url: 'https://api.avax-test.network/ext/bc/C/rpc',
                enabled: true,
            },
        },
        avalancheMain: {
            url: 'https://api.avax.network/ext/bc/C/rpc',
            chainId: 43114,
            accounts: [`0x${process.env.PRIVATE_KEY}`],
            forking: {
                url: 'https://api.avax.network/ext/bc/C/rpc',
                enabled: true,
            },
        },
    },
};
