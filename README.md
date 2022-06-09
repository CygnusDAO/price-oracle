# Cygnus-Chainlink LP Oracle

A fair reserves LP Oracle using Chainlink price feeds.

It returns the price of 1 LP Token denominated in DAI.

The oracle returns the price of each LP Token's assets from Chainlink price feeds and uses it to query against the pool's
constant `K` to avoid using the reserves themselves to determine LP price. This prevents price manipulations from attacks that move along
constant AMM curves such as flash loans.

For more info read [here](https://blog.alphaventuredao.io/fair-lp-token-pricing/) and [here](https://cmichel.io/pricing-lp-tokens/)
