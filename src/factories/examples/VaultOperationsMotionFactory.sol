// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.16;

import "../BaseMotionFactory.sol";

interface Vault {
        function updateStrategyDebtRatio(address _strategy, uint256 _debtRatio) external;
}

// This contract is used as an example implementation for testing purposes only
// It is not meant to be used in production and lacks more security checks
/**
 * @dev Example contract for creating motions that manage emergency operations for yearn vaults
 */
contract VaultOperationsMotionFactory is BaseMotionFactory {
    
        constructor(address _leanTrack, address _gov) BaseMotionFactory(_leanTrack, _gov) {}
        
        // NOTE: this function could also be implemented with batch vaults and limits
        function setDepositLimit(address _vault, uint256 _limit) external onlyAuthorized {
                // WARNING: this is a simplified example, in production you should check if the vault is a valid vault  
                address[] memory targets = new address[](1);
                targets[0] = _vault;
                uint256[] memory values = new uint256[](1);
                values[0] = 0;
                string[] memory signatures = new string[](1);
                bytes[] memory calldatas = new bytes[](1);
                calldatas[0] = abi.encodeWithSignature("setDepositLimit(uint256)", _limit);
                _createMotion(targets, values, signatures, calldatas);
        }

        // emergency function to disable deposit into multiple vaults
        function disableDepositLimit(address[] calldata _vaults) external onlyAuthorized returns (uint256) {
                // iterate vaults and create motion
                address[] memory targets = new address[](_vaults.length);
                uint256[] memory values = new uint256[](_vaults.length);
                string[] memory signatures = new string[](_vaults.length);
                bytes[] memory calldatas = new bytes[](_vaults.length);
                // WARNING: this is a simplified example, in production you should check if the vault is a valid vault  
                for (uint256 i = 0; i < _vaults.length; i++) {
                        targets[i] = _vaults[i];
                        values[i] = 0;
                        calldatas[i] = abi.encodeWithSignature("setDepositLimit(uint256)", 0);
                }
                return _createMotion(targets, values, signatures, calldatas);
        }

        

}