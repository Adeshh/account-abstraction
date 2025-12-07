//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {
    IAccount,
    ACCOUNT_VALIDATION_SUCCESS_MAGIC
} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {
    Transaction,
    MemoryTransactionHelper
} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {
    SystemContractsCaller
} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import {
    NONCE_HOLDER_SYSTEM_CONTRACT,
    BOOTLOADER_FORMAL_ADDRESS,
    DEPLOYER_SYSTEM_CONTRACT
} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import {INonceHolder} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Utils} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/Utils.sol";

/**
 * @title ZkMinimalAccount
 * @notice A minimal smart contract wallet for zkSync Era native account abstraction
 * @dev Implements zkSync's IAccount interface. Unlike Ethereum's ERC-4337, zkSync has native AA
 *      where the bootloader (not a real contract) orchestrates transactions. This contract
 *      validates transactions, manages nonces via system contracts, and executes calls.
 */
contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    /// @notice Thrown when account doesn't have enough balance to pay for transaction
    error ZkMinimalAccount__NotEnoughBalance();
    /// @notice Thrown when function is called by someone other than bootloader
    error ZkMinimalAccount__NotFromBootloader();
    /// @notice Thrown when function is called by someone other than bootloader or owner
    error ZkMinimalAccount__NotFromBootloaderOrOwner();
    /// @notice Thrown when transaction execution fails
    error ZkMinimalAccount__ExecutionFailed();
    /// @notice Thrown when signature validation fails
    error ZkMinimalAccount__InvalidSignature();
    /// @notice Thrown when payment to bootloader fails
    error ZkMinimalAccount__FailedToPay();

    /// @notice Ensures only the bootloader can call certain functions
    modifier onlyBootloader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZkMinimalAccount__NotFromBootloader();
        }
        _;
    }

    /// @notice Allows bootloader or owner to call certain functions
    modifier onlyBootloaderOrOwner() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()) {
            revert ZkMinimalAccount__NotFromBootloaderOrOwner();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}

    /// @notice Allows the contract to receive ETH
    receive() external payable {}

    /**
     * @notice Validates a transaction before execution
     * @dev Called by bootloader during transaction validation phase. Increments nonce via system contract,
     *      checks balance, and validates signature. Must return ACCOUNT_VALIDATION_SUCCESS_MAGIC if valid.
     *      First two parameters are unused (txHash and suggestedSignedHash) but required by interface.
     * @param _transaction The transaction to validate
     * @return magic ACCOUNT_VALIDATION_SUCCESS_MAGIC if valid, bytes4(0) if invalid
     */
    function validateTransaction(
        bytes32,
        /*_txHash*/
        bytes32,
        /*_suggestedSignedHash*/
        Transaction memory _transaction
    )
        external
        payable
        onlyBootloader
        returns (bytes4 magic)
    {
        return _validateTransaction(_transaction);
    }

    /**
     * @notice Executes a validated transaction
     * @dev Called by bootloader during execution phase. Can also be called by owner directly.
     *      First two parameters are unused but required by interface.
     * @param _transaction The transaction to execute
     */
    function executeTransaction(
        bytes32,
        /*_txHash*/
        bytes32,
        /*_suggestedSignedHash*/
        Transaction memory _transaction
    )
        external
        payable
        onlyBootloaderOrOwner
    {
        _executeTransaction(_transaction);
    }

    /**
     * @notice Allows owner to execute a transaction directly without going through bootloader
     * @dev Validates the transaction first, then executes it. Useful for testing or direct calls.
     * @param _transaction The transaction to validate and execute
     */
    function executeTransactionFromOutside(Transaction calldata _transaction) external payable {
        bytes4 magic = _validateTransaction(_transaction);
        if (magic != ACCOUNT_VALIDATION_SUCCESS_MAGIC) {
            revert ZkMinimalAccount__InvalidSignature();
        }
        _executeTransaction(_transaction);
    }

    /**
     * @notice Pays the bootloader for transaction gas costs
     * @dev Called by bootloader after validation. Transfers ETH to bootloader address.
     *      First two parameters are unused but required by interface.
     * @param _transaction The transaction being paid for
     */
    function payForTransaction(
        bytes32,
        /*_txHash*/
        bytes32,
        /*_suggestedSignedHash*/
        Transaction memory _transaction
    )
        external
        payable
    {
        bool success = _transaction.payToTheBootloader();
        if (!success) {
            revert ZkMinimalAccount__FailedToPay();
        }
    }

    /**
     * @notice Prepares the account for paymaster usage
     * @dev Currently not implemented - placeholder for paymaster integration.
     *      Parameters are unused but required by interface.
     */
    function prepareForPaymaster(
        bytes32,
        /*_txHash*/
        bytes32,
        /*_possibleSignedHash*/
        Transaction memory _transaction
    )
        external
        payable {}

    /**
     * @notice Internal function to validate a transaction
     * @dev Increments nonce via NONCE_HOLDER_SYSTEM_CONTRACT, checks balance, and validates signature.
     *      Note: zkSync doesn't use EIP-191 for transaction hashes - we recover directly from the hash.
     * @param _transaction The transaction to validate
     * @return magic ACCOUNT_VALIDATION_SUCCESS_MAGIC if valid, bytes4(0) if invalid
     */
    function _validateTransaction(Transaction memory _transaction) internal returns (bytes4 magic) {
        // Increment nonce if it matches expected value
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
        );

        // Check if we have enough balance to cover gas and value
        uint256 totalRequiredBalance = MemoryTransactionHelper.totalRequiredBalance(_transaction);
        if (totalRequiredBalance > address(this).balance) {
            revert ZkMinimalAccount__NotEnoughBalance();
        }

        // Validate signature - zkSync uses raw hash, not EIP-191
        bytes32 txHash = _transaction.encodeHash();
        address signer = ECDSA.recover(txHash, _transaction.signature);
        bool isValidSigner = signer == owner();
        if (isValidSigner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }
        return magic;
    }

    /**
     * @notice Executes a transaction by making a call to the target address
     * @dev Handles both regular calls and system contract calls (like contract deployment).
     *      Uses assembly for regular calls to save gas.
     * @param _transaction The transaction to execute
     */
    function _executeTransaction(Transaction memory _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        // Special handling for contract deployment via DEPLOYER_SYSTEM_CONTRACT
        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
        } else {
            // Regular call using assembly for gas efficiency
            bool success;
            assembly {
                success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }
            if (!success) {
                revert ZkMinimalAccount__ExecutionFailed();
            }
        }
    }
}
