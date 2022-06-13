//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;

import { InstaConnectors } from "../../common/interfaces.sol";

contract SwapHelpers {
	/**
	 * @dev Instadapp Connectors Registry
	 */
	InstaConnectors internal constant instaConnectors =
		InstaConnectors(0x127d8cD0E2b2E0366D522DeA53A787bfE9002C14);

	struct InputData {
		address buyAddr;
		address sellAddr;
		uint256 sellAmt;
		uint256[] unitAmts;
		bytes[] callDatas;
		uint256 setId;
	}

	/**
	 *@dev Swap using the dex aggregators.
	 *@param _connectors name of the connectors in preference order.
	 *@param _inputData data for the swap cast.
	 */
	function _swap(string[] memory _connectors, InputData memory _inputData)
		internal
		returns (
			bool success,
			bytes memory returnData,
			string memory _connector
		)
	{
		uint256 _length = _connectors.length;
		require(_length > 0, "zero-length-not-allowed");
		require(
			_inputData.unitAmts.length == _length,
			"unitAmts-length-invalid"
		);
		require(
			_inputData.callDatas.length == _length,
			"callDatas-length-invalid"
		);

		// require _connectors[i] == "1INCH-A" || "ZEROX-A" || "PARASWAP-A" || similar connectors

		for (uint256 i = 0; i < _length; i++) {
			bytes4 swapData = (keccak256(bytes(_connectors[i])) ==
				keccak256(bytes("1INCH-A")))
				? bytes4(
					keccak256(
						"sell(address,address,uint256,uint256,bytes,uint256)"
					)
				)
				: bytes4(
					keccak256(
						"swap(address,address,uint256,uint256,bytes,uint256)"
					)
				);

			bytes memory _data = abi.encodeWithSelector(
				swapData,
				_inputData.buyAddr,
				_inputData.sellAddr,
				_inputData.sellAmt,
				_inputData.unitAmts[i],
				_inputData.callDatas[i],
				_inputData.setId
			);

			(success, returnData) = instaConnectors
				.connectors(_connectors[i])
				.delegatecall(_data);
			if (success) {
				_connector = _connectors[i];
				break;
			}
		}
	}

	function decodeEvents(string memory _connector, bytes memory returnData)
		internal
		view
		returns (uint256 _buyAmt, uint256 _sellAmt)
	{
		(, bytes memory _eventParam) = abi.decode(returnData, (string, bytes));
		if (keccak256(bytes(_connector)) == keccak256(bytes("PARASWAP-A"))) {
			(, , _buyAmt, _sellAmt, ) = abi.decode(
				_eventParam,
				(address, address, uint256, uint256, uint256)
			);
		} else {
			(, , _buyAmt, _sellAmt, , ) = abi.decode(
				_eventParam,
				(address, address, uint256, uint256, uint256, uint256)
			);
		}
	}
}
