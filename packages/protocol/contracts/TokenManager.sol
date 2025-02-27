// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {SecurityModule} from "./SecurityModule.sol";
import {ITokenManager} from "./interfaces/ITokenManager.sol";
import {IERC20Extended} from "./interfaces/IERC20Extended.sol";
import {ISubjectErc20} from "./interfaces/ISubjectErc20.sol";

contract TokenManager is ITokenManager, SecurityModule {
    using EnumerableSet for EnumerableSet.AddressSet;

    using SafeERC20 for IERC20Extended;

    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 public constant CREATE_ROLE = keccak256("CREATE_ROLE");
    bytes32 public constant ALLOW_LIST_ROLE = keccak256("ALLOW_LIST_ROLE");

    /// @dev Address of subject implementation.
    address public subjectImplementation;

    /// @dev list of address which must be either to or from of a valid subject token transfer.
    /// This is to ensure transfer should always involve moxie protocol contracts.
    EnumerableSet.AddressSet private transferAllowList;

    /// @dev Mapping of subject & its Token
    mapping(address subject => address token) public tokens;

    /**
     * @notice Initialize the contract.
     * @param _admin Admin of contract which gets admin role.
     * @param _subjectImplementation Implementation of subject ERC20 contract.
     */
    function initialize(
        address _admin,
        address _subjectImplementation
    ) public initializer {
        if (_subjectImplementation == address(0))
            revert TokenManager_InvalidSubjectImplementation();
        if (_admin == address(0)) revert TokenManager_InvalidOwner();

        __AccessControl_init();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        subjectImplementation = _subjectImplementation;
    }

    /**
     * @notice Creates token for subject, mints initial supply & transfer it to creator.
     * @param _subject Address of subject for which token is getting deployed.
     * @param _name Name of token getting deployed.
     * @param _symbol Symbol of token getting deployed
     * @param _initialSupply Initial supply of token getting deployed.
     * @param _moxiePassVerifier Address of moxie pass verifier contract.
     */
    function create(
        address _subject,
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        address _moxiePassVerifier
    ) external whenNotPaused onlyRole(CREATE_ROLE) returns (address token_) {
        if (_subject == address(0)) revert TokenManager_InvalidSubject();
        if (tokens[_subject] != address(0)) revert TokenManager_SubjectExists();

        token_ = Clones.cloneDeterministic(
            subjectImplementation,
            keccak256(abi.encodePacked(_subject))
        );
        tokens[_subject] = token_;
        emit TokenDeployed(_subject, token_, _initialSupply);

        //Initialize & mint initial supply.
        ISubjectErc20(token_).initialize(
            address(this),
            _name,
            _symbol,
            _initialSupply,
            _moxiePassVerifier
        );

        // Transfer initial supply to creator.
        IERC20Extended(token_).safeTransfer(msg.sender, _initialSupply);
    }

    /**
     * @notice Mint for subject's token.
     * @param _subject Subject for which shares needs to be minted.
     * @param _beneficiary Beneficiary of minted token.
     * @param _amount Amount of tokens to mint.
     */
    function mint(
        address _subject,
        address _beneficiary,
        uint256 _amount
    ) public whenNotPaused onlyRole(MINT_ROLE) returns (bool) {
        address token = tokens[_subject];
        if (token == address(0)) revert TokenManager_TokenNotFound();

        if (_amount == 0) revert TokenManager_InvalidAmount();

        IERC20Extended(token).mint(_beneficiary, _amount);
        return true;
    }

    /**
     * @notice Adds an address that can be allowed as one of the transfer address(from/to)
     * @param _wallet Wallet address that is to be added to allow list.
     */
    function addToTransferAllowList(
        address _wallet
    ) external onlyRole(ALLOW_LIST_ROLE) {
        if (_wallet == address(0)) revert TokenManager_InvalidAddress();

        if (!transferAllowList.add(_wallet))
            revert TokenManager_AddressAlreadyAdded();

        emit TransferAllowListWalletAllowed(_wallet, true);
    }

    /**
     * @notice Removes an address from allow list.
     * @param _wallet Wallet address that is to be added to allow list.
     */
    function removeFromTransferAllowList(
        address _wallet
    ) external onlyRole(ALLOW_LIST_ROLE) {
        if (_wallet == address(0)) revert TokenManager_InvalidAddress();

        if (!transferAllowList.remove(_wallet))
            revert TokenManager_AddressAlreadyRemoved();
        emit TransferAllowListWalletAllowed(_wallet, false);
    }

    /**
     * @notice Check if wallet is whitelisted in allow list.
     * For a valid Subject Token transfer either from or to address
     * must be part of allow list.
     * @param _wallet Address of wallet.
     */
    function isWalletAllowedForTransfer(address _wallet) external view returns (bool) {
        //always allow if allow list is not set.
        if (transferAllowList.length() == 0) return true;

        return transferAllowList.contains(_wallet);
    }
}
