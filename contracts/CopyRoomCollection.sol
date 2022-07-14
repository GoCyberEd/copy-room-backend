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
        bool isBonusActive;
        uint256 bonusOne;
        bool bonusOnMint;
        uint256[] members;
    }

    uint256 constant MAX_GROUPS_PER_ADDRESS = 1000;

    uint256 public nextMintId = 0;
    uint256 public nextGroupId = 1; // Allow fixed length arrays "0" to be null
    string public baseURI = "";

    bool public whitelistOnlyMint = true;
    mapping(address => bool) public whitelistedMinters;
    mapping(uint256 => uint256) public transferBonusOne;
    mapping(address => uint256) public bankedOne;

    mapping(uint256 => Group) internal groupByGroupId;
    mapping(uint256 => Group) internal groupByTokenId;
    mapping(address => Group[]) internal groupByOwnerId;

    event Deposit(address bank, uint256 value);
    event Withdrawal(address bank, uint256 value);
    event CreateGroup(uint256 groupId, address owner);
    event ModifyGroupBonus(uint256 groupId, bool isBonusActive, uint256 bonusONE);
    event EnableWhitelist(bool isEnabled);
    event ModifyWhitelist(address[] accounts, bool isEnabled);

    modifier onlyWhitelistedMinter {
        require(!whitelistOnlyMint || whitelistedMinters[msg.sender], "CopyRoom: Minter not on whitelist");
        _;
    }

    modifier onlyGroupOwner(Group storage g) {
        require(msg.sender == g.groupOwner, "CopyRoom: Insufficient permissions for group");
        _;
    }

    modifier onlyNFTOwnerOrApproved(uint256 id) {
        address nftOwner = _ownerOf[id];
        require(_ownerOf[id] == msg.sender || isApprovedForAll[nftOwner][msg.sender] || msg.sender == getApproved[id], "CopyRoom: Must be owner or approved account to burn");
        _;
    }

    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) Owned() { }

    receive() external payable {
        depositOneToMyBank();
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public override {
        _sendBonus(id, payable(to));

        ERC721.transferFrom(from, to, id);
    }

    function burn(uint256 id) public onlyNFTOwnerOrApproved(id) {
        ERC721._burn(id);
    }

    function setBaseURI(string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }

    function setWhitelistOnlyMint(bool b) public onlyOwner {
        whitelistOnlyMint = b;
        emit EnableWhitelist(b);
    }
    function setMintWhitelistForAccounts(address[] memory _accounts, bool b) public onlyOwner {
        for (uint256 i = 0; i < _accounts.length; i++) {
            address acc = _accounts[i];
            whitelistedMinters[acc] = b;
        }
        emit ModifyWhitelist(_accounts, b);
    }
    function getMintWhitelistStatusForAccount(address account) public view returns ( bool ) {
        return whitelistedMinters[account];
    }

    function withdrawOneFromMyBank(uint256 amount) public {
        emit Withdrawal(msg.sender, amount);
        return _transferOneFromBank(amount, msg.sender, payable(msg.sender));
    }
    function _transferOneFromBank(uint256 amount, address bank, address payable destination) internal {
        require(amount <= bankedOne[bank], "CopyRoom: Not enough ONE in bank");
        destination.transfer(amount);
    }
    function depositOneToMyBank() public payable returns (uint256) {
        return depositOneToBank(msg.sender);
    }
    function depositOneToBank(address account) public payable returns (uint256) {
        bankedOne[account] = bankedOne[account].add(msg.value);
        emit Deposit(account, msg.value);
        return bankedOne[account];
    }
    function getOneBankValue(address account) public view returns (uint256) {
        return bankedOne[account];
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return baseURI; // TODO
    }

    function mintGroup(
        uint256 numberToMint,
        address destination,
        uint256 bonusOneOnFirstTransfer,
        bool bonusOnMint) public payable onlyWhitelistedMinter returns (uint256){

        if (msg.value > 0) {
            depositOneToMyBank();
        }

        uint256[] memory arr;
        Group memory g = Group(nextGroupId, msg.sender, true, bonusOneOnFirstTransfer, bonusOnMint, arr);
        groupByGroupId[g.id] = g;
        groupByOwnerId[msg.sender].push(g);
        emit CreateGroup(g.id, msg.sender);
        mintToGroup(numberToMint, g.id, destination);
        nextGroupId ++;
        return g.id;
    }
    function mintToGroup(
        uint256 numberToMint,
        uint256 groupId,
        address mintDestination) public payable onlyWhitelistedMinter onlyGroupOwner(groupByGroupId[groupId]) {

        if (msg.value > 0) {
            depositOneToMyBank();
        }

        for (uint256 i = 0; i < numberToMint; i++) {
            _mintSingleToGroup(groupId, mintDestination);
        }
    }
    function _mintSingleToGroup(uint256 groupId, address mintDestination) internal {
        Group storage g = groupByGroupId[groupId];
        uint256 nftId = nextMintId;
        ERC721._safeMint(mintDestination, nftId);
        groupByTokenId[nftId] = g;
        transferBonusOne[nftId] = g.bonusOne;
        g.members.push(nftId);
        if (g.bonusOnMint) {
            _sendBonus(nftId, payable(mintDestination));
        }
        nextMintId++;
    }
    function setActiveBonusForGroup(uint256 groupId, bool b) public onlyGroupOwner(groupByGroupId[groupId]) {
        Group storage g = groupByGroupId[groupId];
        g.isBonusActive = b;
        emit ModifyGroupBonus(g.id, g.isBonusActive, g.bonusOne);
    }
    function isGroupBonusActive(uint256 groupId) public view returns (bool) {
        return groupByGroupId[groupId].isBonusActive;
    }
    function getGroupMembers(uint256 groupId) public view returns (uint256[] memory) {
        Group storage g = groupByGroupId[groupId];
        return g.members;
    }
    function getOwnedGroupIdsByOwner(address groupOwner) public view returns (uint256[1000] memory){
        uint256 len = groupByOwnerId[groupOwner].length;
        uint256[MAX_GROUPS_PER_ADDRESS] memory ids;
        for (uint256 i = 0; i < len || i >= MAX_GROUPS_PER_ADDRESS; i++) {
            Group memory g = groupByOwnerId[groupOwner][i];
            ids[i] = g.id;
        }
        return ids;
    }
    function getLastGroupIdByOwner(address groupOwner) public view returns (uint256) {
        uint256 len = groupByOwnerId[groupOwner].length;
        return groupByOwnerId[groupOwner][len - 1].id;
    }

    function _sendBonus(uint256 tokenId, address payable destination) internal {
        _sendBonusOne(tokenId, destination);
    }
    function _sendBonusOne(uint256 tokenId, address payable destination) internal {
        Group storage g = groupByTokenId[tokenId];
        if (!g.isBonusActive) return;

        address bank = g.groupOwner;
        uint256 eligibleBonus = transferBonusOne[tokenId];
        if (eligibleBonus == 0) return;

        transferBonusOne[tokenId] = 0;
        _transferOneFromBank(eligibleBonus, bank, destination);
    }
}
