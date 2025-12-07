// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IAccount} from "lib/account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "lib/account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

/**
 * @title MinimalAccount
 * @notice A minimal ERC-4337 compliant smart contract wallet
 * @dev Implements the IAccount interface for account abstraction on Ethereum.
 *      This contract allows the owner to execute transactions either directly or through the EntryPoint.
 *      When called via EntryPoint, it validates UserOperations and handles gas payment.
 */
contract MinimalAccount is IAccount, Ownable {
    /// @notice Thrown when a function is called by someone other than the EntryPoint
    error MinimalAccount__NotEntryPoint();
    /// @notice Thrown when a function is called by someone other than EntryPoint or owner
    error MinimalAccount__NotEntryPointOrOwner();
    /// @notice Thrown when an external call fails
    /// @param returnData The revert data from the failed call
    error MinimalAccount__CallFailed(bytes returnData);

    /// @dev The EntryPoint contract address - immutable for gas savings
    IEntryPoint private immutable I_ENTRY_POINT;

    /// @notice Ensures only the EntryPoint can call certain functions
    modifier onlyEntryPoint() {
        if (msg.sender != address(I_ENTRY_POINT)) {
            revert MinimalAccount__NotEntryPoint();
        }
        _;
    }

    /// @notice Allows EntryPoint or owner to call certain functions
    modifier onlyEntryPointOrOwner() {
        if (msg.sender != address(I_ENTRY_POINT) && msg.sender != owner()) {
            revert MinimalAccount__NotEntryPointOrOwner();
        }
        _;
    }

    /**
     * @notice Deploys a new MinimalAccount
     * @param entryPoint The EntryPoint contract address to use for UserOperations
     */
    constructor(address entryPoint) Ownable(msg.sender) {
        I_ENTRY_POINT = IEntryPoint(entryPoint);
    }

    /// @notice Allows the contract to receive ETH
    receive() external payable {}

    /**
     * @notice Executes a call to an external contract
     * @dev Can be called by owner directly or by EntryPoint during UserOperation execution
     * @param dest The address to call
     * @param value The amount of ETH to send with the call
     * @param functionData The calldata to send
     */
    function execute(address dest, uint256 value, bytes calldata functionData) external onlyEntryPointOrOwner {
        (bool success, bytes memory returnData) = dest.call{value: value}(functionData);
        if (!success) {
            revert MinimalAccount__CallFailed(returnData);
        }
    }

    /**
     * @notice Validates a UserOperation as required by ERC-4337
     * @dev Called by EntryPoint during handleOps. Validates signature and pays for gas.
     *      EntryPoint manages nonce validation separately, so we don't check it here.
     * @param userOp The UserOperation to validate
     * @param userOpHash The hash of the UserOperation (computed by EntryPoint)
     * @param missingAccountFunds The amount of ETH needed to cover gas costs
     * @return validationData Returns SIG_VALIDATION_SUCCESS (0) if valid, SIG_VALIDATION_FAILED (1) otherwise
     */
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        onlyEntryPoint
        returns (uint256 validationData)
    {
        validationData = _validateSignature(userOp, userOpHash);
        _payPrefund(missingAccountFunds);
    }

    /**
     * @notice Validates the signature of a UserOperation
     * @dev Uses EIP-191 message signing. Recovers the signer and checks if it matches the owner.
     * @param userOp The UserOperation containing the signature
     * @param userOpHash The hash of the UserOperation
     * @return validationData SIG_VALIDATION_SUCCESS if owner signed, SIG_VALIDATION_FAILED otherwise
     */
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256 validationData)
    {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address signer = ECDSA.recover(ethSignedMessageHash, userOp.signature);
        if (signer != owner()) {
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }

    /**
     * @notice Pays the EntryPoint for gas costs
     * @dev Transfers ETH to EntryPoint (msg.sender) to cover gas. Uses max gas to ensure it goes through.
     *      This is called during validateUserOp, so msg.sender is always the EntryPoint contract.
     * @param missingAccountFunds The amount of ETH to transfer to EntryPoint
     */
    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds > 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds, gas: type(uint256).max}("");
            (success);
        }
    }

    /**
     * @notice Returns the EntryPoint address this account uses
     * @return The EntryPoint contract address
     */
    function getEntryPoint() public view returns (address) {
        return address(I_ENTRY_POINT);
    }
}
