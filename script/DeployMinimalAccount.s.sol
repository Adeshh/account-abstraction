//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;
import {Script} from "forge-std/Script.sol";
import {MinimalAccount} from "../src/ethereum/MinimalAccount.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/**
 * @title DeployMinimalAccount
 * @notice Deployment script for MinimalAccount contract
 * @dev Deploys a new MinimalAccount with the EntryPoint from HelperConfig.
 *      Transfers ownership to the configured account address.
 */
contract DeployMinimalAccount is Script {
    /**
     * @notice Deploys a MinimalAccount contract
     * @return minimalAccount The deployed MinimalAccount instance
     * @return config The HelperConfig instance used for deployment
     */
    function run() public returns (MinimalAccount, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address entryPoint, address account) = config.activeNetworkConfig();

        vm.startBroadcast(account);
        MinimalAccount minimalAccount = new MinimalAccount(entryPoint);
        minimalAccount.transferOwnership(account);
        vm.stopBroadcast();
        return (minimalAccount, config);
    }
}
