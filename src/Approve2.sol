// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

/// @title Approve2
/// @author transmissions11 <t11s@paradigm.xyz>
/// @notice Backwards compatible, low-overhead,
/// next generation token approval/meta-tx system.
contract Approve2 {
    using SafeTransferLib for ERC20;

    uint256 private constant _BITMASK_ADDRESS = (1 << 160) - 1;

    /*//////////////////////////////////////////////////////////////
                          EIP-712 STORAGE/LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps addresses to their current nonces. Used to prevent replay
    /// attacks and allow invalidating in-flight permits via invalidateNonce.
    mapping(address => uint256) public nonces;

    /// @notice Invalidate a specific number of nonces. Can be used
    /// to invalidate in-flight permits before they are executed.
    /// @param noncesToInvalidate The number of nonces to invalidate.
    function invalidateNonces(uint256 noncesToInvalidate) public {
        // Limit how quickly users can invalidate their nonces to
        // ensure no one accidentally invalidates all their nonces.
        require(noncesToInvalidate <= type(uint16).max);

        nonces[msg.sender] += noncesToInvalidate;
    }

    /// @notice The EIP-712 "domain separator" the contract
    /// will use when validating signatures for a given token.
    /// @param token The token to get the domain separator for.
    /// @dev For calls to permitAll, the address of
    /// the Approve2 contract will be used the token.
    function DOMAIN_SEPARATOR(address token) public view returns (bytes32 result) {
        assembly {
            let m0x40 := mload(0x40)
            let m0x80 := mload(0x80)
            // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
            mstore(0x00, 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f)
            // keccak256("Approve2")
            mstore(0x20, 0x2b5743ce396fc0fb7c46d02cbef4ec38cf7e859e3570e69baaf898ed84405e0d)
            // keccak256("1")
            mstore(0x40, 0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6)
            mstore(0x60, chainid())
            mstore(0x80, and(token, _BITMASK_ADDRESS))
            result := keccak256(0x00, 0xa0)
            mstore(0x80, m0x80)
            mstore(0x60, 0)
            mstore(0x40, m0x40)
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ALLOWANCE STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps user addresses to "operator" addresses and whether they are
    /// are approved to spend any amount of any token the user has approved.
    mapping(address => mapping(address => bool)) public isOperator;

    /// @notice Maps users to tokens to spender addresses and how much they
    /// are approved to spend the amount of that token the user has approved.
    mapping(address => mapping(ERC20 => mapping(address => uint256))) public allowance;

    /// @notice Set whether an spender address is approved
    /// to transfer any one of the sender's approved tokens.
    /// @param operator The operator address to approve or unapprove.
    /// @param approved Whether the operator is approved.
    function setOperator(address operator, bool approved) external {
        isOperator[msg.sender][operator] = approved;
    }

    /// @notice Approve a spender to transfer a specific
    /// amount of a specific ERC20 token from the sender.
    /// @param token The token to approve.
    /// @param spender The spender address to approve.
    /// @param amount The amount of the token to approve.
    function approve(
        ERC20 token,
        address spender,
        uint256 amount
    ) external {
        allowance[msg.sender][token][spender] = amount;
    }

    /*//////////////////////////////////////////////////////////////
                              PERMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Permit a user to spend a given amount of another user's
    /// approved amount of the given token via the owner's EIP-712 signature.
    /// @param token The token to permit spending.
    /// @param owner The user to permit spending from.
    /// @param spender The user to permit spending to.
    /// @param amount The amount to permit spending.
    /// @param deadline  The timestamp after which the signature is no longer valid.
    /// @param v Must produce valid secp256k1 signature from the owner along with r and s.
    /// @param r Must produce valid secp256k1 signature from the owner along with v and s.
    /// @param s Must produce valid secp256k1 signature from the owner along with r and v.
    /// @dev May fail if the owner's nonce was invalidated in-flight by invalidateNonce.
    function permit(
        ERC20 token,
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        assembly {
            // Cache the reserved memory slots.
            let m0x40 := mload(0x40)
            let m0x80 := mload(0x80)
            let m0xa0 := mload(0xa0)

            // Ensure the signature's deadline has not already passed.
            if lt(deadline, timestamp()) {
                mstore(0x00, hex"08c379a0") // Function selector of the error method.
                mstore(0x04, 0x20) // Offset of the error string.
                mstore(0x24, 23) // Length of the error string.
                mstore(0x44, "PERMIT_DEADLINE_EXPIRED") // The error string.
                revert(0x00, 0x64) // Revert with (offset, size).
            }

            // Mask the input address to clear the upper 96 bits.
            owner := and(owner, _BITMASK_ADDRESS)
            spender := and(spender, _BITMASK_ADDRESS)
            token := and(token, _BITMASK_ADDRESS)

            // Load and increment the nonce.
            mstore(0x00, owner)
            mstore(0x20, nonces.slot)
            let nonceSlot := keccak256(0x00, 0x40)
            let nonce := sload(nonceSlot)
            sstore(nonceSlot, add(nonce, 1))

            // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
            mstore(0x00, 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9)
            mstore(0x20, owner)
            mstore(0x40, spender)
            mstore(0x60, amount)
            mstore(0x80, nonce)
            mstore(0xa0, deadline)
            
            let h := keccak256(0x00, 0xc0)

            // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
            mstore(0x00, 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f)
            // keccak256("Approve2")
            mstore(0x20, 0x2b5743ce396fc0fb7c46d02cbef4ec38cf7e859e3570e69baaf898ed84405e0d)
            // keccak256("1")
            mstore(0x40, 0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6)
            mstore(0x60, chainid())
            mstore(0x80, token)

            mstore(0x20, keccak256(0x00, 0xa0))
            mstore(0x00, 0x1901)
            mstore(0x40, h)

            mstore(0x00, keccak256(0x1e, 0x42))
            mstore(0x20, and(v, 0xff))
            mstore(0x40, r)
            mstore(0x60, s)

            pop(
                staticcall(
                    gas(), // Amount of gas left for the transaction.
                    0x01, // Address of `ecrecover`.
                    0x00, // Start of input.
                    0x80, // Size of input.
                    0x40, // Start of output.
                    0x20 // Size of output.
                )
            )
            // Restore the zero slot.
            mstore(0x60, 0)
            // `returndatasize()` will be `0x20` upon success, and `0x00` otherwise.
            let recoveredAddress := mload(sub(0x60, returndatasize()))
            // Ensure the signature is valid and the signer is the owner.
            if or(iszero(recoveredAddress), iszero(eq(recoveredAddress, owner))) {
                mstore(0x00, hex"08c379a0") // Function selector of the error method.
                mstore(0x04, 0x20) // Offset of the error string.
                mstore(0x24, 14) // Length of the error string.
                mstore(0x44, "INVALID_SIGNER") // The error string.
                revert(0x00, 0x64) // Revert with (offset, size).
            }

            // Set the allowance of the spender to the given amount.
            mstore(0x20, allowance.slot)
            mstore(0x00, recoveredAddress)
            mstore(0x20, keccak256(0x00, 0x40))
            mstore(0x00, token)
            mstore(0x20, keccak256(0x00, 0x40))
            mstore(0x00, spender)
            sstore(keccak256(0x00, 0x40), amount)

            // Restore the reserved memory slots.
            mstore(0xa0, m0xa0)
            mstore(0x80, m0x80)
            mstore(0x40, m0x40)
        }
    }

    /// @notice Permit a user to spend any amount of any of another
    /// user's approved tokens via the owner's EIP-712 signature.
    /// @param owner The user to permit spending from.
    /// @param spender The user to permit spending to.
    /// @param deadline The timestamp after which the signature is no longer valid.
    /// @param v Must produce valid secp256k1 signature from the owner along with r and s.
    /// @param r Must produce valid secp256k1 signature from the owner along with v and s.
    /// @param s Must produce valid secp256k1 signature from the owner along with r and v.
    /// @dev May fail if the owner's nonce was invalidated in-flight by invalidateNonce.
    function permitAll(
        address owner,
        address spender,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        assembly {
            // Cache the reserved memory slots.
            let m0x40 := mload(0x40)
            let m0x80 := mload(0x80)
            let m0xa0 := mload(0xa0)

            // Ensure the signature's deadline has not already passed.
            if lt(deadline, timestamp()) {
                mstore(0x00, hex"08c379a0") // Function selector of the error method.
                mstore(0x04, 0x20) // Offset of the error string.
                mstore(0x24, 23) // Length of the error string.
                mstore(0x44, "PERMIT_DEADLINE_EXPIRED") // The error string.
                revert(0x00, 0x64) // Revert with (offset, size).
            }

            // Mask the input address to clear the upper 96 bits.
            owner := and(owner, _BITMASK_ADDRESS)
            spender := and(spender, _BITMASK_ADDRESS)

            // Load and increment the nonce.
            mstore(0x00, owner)
            mstore(0x20, nonces.slot)
            let nonceSlot := keccak256(0x00, 0x40)
            let nonce := sload(nonceSlot)
            sstore(nonceSlot, add(nonce, 1))

            // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
            mstore(0x00, 0x8b2a9c07938b6d62909dc00103ea4e71485caf5019e7fa95b0a87e13825663b0)
            mstore(0x20, owner)
            mstore(0x40, spender)
            mstore(0x60, nonce)
            mstore(0x80, deadline)

            let h := keccak256(0x00, 0xa0)

            // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
            mstore(0x00, 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f)
            // keccak256("Approve2")
            mstore(0x20, 0x2b5743ce396fc0fb7c46d02cbef4ec38cf7e859e3570e69baaf898ed84405e0d)
            // keccak256("1")
            mstore(0x40, 0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6)
            mstore(0x60, chainid())
            mstore(0x80, address())

            mstore(0x20, keccak256(0x00, 0xa0))
            mstore(0x00, 0x1901)
            mstore(0x40, h)

            mstore(0x00, keccak256(0x1e, 0x42))
            mstore(0x20, and(v, 0xff))
            mstore(0x40, r)
            mstore(0x60, s)

            pop(
                staticcall(
                    gas(), // Amount of gas left for the transaction.
                    0x01, // Address of `ecrecover`.
                    0x00, // Start of input.
                    0x80, // Size of input.
                    0x40, // Start of output.
                    0x20 // Size of output.
                )
            )
            // Restore the zero slot.
            mstore(0x60, 0)
            // `returndatasize()` will be `0x20` upon success, and `0x00` otherwise.
            let recoveredAddress := mload(sub(0x60, returndatasize()))
            // Ensure the signature is valid and the signer is the owner.
            if or(iszero(recoveredAddress), iszero(eq(recoveredAddress, owner))) {
                mstore(0x00, hex"08c379a0") // Function selector of the error method.
                mstore(0x04, 0x20) // Offset of the error string.
                mstore(0x24, 14) // Length of the error string.
                mstore(0x44, "INVALID_SIGNER") // The error string.
                revert(0x00, 0x64) // Revert with (offset, size).
            }

            // Set isOperator for the spender to true.
            mstore(0x20, isOperator.slot)
            mstore(0x00, owner)
            mstore(0x20, keccak256(0x00, 0x40))
            mstore(0x00, spender)
            sstore(keccak256(0x00, 0x40), 1)

            // Restore the reserved memory slots.
            mstore(0xa0, m0xa0)
            mstore(0x80, m0x80)
            mstore(0x40, m0x40)
        }
    }

    /*//////////////////////////////////////////////////////////////
                             TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfer approved tokens from one address to another.
    /// @param token The token to transfer.
    /// @param from The address to transfer from.
    /// @param to The address to transfer to.
    /// @param amount The amount of tokens to transfer.
    /// @dev Requires either the from address to have approved at least the desired amount
    /// of tokens or msg.sender to be approved to manage all of the from addresses's tokens.
    function transferFrom(
        ERC20 token,
        address from,
        address to,
        uint256 amount
    ) external {
        unchecked {
            uint256 allowed = allowance[from][token][msg.sender]; // Saves gas for limited approvals.

            // If the from address has set an unlimited approval, we'll go straight to the transfer.
            if (allowed != type(uint256).max) {
                if (allowed >= amount) {
                    // If msg.sender has enough approved to them, decrement their allowance.
                    allowance[from][token][msg.sender] = allowed - amount;
                } else {
                    // Otherwise, check if msg.sender is an operator for the
                    // from address, otherwise we'll revert and block the transfer.
                    require(isOperator[from][msg.sender], "APPROVE_ALL_REQUIRED");
                }
            }

            // Transfer the tokens from the from address to the recipient.
            token.safeTransferFrom(from, to, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             LOCKDOWN LOGIC
    //////////////////////////////////////////////////////////////*/

    // TODO: Bench if a struct for token-spender pairs is cheaper.

    /// @notice Enables performing a "lockdown" of the sender's Approve2 identity
    /// by batch revoking approvals, unapproving operators, and invalidating nonces.
    /// @param tokens An array of tokens who's corresponding spenders should have their
    /// approvals revoked. Each index should correspond to an index in the spenders array.
    /// @param spenders An array of addresses to revoke approvals from.
    /// Each index should correspond to an index in the tokens array.
    /// @param operators An array of addresses to revoke operator approval from.
    function lockdown(
        ERC20[] calldata tokens,
        address[] calldata spenders,
        address[] calldata operators,
        uint256 noncesToInvalidate
    ) external {
        unchecked {
            // Will revert if trying to invalidate
            // more than type(uint16).max nonces.
            invalidateNonces(noncesToInvalidate);

            // Each index should correspond to an index in the other array.
            require(tokens.length == spenders.length, "LENGTH_MISMATCH");

            assembly {
                // Revoke allowances for each pair of spenders and tokens.
                for {
                    let end := add(spenders.offset, shl(5, spenders.length))
                    let i := spenders.offset
                    let j := tokens.offset
                    mstore(0x20, allowance.slot)
                    mstore(0x00, caller())
                    let h := keccak256(0x00, 0x40)
                } iszero(eq(i, end)) {
                    j := add(j, 0x20)
                    i := add(i, 0x20)
                } {
                    mstore(0x20, h)
                    calldatacopy(0x00, j, 0x20)
                    mstore(0x20, keccak256(0x00, 0x40))
                    calldatacopy(0x00, i, 0x20)
                    sstore(keccak256(0x00, 0x40), 0)
                }

                // Revoke allowances for each pair of spenders and tokens.
                for {
                    let end := add(operators.offset, shl(5, operators.length))
                    let i := operators.offset 
                    mstore(0x20, isOperator.slot)
                    mstore(0x00, caller())
                    mstore(0x20, keccak256(0x00, 0x40))
                } iszero(eq(i, end)) {
                    i := add(i, 0x20)
                } {
                    calldatacopy(0x00, i, 0x20)
                    sstore(keccak256(0x00, 0x40), 0)   
                }
            }
        }
    }
}
