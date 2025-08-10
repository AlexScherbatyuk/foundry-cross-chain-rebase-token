// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from
    "@chainlink-ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from
    "@chainlink-ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@chainlink-ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "@chainlink-ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@chainlink-ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "@chainlink-ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink-ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

/**
 * @title CrossChain
 * @notice This contract is used to test the cross-chain functionality
 * @dev This contract is used to test the cross-chain functionality of the RebaseToken
 */
contract CrossChain is Test {
    address owner = makeAddr("owner");
    address user = makeAddr("user");

    uint256 SEND_VALUE = 1e5;

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;

    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;

    Vault vault;

    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbSepoliaPool;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    function setUp() public {
        // 1. Create forks
        sepoliaFork = vm.createSelectFork("sepolia-eth"); // Means that the sepolia fork is selected after creating it
        arbSepoliaFork = vm.createFork("arb-sepolia");

        console.log("");
        console.log("=========== Fork IDs ===========");
        console.log("sepoliaFork: ", sepoliaFork);
        console.log("arbSepoliaFork: ", arbSepoliaFork);

        // 2. Deploy CCIPLocalSimulatorFork
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 3. We have got the network details for the sepolia fork
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        // 4. Deploy and configure on sepolia
        vm.startPrank(owner);
        sepoliaToken = new RebaseToken();
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        vault = new Vault(IRebaseToken(address(sepoliaToken)));

        console.log("");
        console.log("=========== Sepolia Deployments ===========");
        console.log("sepoliaPool contract address: ", address(sepoliaPool));
        console.log("sepoliaToken contract address: ", address(sepoliaToken));
        console.log("vault contract address: ", address(vault));

        // 5. Grant Mint and Burn roles to the token and pool
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));

        // 6. Register CCIP Admin to be the owner of the token
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );

        // 7. Accept Admin role to the token
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));

        // 8. Set the pool for the token
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(sepoliaToken), address(sepoliaPool)
        );

        vm.stopPrank();

        // 2. Switch to the arbSepolia fork
        vm.selectFork(arbSepoliaFork); // Selects the arbSepolia fork as current network

        // 5. We have got the network details for the arbSepolia fork
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(owner);

        // 6. Deploy and configure on arbSepolia
        arbSepoliaToken = new RebaseToken();
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );

        console.log("");
        console.log("=========== Arbitrum Sepolia Deployments ===========");
        console.log("arbSepoliaPool contract address: ", address(arbSepoliaPool));
        console.log("arbSepoliaToken contract address: ", address(arbSepoliaToken));

        console.log("ccipLocalSimulatorFork contract address: ", address(ccipLocalSimulatorFork));
        console.log("arbSepoliaNetworkDetails.chainSelector: ", arbSepoliaNetworkDetails.chainSelector);
        console.log("arbSepoliaNetworkDetails routerAddress: ", arbSepoliaNetworkDetails.routerAddress);

        // 7. Grant Mint and Burn roles to the token and pool
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));

        // 8. Register CCIP Admin to be the owner of the token
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbSepoliaToken)
        );

        // 9. Accept Admin role to the token
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));

        // 10. Set the pool for the token
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbSepoliaToken), address(arbSepoliaPool)
        );

        vm.stopPrank();

        // 11. Configure the token pool for the sepolia fork
        // in order to receive and send tokens to the arbSepolia fork
        configureTokenPool(
            sepoliaFork,
            address(sepoliaPool),
            arbSepoliaNetworkDetails.chainSelector,
            address(arbSepoliaPool),
            address(arbSepoliaToken)
        );

        // 12. Configure the token pool for the arbSepolia fork
        // in order to receive and send tokens to the sepolia fork
        configureTokenPool(
            arbSepoliaFork,
            address(arbSepoliaPool),
            sepoliaNetworkDetails.chainSelector,
            address(sepoliaPool),
            address(sepoliaToken)
        );
    }

    /**
     * @dev Configure the token pool for the local fork
     * in order to receive and send tokens to the remote fork
     * @param fork The fork to configure the token pool for
     * @param localPool The local pool to configure
     * @param remoteChainSelector The remote chain selector
     * @param remotePool The remote pool to configure
     * @param remoteTokenAddress The remote token address
     */
    function configureTokenPool(
        uint256 fork,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteTokenAddress
    ) public {
        console.log("");
        console.log("=========== Token pool configuration ===========");
        console.log("fork: ", fork);
        console.log("localPool: ", localPool);
        console.log("remotePool: ", remotePool);
        console.log("remoteTokenAddress: ", remoteTokenAddress);
        console.log("remoteChainSelector: ", remoteChainSelector);
        console.log("=========== Token pool configuration ===========");

        vm.selectFork(fork);
        vm.prank(owner);

        bytes[] memory remotePoolAdresses = new bytes[](1);
        remotePoolAdresses[0] = abi.encode(remotePool);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: remotePoolAdresses[0],
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool(localPool).applyChainUpdates(chainsToAdd);
        vm.stopPrank();
    }

    /**
     * @dev Bridge tokens from the local fork to the remote fork
     * @param amountToBridge The amount of tokens to bridge
     * @param localFork The local fork
     * @param remoteFork The remote fork
     */
    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        console.log("");
        console.log("=========== Bridge tokens inputs ===========");
        console.log("amountToBridge: ", amountToBridge);
        console.log("localFork: ", localFork);
        console.log("remoteFork: ", remoteFork);
        console.log("localNetworkDetails: ", localNetworkDetails.chainSelector);
        console.log("remoteNetworkDetails: ", remoteNetworkDetails.chainSelector);
        console.log("localToken: ", address(localToken));
        console.log("remoteToken: ", address(remoteToken));
        console.log("");

        // 1. Switch to the local fork (sepolia)
        vm.selectFork(localFork);

        // 2. Configure the message
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 500_000}))
        });

        // 3. Get the fee for the message
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);

        // 4. Request the fee from the faucet
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);

        console.log("=========== Local Fork ===========");
        console.log("calculated fee: ", fee);
        console.log("user Link balance: ", IERC20(localNetworkDetails.linkAddress).balanceOf(user));

        // 5. Approve the fee
        vm.prank(user);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);

        // 6. Approve the token
        vm.prank(user);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);
        uint256 localBalanceBefore = IERC20(address(localToken)).balanceOf(user);
        console.log("localBalanceBefore of localToken before bridge: ", localBalanceBefore);

        // 7. Send the message
        vm.prank(user);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);

        // 8. Get the balance of the token after the bridge
        uint256 localBalanceAfter = IERC20(address(localToken)).balanceOf(user);
        console.log("localBalanceAfter of localToken after bridge: ", localBalanceAfter);

        // 9. Assert the balance of the token after the bridge
        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge);

        // 10. Get the user interest rate of the token
        uint256 localUserInterestRate = IRebaseToken(address(localToken)).getUserInterestRate(user);
        console.log("localUserInterestRate: ", localUserInterestRate);

        // 11. Switch to the remote fork (arbSepolia)
        vm.selectFork(remoteFork);

        console.log("");
        console.log("=========== Remote Fork ===========");
        console.log("remote fork: ", remoteFork);

        // 12. Wait for 20 minutes
        vm.warp(block.timestamp + 20 minutes);

        // 13. Get the balance of the token before the bridge
        uint256 remoteBalanceBefore = IERC20(address(remoteToken)).balanceOf(user);
        console.log("remoteBalanceBefore of remoteToken before bridge: ", remoteBalanceBefore);

        // 14. Switch to the local fork
        // since we use switchChainAndRouteMessage we need to switch back to the local fork
        // because switchChainAndRouteMessage performs a switch to the remote fork as well
        // if we dont switch back to the local fork, the message will not be routed to the remote fork
        // and the test will fail ( probably limmitation of current version of chainlink ccip)
        vm.selectFork(localFork);

        // 15. Switch to the remote fork and route the message
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        // 16. Get the balance of the token after the bridge
        uint256 remoteBalanceAfter = IERC20(address(remoteToken)).balanceOf(user);
        console.log("remoteBalanceAfter of remoteToken after bridge: ", remoteBalanceAfter);

        // 17. Assert the balance of the token after the bridge
        assertEq(remoteBalanceAfter, remoteBalanceBefore + amountToBridge);

        // 18. Get the user interest rate of the token
        uint256 remoteUserInterestRate = IRebaseToken(address(remoteToken)).getUserInterestRate(user);
        console.log("remoteUserInterestRate of remoteToken: ", remoteUserInterestRate);

        // 19. Assert the user interest rate of the token
        assertEq(localUserInterestRate, remoteUserInterestRate);
    }

    function testBridgeAllTokens() public {
        // 1. Select the sepolia fork
        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);

        // 2. Deposit the value to the vault
        // in order to send some ETH to the vault we need to cast address and then to payable
        // finally cast payable address to Vault to access the deposit function
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();

        // 3. Assert the balance of the token of the user
        // should be the same as the SEND_VALUE because no time has passed
        assertEq(sepoliaToken.balanceOf(user), SEND_VALUE);

        bridgeTokens(
            SEND_VALUE, // amount to bridge
            sepoliaFork, // local fork
            arbSepoliaFork, // remote fork
            sepoliaNetworkDetails, // local network details (sepolia)
            arbSepoliaNetworkDetails, // remote network details (arbSepolia)
            sepoliaToken, // local token (sepolia)
            arbSepoliaToken // remote token (arbSepolia)
        );
    }
}
