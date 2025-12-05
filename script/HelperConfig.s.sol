//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;
import {Script, console} from "forge-std/Script.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";

contract HelperConfig is Script {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        address entryPoint;
        address account;
    }

    NetworkConfig public activeNetworkConfig;
    address constant ANVIL_DEFAULT_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant BURNER_WALLET = 0x5d6eD63EA4aDcecc5B7a622f6f2D5D345e55b843;
    //mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ANVIL_CHAIN_ID = 31337;
    uint256 public constant ZKSYNC_SEPOLIA_CHAIN_ID = 300;

    constructor() {
        if (block.chainid == ETH_SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == ZKSYNC_SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getZkSepoliaConfig();
        } else if (block.chainid == ANVIL_CHAIN_ID) {
            activeNetworkConfig = getOrCreateAnvilConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, account: BURNER_WALLET});
    }

    function getZkSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({entryPoint: address(0), account: BURNER_WALLET});
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.entryPoint != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        EntryPoint entryPoint = new EntryPoint();
        vm.stopBroadcast();
        return NetworkConfig({entryPoint: address(entryPoint), account: ANVIL_DEFAULT_ACCOUNT});
    }

    function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
