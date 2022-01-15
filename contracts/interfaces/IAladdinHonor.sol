// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IAladdinHonor {
  function tokenToLevel(uint256 tokenId) external view returns (uint256);

  function ownerOf(uint256 tokenId) external view returns (address owner);
}
