// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {TokenPool} from "@chainlink-ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {Pool} from "@chainlink-ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {IERC20} from "@chainlink-ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract RebaseTokenPool is TokenPool {
    constructor(IERC20 _token, address[] memory _allowList, address _rmnProxy, address _router) TokenPool(_token, _allowList, _rmnProxy, _router) {}

    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn) external returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut) {
        _validateLockOrBurn(lockOrBurnIn);
        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        // @return named variable lockOrBurnOut
        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector), // destination token
            destPoolData: abi.encode(userInterestRate) // abi incoded data to be send cross chain
        });
    }

    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn) external returns (Pool.ReleaseOrMintOutV1 memory releaseOrMintOut) {
        _validateReleaseOrMint(releaseOrMintIn);
        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        IRebaseToken(address(i_token)).mint(releaseOrMintIn.receiver, releaseOrMintIn.amount, userInterestRate);

        // @return named variable releaseOrMintOut
        releaseOrMintOut = Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
    }
}
