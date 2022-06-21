// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./ERC721.sol";
import "./Owned.sol";

contract CopyRoomCollection is ERC721, Owned {
    using SafeMath for uint256;

    struct Group {
        uint256 id;
        address groupOwner;
        uint256 bonusOne;
        bool bonusOnMint;
        uint256[] members;
    }

    uint256 public nextMintId = 0;
    uint256 public nextGroupId = 0;
    string public baseURI = "";

    bool public whitelistOnlyMint = true;
    mapping(address => bool) public whitelistedMinters;
    mapping(uint256 => uint256) public transferBonusOne;
    mapping(address => uint256) public bankedOne;

    mapping(uint256 => Group) internal groupByGroupId;
    mapping(uint256 => Group) internal groupByTokenId;

    modifier onlyWhitelistedMinter {
        require(!whitelistOnlyMint || whitelistedMinters[msg.sender], "CopyRoom: Minter not on whitelist");
        _;
    }

    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) Owned() { }

    function setBaseURI(string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }

    function setMintWhitelistForAccounts(address[] memory _accounts, bool val) public onlyOwner {
        for (uint256 i = 0; i < _accounts.length; i++) {
            address acc = _accounts[i];
            whitelistedMinters[acc] = val;
        }
    }

    function withdrawOneFromMyBank(uint256 amount) public {
        return _transferOneFromBank(amount, msg.sender, msg.sender);
    }
    function _transferOneFromBank(uint256 amount, address bank, address destination) internal {
        require(amount <= bankedOne[bank], "CopyRoom: Not enough ONE in bank");
        payable(destination).transfer(amount);
    }
    function depositOneToMyBank() external payable returns (uint256) {
        return depositOneToBank(msg.sender);
    }
    function depositOneToBank(address account) public payable returns (uint256) {
        bankedOne[account].add(msg.value);
        return bankedOne[account];
    }
    function getOneBankValue(address account) public view returns (uint256) {
        return bankedOne[account];
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return baseURI; // TODO
    }

    function isOnWhitelist(address account) public view returns (bool) {
        return whitelistedMinters[account];
    }

    function mintGroup(uint256 numberToMint, address destination, uint256 bonusOneOnFirstTransfer, bool bonusOnMint) public onlyWhitelistedMinter {
        uint256[] memory arr;
        Group memory g = Group(nextGroupId, msg.sender, bonusOneOnFirstTransfer, bonusOnMint, arr);
        groupByGroupId[g.id] = g;
        for (uint256 i = 0; i < numberToMint; i++) {
            mintToGroup(g.id, destination);
        }
        nextGroupId ++;
    }
    function mintToGroup(uint256 groupId, address mintDestination) public {
        Group storage g = groupByGroupId[groupId];
        uint256 nftId = nextMintId;
        ERC721._safeMint(mintDestination, nftId);
        nextMintId++;
        g.members.push(nftId);
    }
    function getGroupMembers(uint256 groupId) public view returns (uint256[] memory) {
        Group storage g = groupByGroupId[groupId];
        return g.members;
    }

    function _sendBonus(uint256 tokenId, address destination) internal {
        _sendBonusOne(tokenId, destination);
    }
    function _sendBonusOne(uint256 tokenId, address destination) internal {
        Group storage g = groupByTokenId[tokenId];
        address bank = g.groupOwner;
        uint256 eligibleBonus = transferBonusOne[tokenId];
        transferBonusOne[tokenId] = 0;
        _transferOneFromBank(eligibleBonus, bank, destination);
    }

}
