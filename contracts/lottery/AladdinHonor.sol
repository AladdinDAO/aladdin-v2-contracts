// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/ILottery.sol";

contract AladdinHonor is ERC721, Ownable, ReentrancyGuard {
  event SetPendingMint(address indexed account, uint256 level);
  event SetLevelURI(uint256 level, string url);
  event SetLottery(address lottery);

  struct PendingMint {
    // current minted level.
    uint128 mintedLevel;
    // pending mint max level.
    uint128 maxLevel;
  }

  /// The address of lottery contract.
  address public lottery;
  /// total token minted.
  uint256 public tokenCounter;
  /// mapping from user address to mint info.
  mapping(address => PendingMint) public addressToPendingMint;
  /// mapping from tokenId to level.
  mapping(uint256 => uint256) public tokenToLevel;
  /// mapping from level to token URI.
  mapping(uint256 => string) public levelToURI;

  constructor() ERC721("AladdinHonor", "ALDHONOR") Ownable() {}

  /********************************** View Functions **********************************/

  /// @notice Returns the token URI
  /// @param tokenId The tokenId, from 1 to tokenCounter (max MAX_SUPPLY)
  /// @dev Token owners can specify which tokenURI address to use
  ///      on a per-token basis using setTokenURIAddress
  /// @return result A base64 encoded JSON string
  function tokenURI(uint256 tokenId) public view override returns (string memory result) {
    uint256 level = tokenToLevel[tokenId];
    result = levelToURI[level];
  }

  /********************************** Mutated Functions **********************************/

  function mint() external nonReentrant {
    PendingMint memory pending = addressToPendingMint[msg.sender];
    address _lottery = lottery;

    uint256 _tokenCounter = tokenCounter;
    for (uint256 level = pending.mintedLevel + 1; level <= pending.maxLevel; level++) {
      tokenToLevel[_tokenCounter] = level;
      _safeMint(msg.sender, _tokenCounter);
      if (_lottery != address(0)) {
        ILottery(_lottery).registerToken(_tokenCounter);
      }
      _tokenCounter += 1;
    }
    tokenCounter = _tokenCounter;
    pending.mintedLevel = pending.maxLevel;
    addressToPendingMint[msg.sender] = pending;
  }

  /********************************** Restricted Functions **********************************/

  function setLevelURI(uint256 level, string memory uri) external onlyOwner {
    require(1 <= level && level <= 9, "AladdinHonor: invalid level");
    levelToURI[level] = uri;

    emit SetLevelURI(level, uri);
  }

  function setLottery(address _lottery) external onlyOwner {
    lottery = _lottery;

    emit SetLottery(_lottery);
  }

  function setPendingMints(address[] memory users, uint256[] memory levels) external onlyOwner {
    require(users.length == levels.length, "AladdinHonor: length mismatch");
    for (uint256 i = 0; i < users.length; i++) {
      _setPendingMint(users[i], levels[i]);
    }
  }

  function setPendingMint(address user, uint256 level) external onlyOwner {
    _setPendingMint(user, level);
  }

  /********************************** Internal Functions **********************************/

  function _setPendingMint(address user, uint256 level) internal {
    require(1 <= level && level <= 9, "AladdinHonor: invalid level");

    PendingMint memory pending = addressToPendingMint[user];
    require(pending.maxLevel < level, "AladdinHonor: level already set");
    pending.maxLevel = uint128(level);

    addressToPendingMint[user] = pending;
    emit SetPendingMint(user, level);
  }
}
