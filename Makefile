-include .env

.PHONY: install

install:; forge install openzeppelin/openzeppelin-contracts@v5.4.0 && forge install smartcontractkit/ccip@v2.17.0-ccip1.5.16 && forge install smartcontractkit/chainlink-local@v0.2.5-beta.0
