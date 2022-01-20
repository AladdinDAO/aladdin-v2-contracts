// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "../interfaces/ILottery.sol";
import "../interfaces/IAladdinHonor.sol";

contract Lottery is OwnableUpgradeable, ILottery {
  using SafeMath for uint256;
  using SafeERC20Upgradeable for IERC20Upgradeable;

  // a large 64-bits prime number
  uint256 private constant prime = 18446744073709551557;

  struct PrizeInfo {
    // The number of ald each prize.
    uint128 amount;
    // The number of prize to open in the level.
    uint128 count;
  }

  struct WinInfo {
    // The number of round.
    uint64 round;
    // The prize level.
    uint64 prizeLevel;
    // The amount of ald.
    uint128 amount;
  }

  event RegisterToken(uint256 tokenId, uint256 round);
  event UpdateWeights(uint256[] weights);
  event UpdateParticipantThreshold(uint256 threshold);
  event UpdateTotalPrizeThreshold(uint256 threshold);
  event UpdatePrizeInfo(uint256[] amounts, uint256[] counts);
  event UpdateKeeper(address keeper);
  event Claim(address user, uint256 amount);
  event OpenPrize(uint256 round, uint256 rewardAmount);
  event WinPrize(uint256 round, uint256 prizeLevel, uint256 amount);

  /// the address of rewardToken token.
  address public rewardToken;

  /// the address of NFT token.
  address public token;

  /// The round id of lottery.
  uint256 public round;

  /// the maximum number of round each token can participant.
  uint256 public participantThreshold;

  /// the amount of rewardToken in each lottery.
  uint256 public totalPrizeThreshold;

  /// the number of total unclaimed rewards.
  uint256 public totalUnclaimedRewards;

  /// the weights of each level.
  uint256[9] public weights;

  /// the prize info of each prize.
  PrizeInfo[4] public prizeInfo;

  /// mapping from tokenId to registered round.
  mapping(uint256 => uint256) public registeredRound;

  /// whether the token is registered;
  mapping(uint256 => bool) public isRegistered;

  /// mapping from level to the list of registered tokens.
  mapping(uint256 => uint256[]) public registeredTokens;

  /// mapping from user address to unclaimed rewards.
  mapping(address => uint256) public unclaimedRewards;

  /// the address of keeper, who can trigger open prize.
  address public keeper;

  // mapping from user address to win info in each round.
  mapping(address => WinInfo[]) private accountToWinInfo;

  function initialize(address _rewardToken, address _token) external initializer {
    require(_rewardToken != address(0), "Lottery: zero address");
    require(_token != address(0), "Lottery: zero address");

    OwnableUpgradeable.__Ownable_init();

    rewardToken = _rewardToken;
    token = _token;
  }

  /********************************** View Functions **********************************/

  function currentPoolSize() public view returns (uint256) {
    return IERC20Upgradeable(rewardToken).balanceOf(address(this)).sub(totalUnclaimedRewards);
  }

  function getAccountToWinInfo(address _user) external view returns (WinInfo[] memory) {
    return accountToWinInfo[_user];
  }

  function getTotalWeights() external view returns (uint256) {
    (, uint256[] memory _levelCount, uint256[] memory _levelWeight, ) = _loadLotteryInfo(round + 1);
    uint256 _totalWeight = 0;
    for (uint256 i = 0; i < 9; i++) {
      _totalWeight = _totalWeight.add(_levelCount[i].mul(_levelWeight[i]));
    }
    return _totalWeight;
  }

  /********************************** Mutated Functions **********************************/

  function remainParticipantTimes(uint256 _tokenId) public view returns (uint256) {
    if (!isRegistered[_tokenId]) return 0;
    uint256 _usedRound = round - registeredRound[_tokenId];
    if (_usedRound < participantThreshold) return participantThreshold - _usedRound;
    else return 0;
  }

  /// @dev register nft token, called by NFT contract
  /// @param tokenId The id of corresponding NFT.
  function registerToken(uint256 tokenId) external override {
    require(msg.sender == token, "Lottery: not allowed");
    require(!isRegistered[tokenId], "Lottery: registered");

    _register(msg.sender, tokenId);
  }

  /// @dev Open lottery prize if the pending pool size reach the threshold.
  function openPrize() external {
    require(keeper == address(0) || msg.sender == keeper, "Lottery: sender not allowed");
    require(currentPoolSize() >= totalPrizeThreshold, "Lottery: not enough ald");
    uint256 _round = round + 1;
    round = _round;

    (
      uint256[] memory _offset,
      uint256[] memory _levelCount,
      uint256[] memory _levelWeight,
      uint256 _sampleCount
    ) = _loadLotteryInfo(_round);

    (uint256[] memory _levels, uint256[] memory _indices) = _sample(_levelCount, _levelWeight, _sampleCount);

    emit OpenPrize(_round, totalPrizeThreshold);

    _distributePrize(_round, _levels, _offset, _indices);
  }

  /// @dev claim pending prize reward
  function claim() external {
    uint256 _uncalimed = unclaimedRewards[msg.sender];
    unclaimedRewards[msg.sender] = 0;
    totalUnclaimedRewards = totalUnclaimedRewards.sub(_uncalimed);

    IERC20Upgradeable(rewardToken).safeTransfer(msg.sender, _uncalimed);

    emit Claim(msg.sender, _uncalimed);
  }

  /********************************** Restricted Functions **********************************/

  function updateWeights(uint256[] memory _weights) external onlyOwner {
    require(_weights.length == 9, "Lottery: length mismatch");
    for (uint256 i = 0; i < 9; i++) {
      if (i > 0) {
        require(_weights[i] > _weights[i - 1], "Lottery: weight should increase");
      }
      weights[i] = _weights[i];

      emit UpdateWeights(_weights);
    }
  }

  function updateParticipeThreshold(uint256 _threshold) external onlyOwner {
    participantThreshold = _threshold;

    emit UpdateParticipantThreshold(_threshold);
  }

  function updateTotalPrizeThreshold(uint256 _threshold) external onlyOwner {
    totalPrizeThreshold = _threshold;

    emit UpdateTotalPrizeThreshold(_threshold);
  }

  function updatePrizeInfo(uint256[] memory amounts, uint256[] memory counts) external onlyOwner {
    require(amounts.length == 4, "Lottery: length mismatch");
    require(counts.length == 4, "Lottery: length mismatch");

    uint256 sum;
    for (uint256 i = 0; i < 4; i++) {
      prizeInfo[i] = PrizeInfo({ amount: uint128(amounts[i]), count: uint128(counts[i]) });
      sum = sum.add(amounts[i].mul(counts[i]));
    }
    require(sum == totalPrizeThreshold, "Lottery: sum mismatch");

    emit UpdatePrizeInfo(amounts, counts);
  }

  function updateKeeper(address _keeper) external onlyOwner {
    keeper = _keeper;

    emit UpdateKeeper(_keeper);
  }

  /********************************** Internal Functions **********************************/

  function _register(address _token, uint256 _tokenId) internal {
    uint256 _level = IAladdinHonor(_token).tokenToLevel(_tokenId).sub(1);
    registeredTokens[_level].push(_tokenId);
    isRegistered[_tokenId] = true;
    registeredRound[_tokenId] = round;

    emit RegisterToken(_tokenId, round);
  }

  function _loadLotteryInfo(uint256 _round)
    internal
    view
    returns (
      uint256[] memory _offset,
      uint256[] memory _levelCount,
      uint256[] memory _levelWeights,
      uint256 _sampleCount
    )
  {
    _offset = new uint256[](9);
    _levelCount = new uint256[](9);
    _levelWeights = new uint256[](9);

    uint256 _totalTokenCount = 0;
    uint256 _theshold = participantThreshold;
    for (uint256 level = 0; level < 9; ++level) {
      _levelWeights[level] = weights[level];
      uint256[] storage _tokens = registeredTokens[level];
      uint256 length = _tokens.length;
      if (length == 0) continue;
      uint256 left = 0;
      uint256 right = length;
      uint256 mid;
      // since the registered round of tokens in `_tokens` is in non-decreasing order,
      // we can use binary search to find the first token which can participate lottery.
      while (left < right) {
        mid = (left + right - 1) >> 1;
        if (mid == length || _round <= _theshold + registeredRound[_tokens[mid]]) {
          right = mid;
        } else {
          left = mid + 1;
        }
      }
      _levelCount[level] = length - right;
      _totalTokenCount += _levelCount[level];
      _offset[level] = right;
    }

    for (uint256 i = 0; i < 4; i++) {
      _sampleCount += prizeInfo[i].count;
    }
    require(_totalTokenCount >= _sampleCount, "Lottery: token count not enough");
  }

  /// @dev Weighted random sampling using Algorithm A-Chao, see: https://en.wikipedia.org/wiki/Reservoir_sampling#Weighted_random_sampling
  function _sample(
    uint256[] memory _levelCount,
    uint256[] memory _levelWeight,
    uint256 _sampleCount
  ) internal view returns (uint256[] memory _levels, uint256[] memory _indices) {
    _levels = new uint256[](_sampleCount);
    _indices = new uint256[](_sampleCount);

    // use (round,last block hash, current block difficulty) as seed for xoshiro256 algorithm
    uint256 _state = uint256(keccak256(abi.encodePacked(round, blockhash(block.number - 1), block.difficulty)));
    uint256 _totalWeight;
    for (uint256 level = 0; level < 9; level++) {
      uint256 _weight = _levelWeight[level];
      for (uint256 i = 0; i < _levelCount[level]; i++) {
        _totalWeight += _weight;
        if (_sampleCount > 0) {
          _sampleCount -= 1;
          _levels[_sampleCount] = level;
          _indices[_sampleCount] = i;
        } else {
          uint256 prob = _weight.mul(prime).div(_totalWeight);
          uint256 rand;
          (rand, _state) = _xoshiro256ss(_state);
          if (rand % prime <= prob) {
            (rand, _state) = _xoshiro256ss(_state);
            rand %= _levels.length;
            _levels[rand] = level;
            _indices[rand] = i;
          }
        }
      }
    }

    // random shuffle using Fisher–Yates shuffle
    for (uint256 i = 0; i + 1 < _levels.length; i++) {
      uint256 j;
      (j, _state) = _xoshiro256ss(_state);
      j = i + (j % (_levels.length - i));
      if (i != j) {
        uint256 t = _levels[i];
        _levels[i] = _levels[j];
        _levels[j] = t;
        t = _indices[i];
        _indices[i] = _indices[j];
        _indices[j] = t;
      }
    }
  }

  function _distributePrize(
    uint256 _round,
    uint256[] memory _levels,
    uint256[] memory _offset,
    uint256[] memory _indices
  ) internal {
    uint256 i;
    address _token = token;
    uint256 _tokenId;
    address _owner;
    for (uint256 prizeLevel = 0; prizeLevel < 4; prizeLevel++) {
      PrizeInfo memory _info = prizeInfo[prizeLevel];
      for (uint256 j = 0; j < _info.count; j++) {
        _tokenId = registeredTokens[_levels[i]][_indices[i] + _offset[i]];
        _owner = IERC721(_token).ownerOf(_tokenId);
        accountToWinInfo[_owner].push(
          WinInfo({ round: uint64(_round), prizeLevel: uint64(prizeLevel), amount: _info.amount })
        );
        unclaimedRewards[_owner] += _info.amount;
        i += 1;
        emit WinPrize(_round, prizeLevel, _info.amount);
      }
    }
    totalUnclaimedRewards += totalPrizeThreshold;
  }

  /// @dev xoshiro256 algorithm to generate pseudorandom 64-bit integer, see: https://en.wikipedia.org/wiki/Xorshift
  function _xoshiro256ss(uint256 _state) internal pure returns (uint64, uint256) {
    uint64 s0 = uint64(_state);
    uint64 s1 = uint64(_state >> 64);
    uint64 s2 = uint64(_state >> 128);
    uint64 s3 = uint64(_state >> 192);
    uint64 result = _rol64(s1 * uint64(5), 7) * uint64(9);
    uint64 t = s1 << 17;

    s2 ^= s0;
    s3 ^= s1;
    s1 ^= s2;
    s0 ^= s3;

    s2 ^= t;
    s3 = _rol64(s3, 45);

    _state = uint256(s0) + (uint256(s1) << 64) + (uint256(s2) << 128) + (uint256(s3) << 192);
    return (result, _state);
  }

  function _rol64(uint64 x, uint64 k) internal pure returns (uint64) {
    return (x << k) | (x >> (64 - k));
  }
}
