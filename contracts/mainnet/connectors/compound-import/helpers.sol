pragma solidity ^0.7.6;

import { DSMath } from "../../common/math.sol";
import { Basic } from "../../common/basic.sol";
import { TokenInterface, AccountInterface } from "../../common/interfaces.sol";
import { ComptrollerInterface, CompoundMappingInterface, CETHInterface, CTokenInterface } from "./interface.sol";

abstract contract Helpers is DSMath, Basic {

    /**
     * @dev Compound CEth 
     */
    CETHInterface internal constant cEth = CETHInterface(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);

    /**
     * @dev Compound Comptroller
     */
    ComptrollerInterface internal constant troller = ComptrollerInterface(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    /**
     * @dev Compound Mapping
     */
    CompoundMappingInterface internal constant compMapping = CompoundMappingInterface(0xe7a85d0adDB972A4f0A4e57B698B37f171519e88);

    struct ImportData {
        address[] cTokens; // is the list of all tokens the user has interacted with (supply/borrow) -> used to enter markets
        uint[] borrowAmts;
        uint[] supplyAmts;
        address[] borrowTokens;
        address[] supplyTokens;
        CTokenInterface[] borrowCtokens;
        CTokenInterface[] supplyCtokens;
        address[] supplyCtokensAddr;
        address[] borrowCtokensAddr;
    }

    struct ImportInputData {
        address userAccount;
        string[] supplyIds;
        string[] borrowIds;
    }

    /**
     * @dev enter compound market
     */
    function enterMarket(address cToken) internal {
        address[] memory markets = troller.getAssetsIn(address(this));
        bool isEntered = false;
        for (uint i = 0; i < markets.length; i++) {
            if (markets[i] == cToken) {
                isEntered = true;
            }
        }
        if (!isEntered) {
            address[] memory toEnter = new address[](1);
            toEnter[0] = cToken;
            troller.enterMarkets(toEnter);
        }
    }
}

contract CompoundHelper is Helpers {

    /**
     * @notice fetch the borrow details of the user
     * @dev approve the cToken to spend (borrowed amount of) tokens to allow for repaying later
     * @param _importInputData the struct containing borrowIds of the users borrowed tokens
     * @param data struct used to store the final data on which the CompoundHelper contract functions operate
     * @return ImportData the final value of param data
     */
    function getBorrowAmounts (
        ImportInputData memory _importInputData,
        ImportData memory data
    ) internal returns(ImportData memory) {
        if (_importInputData.borrowIds.length > 0) {
            // initialize arrays for borrow data
            data.borrowTokens = new address[](_importInputData.borrowIds.length);
            data.borrowCtokens = new CTokenInterface[](_importInputData.borrowIds.length);
            data.borrowCtokensAddr = new address[](_importInputData.borrowIds.length);
            data.borrowAmts = new uint[](_importInputData.borrowIds.length);

            // check for repeated tokens
            for (uint i = 0; i < _importInputData.borrowIds.length; i++) {
                bytes32 i_hash = keccak256(abi.encode(_importInputData.borrowIds[i]));
                for (uint j = i + 1; j < _importInputData.borrowIds.length; j++) {
                    bytes32 j_hash = keccak256(abi.encode(_importInputData.borrowIds[j]));
                    require(i_hash != j_hash, "token-repeated");
                }
            }

            // populate the arrays with borrow tokens, cToken addresses and instances, and borrow amounts
            for (uint i = 0; i < _importInputData.borrowIds.length; i++) {
                (address _token, address _cToken) = compMapping.getMapping(_importInputData.borrowIds[i]);

                require(_token != address(0) && _cToken != address(0), "ctoken mapping not found");

                data.cTokens[i] = _cToken;

                data.borrowTokens[i] = _token;
                data.borrowCtokens[i] = CTokenInterface(_cToken);
                data.borrowCtokensAddr[i] = _cToken;
                data.borrowAmts[i] = data.borrowCtokens[i].borrowBalanceCurrent(_importInputData.userAccount);

                // give the resp. cToken address approval to spend tokens
                if (_token != ethAddr && data.borrowAmts[i] > 0) {
                    // will be required when repaying the borrow amount on behalf of the user
                    TokenInterface(_token).approve(_cToken, data.borrowAmts[i]);
                }
            }
        }
        return data;
    }

    /**
     * @notice fetch the supply details of the user
     * @dev only reads data from blockchain hence view
     * @param _importInputData the struct containing supplyIds of the users supplied tokens
     * @param data struct used to store the final data on which the CompoundHelper contract functions operate
     * @return ImportData the final value of param data
     */
    function getSupplyAmounts (
        ImportInputData memory _importInputData,
        ImportData memory data
    ) internal view returns(ImportData memory) {
        // initialize arrays for supply data
        data.supplyTokens = new address[](_importInputData.supplyIds.length);
        data.supplyCtokens = new CTokenInterface[](_importInputData.supplyIds.length);
        data.supplyCtokensAddr = new address[](_importInputData.supplyIds.length);
        data.supplyAmts = new uint[](_importInputData.supplyIds.length);

        // check for repeated tokens
        for (uint i = 0; i < _importInputData.supplyIds.length; i++) {
            bytes32 i_hash = keccak256(abi.encode(_importInputData.supplyIds[i]));
            for (uint j = i + 1; j < _importInputData.supplyIds.length; j++) {
                bytes32 j_hash = keccak256(abi.encode(_importInputData.supplyIds[j]));
                require(i_hash != j_hash, "token-repeated");
            }
        }

        // populate arrays with supply data (supply tokens address, cToken addresses, cToken instances and supply amounts)
        for (uint i = 0; i < _importInputData.supplyIds.length; i++) {
            (address _token, address _cToken) = compMapping.getMapping(_importInputData.supplyIds[i]);
            
            require(_token != address(0) && _cToken != address(0), "ctoken mapping not found");

            uint _supplyIndex = add(i, _importInputData.borrowIds.length);
            data.cTokens[_supplyIndex] = _cToken;

            data.supplyTokens[i] = _token;
            data.supplyCtokens[i] = CTokenInterface(_cToken);
            data.supplyCtokensAddr[i] = (_cToken);
            data.supplyAmts[i] = data.supplyCtokens[i].balanceOf(_importInputData.userAccount);
        }
        return data;
    }

    /**
     * @notice repays the debt taken by user on Compound on its behalf to free its collateral for transfer
     * @dev uses the cEth contract for ETH repays, otherwise the general cToken interface
     * @param _userAccount the user address for which debt is to be repayed
     * @param _cTokenContracts array containing all interfaces to the cToken contracts in which the user has debt positions
     * @param _borrowAmts array containing the amount borrowed for each token
     */
    function _repayUserDebt(
        address _userAccount,
        CTokenInterface[] memory _cTokenContracts,
        uint[] memory _borrowAmts
    ) internal {
        for(uint i = 0; i < _cTokenContracts.length; i++){
            if(_borrowAmts[i] > 0){
                if(address(_cTokenContracts[i]) == address(cEth)){
                    cEth.repayBorrowBehalf{value: _borrowAmts[i]}(_userAccount);
                }
                else{
                    require(_cTokenContracts[i].repayBorrowBehalf(_userAccount, _borrowAmts[i]) == 0, "repayOnBehalf-failed");
                }
            }
        }
    }

    /**
     * @notice used to transfer user's supply position on Compound to DSA
     * @dev uses the transferFrom token in cToken contracts to transfer positions, requires approval from user first
     * @param _userAccount address of the user account whose position is to be transferred
     * @param _cTokenContracts array containing all interfaces to the cToken contracts in which the user has supply positions
     * @param _amts array containing the amount supplied for each token
     */
    function _transferTokensToDsa(
        address _userAccount, 
        CTokenInterface[] memory _cTokenContracts,
        uint[] memory _amts
    ) internal {
        for(uint i = 0; i < _cTokenContracts.length; i++) {
            if(_amts[i] > 0) {
                require(_cTokenContracts[i].transferFrom(_userAccount, address(this), _amts[i]), "ctoken-transfer-failed-allowance?");
            }
        }
    }

    /**
     * @notice borrows the user's debt positions from Compound via DSA, so that its debt positions get imported to DSA
     * @dev actually borrow some extra amount than the original position to cover the flash loan fee
     * @param _cTokenContracts array containing all interfaces to the cToken contracts in which the user has debt positions
     * @param _amts array containing the amounts the user had borrowed originally from Compound plus the flash loan fee
     * @param _flashLoanFee flash loan fee (in percentage and scaled up to 10**2)
     */
    function _borrowDebtPosition(
        CTokenInterface[] memory _cTokenContracts, 
        uint256[] memory _amts,
        uint256 _flashLoanFee
    ) internal {
        for (uint i = 0; i < _cTokenContracts.length; i++) {
            if (_amts[i] > 0) {
                require(_cTokenContracts[i].borrow(add(_amts[i], mul(_amts[i], mul(_flashLoanFee, 10**14)))) == 0, "borrow-failed-collateral?");
            }
        }        
    }
}