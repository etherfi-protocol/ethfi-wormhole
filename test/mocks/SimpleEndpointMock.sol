// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {MessagingParams, MessagingFee, MessagingReceipt, Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {ILayerZeroReceiver} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroReceiver.sol";

/// @title SimpleEndpointMock
/// @notice A minimal mock of the LayerZero EndpointV2 for testing
contract SimpleEndpointMock {
    uint32 public immutable eid;
    mapping(address => address) public delegates;

    constructor(uint32 _eid) {
        eid = _eid;
    }

    function setDelegate(address _delegate) external {
        delegates[msg.sender] = _delegate;
    }

    function quote(
        MessagingParams calldata,
        address
    ) external pure returns (MessagingFee memory) {
        return MessagingFee(0, 0);
    }

    function send(
        MessagingParams calldata,
        address
    ) external payable returns (MessagingReceipt memory) {
        return MessagingReceipt(bytes32(0), 0, MessagingFee(0, 0));
    }

    /// @notice Simulates receiving a LayerZero message by calling lzReceive on the target
    /// @param _receiver The OApp contract to receive the message
    /// @param _origin The origin information (srcEid, sender, nonce)
    /// @param _guid The message GUID
    /// @param _message The encoded message payload
    function lzReceive(
        address _receiver,
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message
    ) external payable {
        ILayerZeroReceiver(_receiver).lzReceive(_origin, _guid, _message, msg.sender, "");
    }
}
