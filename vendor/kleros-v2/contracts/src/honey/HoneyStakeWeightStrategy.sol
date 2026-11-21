// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {IStakeWeightStrategy, IStakeIdentity} from "./IStakeWeightStrategy.sol";

/// @notice Honey v2 verified-court weighting strategy.
/// @dev The human court and automation subcourt both use sqrt(total raw active stake per verified identity). Other courts retain
///      upstream linear weight.
contract HoneyStakeWeightStrategy is IStakeWeightStrategy {
    uint96 public immutable humanCourtId;
    uint96 public immutable automationCourtId;

    IStakeIdentity public immutable identityRegistry;

    constructor(uint96 _humanCourtId, uint96 _automationCourtId, address _identityRegistry) {
        require(_identityRegistry.code.length > 0, "Identity resolver required");
        identityRegistry = IStakeIdentity(_identityRegistry);
        require(identityRegistry.stakeIdentity(address(0)) == address(0), "Invalid identity resolver");
        humanCourtId = _humanCourtId;
        automationCourtId = _automationCourtId;
    }

    function usesIdentityWeight(uint96 courtId) external view returns (bool) {
        return courtId == humanCourtId || courtId == automationCourtId;
    }

    function identityOf(address account) external view returns (address) {
        return identityRegistry.stakeIdentity(account);
    }

    function effectiveStake(uint96 courtId, address, uint256 rawActiveStake) external view returns (uint256) {
        if (courtId == humanCourtId || courtId == automationCourtId) return _sqrt(rawActiveStake);
        return rawActiveStake;
    }

    function _sqrt(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) return 0;
        uint256 y = x;
        z = 1;
        if (y >= 2 ** 128) {
            y >>= 128;
            z <<= 64;
        }
        if (y >= 2 ** 64) {
            y >>= 64;
            z <<= 32;
        }
        if (y >= 2 ** 32) {
            y >>= 32;
            z <<= 16;
        }
        if (y >= 2 ** 16) {
            y >>= 16;
            z <<= 8;
        }
        if (y >= 2 ** 8) {
            y >>= 8;
            z <<= 4;
        }
        if (y >= 2 ** 4) {
            y >>= 4;
            z <<= 2;
        }
        if (y >= 2 ** 2) z <<= 1;

        unchecked {
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            z = (z + x / z) >> 1;
            uint256 z1 = x / z;
            return z < z1 ? z : z1;
        }
    }
}
