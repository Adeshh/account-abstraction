//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;
import {Script, console} from "forge-std/Script.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract SendPackedUserOp is Script {
    using MessageHashUtils for bytes32;
    function run() public {}

    function generateSignedUserOperation(bytes memory callData, HelperConfig.NetworkConfig memory config)
        public
        view
        returns (PackedUserOperation memory)
    {
        //generate unsigned data for user operation and then sign and return
        uint256 nonce = vm.getNonce(config.account);
        PackedUserOperation memory userOp = _generateUnsignedUserOperation(callData, config.account, nonce);
        //get user opHash
        bytes32 userOpHash = IEntryPoint(config.entryPoint).getUserOpHash(userOp);
        bytes32 digest = userOpHash.toEthSignedMessageHash(); //digest is the hash of the user operation
        //sign the user operation
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(config.account, digest);
        userOp.signature = abi.encodePacked(r, s, v);
        return userOp;
    }

    function _generateUnsignedUserOperation(bytes memory callData, address sender, uint256 nonce)
        internal
        pure
        returns (PackedUserOperation memory)
    {
        uint128 verificationGasLimit = 17000000;
        uint128 callGasLimit = verificationGasLimit;
        uint128 maxPriorityFeePerGas = 256;
        uint128 maxFeePerGas = maxPriorityFeePerGas;
        //generate unsigned data for user operation and return callData
        return PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: hex"", //empty init code
            callData: callData,
            accountGasLimits: bytes32(uint256(verificationGasLimit) << 128 | uint256(callGasLimit)),
            preVerificationGas: verificationGasLimit,
            gasFees: bytes32(uint256(maxPriorityFeePerGas) << 128 | uint256(maxFeePerGas)),
            paymasterAndData: hex"", //empty paymaster and data
            signature: hex"" //empty signature
        });
    }
}
