//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;
import {Script, console} from "forge-std/Script.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title SendPackedUserOp
 * @notice Helper contract for generating signed UserOperations
 * @dev Used in tests and scripts to create properly formatted and signed UserOperations
 *      for ERC-4337 account abstraction. Handles nonce retrieval, hashing, and signing.
 */
contract SendPackedUserOp is Script {
    using MessageHashUtils for bytes32;

    function run() public {}

    /**
     * @notice Generates a signed UserOperation for a given call
     * @dev Gets nonce from EntryPoint, creates UserOperation, hashes it, signs with EIP-191,
     *      and returns the complete signed UserOperation ready to submit.
     * @param callData The calldata for the operation (e.g., execute function call)
     * @param config Network configuration containing EntryPoint address
     * @param minialAccount The account contract address (sender in UserOperation)
     * @return PackedUserOperation The complete signed UserOperation
     */
    function generateSignedUserOperation(
        bytes memory callData,
        HelperConfig.NetworkConfig memory config,
        address minialAccount
    ) public view returns (PackedUserOperation memory) {
        // Get current nonce from EntryPoint (key = 0 for default sequence)
        uint256 nonce = IEntryPoint(config.entryPoint).getNonce(minialAccount, 0);
        PackedUserOperation memory userOp = _generateUnsignedUserOperation(callData, minialAccount, nonce);

        // Get UserOperation hash from EntryPoint
        bytes32 userOpHash = IEntryPoint(config.entryPoint).getUserOpHash(userOp);
        bytes32 digest = userOpHash.toEthSignedMessageHash();

        // Sign with appropriate key based on chain
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 ANVIL_DEFAULT_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        if (block.chainid == 31337) {
            (v, r, s) = vm.sign(ANVIL_DEFAULT_KEY, digest);
            userOp.signature = abi.encodePacked(r, s, v);
        } else {
            (v, r, s) = vm.sign(config.account, digest);
            userOp.signature = abi.encodePacked(r, s, v);
        }
        return userOp;
    }

    /**
     * @notice Creates an unsigned UserOperation struct
     * @dev Sets up gas limits and fees. Signature field is left empty - caller should sign and add it.
     * @param callData The calldata for the operation
     * @param sender The account contract address
     * @param nonce The nonce from EntryPoint
     * @return PackedUserOperation The unsigned UserOperation struct
     */
    function _generateUnsignedUserOperation(bytes memory callData, address sender, uint256 nonce)
        internal
        pure
        returns (PackedUserOperation memory)
    {
        uint128 verificationGasLimit = 17000000;
        uint128 callGasLimit = verificationGasLimit;
        uint128 maxPriorityFeePerGas = 256;
        uint128 maxFeePerGas = maxPriorityFeePerGas;

        return PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: hex"", // Empty - account already deployed
            callData: callData,
            accountGasLimits: bytes32(uint256(verificationGasLimit) << 128 | uint256(callGasLimit)),
            preVerificationGas: verificationGasLimit,
            gasFees: bytes32(uint256(maxPriorityFeePerGas) << 128 | uint256(maxFeePerGas)),
            paymasterAndData: hex"", // No paymaster used
            signature: hex"" // Will be filled by caller
        });
    }
}
