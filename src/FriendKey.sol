// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {ERC1155SupplyUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract FriendKey is
    Initializable,
    ERC1155Upgradeable,
    OwnableUpgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155SupplyUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20Metadata;

    uint256 public BPS_SCALE; // Basis Point Scale (100% = 10000 BPS)

    address public devFeeDestination;
    uint256 public devFeePercent;
    uint256 public creatorFeePercent;
    address public tradingPoolFeeDestination;
    uint256 public tradingPoolFeePercent;

    IERC20Metadata public bondingToken; // Changed to IERC20Metadata
    uint256 public bondingTokenPriceUnit; // Added bonding token price unit (e.g., 10**decimals)

    // Mapping from creator's address to their associated token ID
    mapping(address => uint256) public creatorByTokenId;
    mapping(address => uint256) public userAccumulatedFees;

    event Trade(
        address indexed trader,
        uint256 indexed id,
        address indexed creator,
        bool isBuy,
        uint256 shareAmount,
        uint256 tokenAmount
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        address _devFeeDestination,
        uint256 _devFeePercent,
        uint256 _creatorFeePercent,
        address _tradingPoolFeeDestination,
        uint256 _tradingPoolFeePercent,
        address _bondingTokenAddress
    ) public initializer {
        __ERC1155_init("");
        __Ownable_init(initialOwner);
        __ERC1155Burnable_init();
        __ERC1155Supply_init();
        __UUPSUpgradeable_init();

        BPS_SCALE = 10000;

        require(_devFeePercent + _creatorFeePercent + _tradingPoolFeePercent <= BPS_SCALE, "Total fee percent too high");
        require(_bondingTokenAddress != address(0), "Bonding token address cannot be zero");

        devFeeDestination = _devFeeDestination;
        devFeePercent = _devFeePercent;
        creatorFeePercent = _creatorFeePercent;
        tradingPoolFeeDestination = _tradingPoolFeeDestination;
        tradingPoolFeePercent = _tradingPoolFeePercent;
        bondingToken = IERC20Metadata(_bondingTokenAddress);

        uint8 decimals = bondingToken.decimals();
        require(decimals > 0, "Bonding token decimals must be greater than zero");
        bondingTokenPriceUnit = 10 ** decimals;
    }

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    // --- Fee and Creator Management (Owner only) ---

    function setDevFeeDestination(address _feeDestination) public onlyOwner {
        devFeeDestination = _feeDestination;
    }

    function setDevFeePercent(uint256 _feePercent) public onlyOwner {
        require(_feePercent <= BPS_SCALE, "Dev fee percent too high");
        require(_feePercent + creatorFeePercent + tradingPoolFeePercent <= BPS_SCALE, "Total fee percent too high");
        devFeePercent = _feePercent;
    }

    function setCreatorFeePercent(uint256 _feePercent) public onlyOwner {
        require(_feePercent <= BPS_SCALE, "Creator fee percent too high");
        require(devFeePercent + _feePercent + tradingPoolFeePercent <= BPS_SCALE, "Total fee percent too high");
        creatorFeePercent = _feePercent;
    }

    function setTradingPoolFeeDestination(address _feeDestination) public onlyOwner {
        tradingPoolFeeDestination = _feeDestination;
    }

    function setTradingPoolFeePercent(uint256 _feePercent) public onlyOwner {
        require(_feePercent <= BPS_SCALE, "Trading pool fee percent too high");
        require(devFeePercent + creatorFeePercent + _feePercent <= BPS_SCALE, "Total fee percent too high");
        tradingPoolFeePercent = _feePercent;
    }

    function registerCreator(address creatorAccount, uint256 id) public onlyOwner {
        require(creatorAccount != address(0), "Creator account cannot be zero address");
        creatorByTokenId[creatorAccount] = id;
    }

    // --- Pricing Logic ---

    function getPrice(uint256 supply, uint256 amount) public view returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : (supply - 1) * (supply) * (2 * (supply - 1) + 1) / 6;
        uint256 sum2 = supply == 0 && amount == 1
            ? 0
            : (supply - 1 + amount) * (supply + amount) * (2 * (supply - 1 + amount) + 1) / 6;
        uint256 summation = sum2 - sum1;
        return summation * bondingTokenPriceUnit / 16000;
    }

    function getBuyPrice(uint256 id, uint256 amount) public view returns (uint256) {
        return getPrice(totalSupply(id), amount);
    }

    function getSellPrice(uint256 id, uint256 amount) public view returns (uint256) {
        require(totalSupply(id) >= amount, "Amount exceeds supply");
        return getPrice(totalSupply(id) - amount, amount);
    }

    function getBuyPriceAfterFee(uint256 id, uint256 amount) public view returns (uint256) {
        uint256 price = getBuyPrice(id, amount);
        uint256 devFee = price * devFeePercent / BPS_SCALE;
        uint256 creatorFee = price * creatorFeePercent / BPS_SCALE;
        uint256 tradingPoolFee = price * tradingPoolFeePercent / BPS_SCALE;
        return price + devFee + creatorFee + tradingPoolFee;
    }

    function getSellPriceAfterFee(uint256 id, uint256 amount) public view returns (uint256) {
        uint256 price = getSellPrice(id, amount);
        uint256 devFee = price * devFeePercent / BPS_SCALE;
        uint256 creatorFee = price * creatorFeePercent / BPS_SCALE;
        uint256 tradingPoolFee = price * tradingPoolFeePercent / BPS_SCALE;
        uint256 totalFees = devFee + creatorFee + tradingPoolFee;
        return price > totalFees ? price - totalFees : 0;
    }

    // --- Buy and Sell Shares ---

    function buyShares(address creatorAddress, uint256 amount) public {
        require(amount > 0, "Amount must be greater than zero");
        uint256 tokenId = creatorByTokenId[creatorAddress];
        require(tokenId != 0, "Creator not registered or no token ID associated");

        uint256 currentSupply = totalSupply(tokenId);
        if (currentSupply == 0) {
            require(msg.sender == creatorAddress, "Only creator can buy the first share");
        }

        uint256 price = getPrice(currentSupply, amount);
        uint256 devFee = price * devFeePercent / BPS_SCALE;
        uint256 creatorFee = price * creatorFeePercent / BPS_SCALE;
        uint256 tradingPoolFee = price * tradingPoolFeePercent / BPS_SCALE;
        uint256 totalCost = price + devFee + creatorFee + tradingPoolFee;

        if (totalCost > 0) {
            bondingToken.transferFrom(msg.sender, address(this), totalCost);
        }

        _mint(msg.sender, tokenId, amount, "");

        if (devFee > 0 && devFeeDestination != address(0)) {
            bondingToken.transfer(devFeeDestination, devFee);
        }
        if (creatorFee > 0) {
            userAccumulatedFees[creatorAddress] += creatorFee;
        }
        if (tradingPoolFee > 0 && tradingPoolFeeDestination != address(0)) {
            bondingToken.transfer(tradingPoolFeeDestination, tradingPoolFee);
        }

        emit Trade(msg.sender, tokenId, creatorAddress, true, amount, price);
    }

    function sellShares(address creatorAddress, uint256 amount) public {
        require(amount > 0, "Amount must be greater than zero");
        uint256 tokenId = creatorByTokenId[creatorAddress];
        require(tokenId != 0, "Creator not registered or no token ID associated");
        require(balanceOf(msg.sender, tokenId) >= amount, "Insufficient shares");

        uint256 currentSupply = totalSupply(tokenId);
        require(currentSupply > amount, "Cannot sell shares if it makes supply zero or less through this method");

        uint256 price = getPrice(currentSupply - amount, amount);
        uint256 devFee = price * devFeePercent / BPS_SCALE;
        uint256 creatorFee = price * creatorFeePercent / BPS_SCALE;
        uint256 tradingPoolFee = price * tradingPoolFeePercent / BPS_SCALE;

        uint256 totalFees = devFee + creatorFee + tradingPoolFee;
        uint256 proceeds = price > totalFees ? price - totalFees : 0;

        _burn(msg.sender, tokenId, amount);

        emit Trade(msg.sender, tokenId, creatorAddress, false, amount, price);

        if (proceeds > 0) {
            bondingToken.transfer(msg.sender, proceeds);
        }
        if (devFee > 0 && devFeeDestination != address(0)) {
            bondingToken.transfer(devFeeDestination, devFee);
        }
        if (creatorFee > 0) {
            userAccumulatedFees[creatorAddress] += creatorFee;
        }
        if (tradingPoolFee > 0 && tradingPoolFeeDestination != address(0)) {
            bondingToken.transfer(tradingPoolFeeDestination, tradingPoolFee);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        super._update(from, to, ids, values);
    }
}
