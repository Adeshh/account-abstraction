//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;
import {Script} from "forge-std/Script.sol";
import {MinimalAccount} from "../src/ethereum/MinimalAccount.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployMinimalAccount is Script {
    function run() public returns (MinimalAccount, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address entryPoint, address account) = config.activeNetworkConfig();

        vm.startBroadcast();
        MinimalAccount minimalAccount = new MinimalAccount(entryPoint);
        minimalAccount.transferOwnership(msg.sender);
        vm.stopBroadcast();
        return (minimalAccount, config);
    }
}
