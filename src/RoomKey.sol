// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract RoomKey is
    Initializable,
    ERC721Upgradeable,
    ERC721BurnableUpgradeable,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    uint256 public constant PRICE_DIVISOR = 16000;

    address public creatorFeeRecipient;
    address public devFeeRecipient;
    address public tradingPoolFeeRecipient;

    uint16 public constant DEV_FEE_BPS = 400; // 4%
    uint16 public constant CREATOR_FEE_BPS = 400; // 4%
    uint16 public constant TRADING_POOL_FEE_BPS = 400; // 4%
    uint16 public constant SELLER_SHARE_BPS = 8800; // 88%
    uint16 public constant TOTAL_BPS = 10000;

    mapping(uint256 => uint256) public keyLockedUntil;

    event KeyBought(address indexed buyer, uint256 indexed tokenId, uint256 price);
    event KeySold(address indexed seller, uint256 indexed tokenId, uint256 returnAmount);
    event KeyLocked(uint256 indexed tokenId, uint256 lockedUntil);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        address initialContractOwner,
        address _creatorFeeRecipient,
        address _devFeeRecipient,
        address _tradingPoolFeeRecipient
    ) public initializer {
        __ERC721_init(name, symbol);
        __ERC721Enumerable_init();
        __ERC721Burnable_init();
        __Ownable_init(initialContractOwner);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        creatorFeeRecipient = _creatorFeeRecipient;
        devFeeRecipient = _devFeeRecipient;
        tradingPoolFeeRecipient = _tradingPoolFeeRecipient;

        require(_creatorFeeRecipient != address(0), "RoomKey: Creator fee recipient is zero address");
        require(_devFeeRecipient != address(0), "RoomKey: Dev fee recipient is zero address");
        require(_tradingPoolFeeRecipient != address(0), "RoomKey: Trading pool fee recipient is zero address");
        require(
            DEV_FEE_BPS + CREATOR_FEE_BPS + TRADING_POOL_FEE_BPS + SELLER_SHARE_BPS == TOTAL_BPS,
            "RoomKey: Fee BPS mismatch"
        );
    }

    function _sumOfSquares(uint256 n) internal pure returns (uint256) {
        if (n == 0) return 0;
        return n * (n + 1) * (2 * n + 1) / 6;
    }

    function getPriceInternal(uint256 supply, uint256 amount) internal pure returns (uint256) {
        if (amount == 0) return 0;
        uint256 s_supply_plus_amount_minus_1 = _sumOfSquares(supply + amount - 1);
        uint256 s_supply_minus_1 = _sumOfSquares(supply == 0 ? 0 : supply - 1);
        uint256 summation = s_supply_plus_amount_minus_1 - s_supply_minus_1;
        return (summation * 1 ether) / PRICE_DIVISOR;
    }

    function getBuyPrice() public view returns (uint256) {
        uint256 currentSupply = totalSupply();
        return getPriceInternal(currentSupply, 1);
    }

    function getSellPrice() public view returns (uint256) {
        uint256 currentSupply = totalSupply();
        if (currentSupply == 0) {
            return 0;
        }
        return getPriceInternal(currentSupply - 1, 1);
    }

    function buyKey() public payable nonReentrant {
        uint256 basePrice = getBuyPrice();

        uint256 devFee = (basePrice * DEV_FEE_BPS) / TOTAL_BPS;
        uint256 creatorFee = (basePrice * CREATOR_FEE_BPS) / TOTAL_BPS;
        uint256 tradingPoolFee = (basePrice * TRADING_POOL_FEE_BPS) / TOTAL_BPS;
        uint256 totalPaymentRequired = basePrice + devFee + creatorFee + tradingPoolFee;

        require(msg.value >= totalPaymentRequired, "RoomKey: Insufficient payment for key");

        uint256 tokenIdToMint = totalSupply();
        _safeMint(msg.sender, tokenIdToMint);

        if (devFee > 0) {
            payable(devFeeRecipient).transfer(devFee);
        }
        if (creatorFee > 0) {
            payable(creatorFeeRecipient).transfer(creatorFee);
        }
        if (tradingPoolFee > 0) {
            payable(tradingPoolFeeRecipient).transfer(tradingPoolFee);
        }

        if (msg.value > totalPaymentRequired) {
            payable(msg.sender).transfer(msg.value - totalPaymentRequired);
        }
        emit KeyBought(msg.sender, tokenIdToMint, basePrice);
    }

    function sellKey(uint256 tokenId) public nonReentrant {
        address owner = ownerOf(tokenId);
        require(
            owner == msg.sender || isApprovedForAll(owner, msg.sender) || getApproved(tokenId) == msg.sender,
            "RoomKey: Caller is not owner nor approved"
        );
        require(!isKeyLocked(tokenId), "RoomKey: Token is locked, cannot sell");

        uint256 currentSupply = totalSupply();
        require(currentSupply > 0, "RoomKey: No keys to sell");

        uint256 valueBase = getSellPrice();

        _burn(tokenId);

        uint256 devFee = (valueBase * DEV_FEE_BPS) / TOTAL_BPS;
        uint256 creatorFee = (valueBase * CREATOR_FEE_BPS) / TOTAL_BPS;
        uint256 tradingPoolFee = (valueBase * TRADING_POOL_FEE_BPS) / TOTAL_BPS;
        uint256 sellerAmount = valueBase - devFee - creatorFee - tradingPoolFee;

        require(address(this).balance >= valueBase, "RoomKey: Insufficient contract balance for payout");

        if (devFee > 0) {
            payable(devFeeRecipient).transfer(devFee);
        }
        if (creatorFee > 0) {
            payable(creatorFeeRecipient).transfer(creatorFee);
        }
        if (tradingPoolFee > 0) {
            payable(tradingPoolFeeRecipient).transfer(tradingPoolFee);
        }
        if (sellerAmount > 0) {
            payable(msg.sender).transfer(sellerAmount);
        }

        emit KeySold(msg.sender, tokenId, sellerAmount);
    }

    function lockKey(uint256 tokenId, uint256 durationSeconds) public {
        require(ownerOf(tokenId) == msg.sender, "RoomKey: Not token owner");
        keyLockedUntil[tokenId] = block.timestamp + durationSeconds;
        emit KeyLocked(tokenId, keyLockedUntil[tokenId]);
    }

    function isKeyLocked(uint256 tokenId) public view returns (bool) {
        return keyLockedUntil[tokenId] > block.timestamp;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
