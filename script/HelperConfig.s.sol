//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;
import {Script, console} from "forge-std/Script.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";

/**
 * @title HelperConfig
 * @notice Network configuration helper for different chains
 * @dev Automatically detects the chain and provides appropriate EntryPoint and account addresses.
 *      For Anvil, it deploys a fresh EntryPoint. For Sepolia, it uses the canonical EntryPoint.
 */
contract HelperConfig is Script {
    /// @notice Thrown when chain ID is not supported
    error HelperConfig__InvalidChainId();

    /// @notice Network configuration containing EntryPoint and account addresses
    struct NetworkConfig {
        address entryPoint;
        address account;
    }

    /// @notice The active network configuration based on current chain ID
    NetworkConfig public activeNetworkConfig;

    /// @dev Anvil's first default account (used for local testing)
    address constant ANVIL_DEFAULT_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    /// @dev Burner wallet address (used for testnet deployments)
    address constant BURNER_WALLET = 0x5d6eD63EA4aDcecc5B7a622f6f2D5D345e55b843;

    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ANVIL_CHAIN_ID = 31337;
    uint256 public constant ZKSYNC_SEPOLIA_CHAIN_ID = 300;

    /**
     * @notice Initializes the config based on current chain ID
     * @dev Automatically selects the right configuration for the chain we're on
     */
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

    /**
     * @notice Returns configuration for Ethereum Sepolia
     * @return NetworkConfig with canonical EntryPoint address
     */
    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, account: BURNER_WALLET});
    }

    /**
     * @notice Returns configuration for zkSync Sepolia
     * @return NetworkConfig with zero EntryPoint (zkSync doesn't use EntryPoint)
     */
    function getZkSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({entryPoint: address(0), account: BURNER_WALLET});
    }

    /**
     * @notice Creates or returns existing Anvil configuration
     * @dev Deploys a new EntryPoint contract if one doesn't exist yet
     * @return NetworkConfig with deployed EntryPoint for local testing
     */
    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.entryPoint != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        EntryPoint entryPoint = new EntryPoint();
        vm.stopBroadcast();
        return NetworkConfig({entryPoint: address(entryPoint), account: ANVIL_DEFAULT_ACCOUNT});
    }

    /**
     * @notice Returns the active network configuration
     * @return The current NetworkConfig for this chain
     */
    function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
