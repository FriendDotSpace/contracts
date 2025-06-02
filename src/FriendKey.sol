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
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract FriendKey is
    Initializable,
    ERC1155Upgradeable,
    OwnableUpgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155SupplyUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20Metadata;
    using Strings for uint256;

    uint256 private _nextTokenId;

    uint256 public BPS_SCALE; // Basis Point Scale (100% = 10000 BPS)

    address public devFeeDestination;
    uint256 public devFeePercent;
    uint256 public creatorFeePercent;
    address public tradingPoolFeeDestination;
    uint256 public tradingPoolFeePercent;

    IERC20Metadata public bondingToken;
    uint256 public bondingTokenPriceUnit; // Added bonding token price unit (e.g., 10**decimals)

    // Mapping from tokenId to creator's address
    mapping(uint256 => address) public creatorByTokenId;
    mapping(address => uint256) public bondingCurveReserves;

    // Mapping to track when a user first held a token (tokenId => userAddress => timestamp)
    mapping(uint256 => mapping(address => uint256)) public keyHoldingSince;

    event Trade(
        uint256 indexed tokenId,
        address indexed trader,
        address indexed subject,
        bool isBuy,
        uint256 shareAmount,
        uint256 tokenAmount,
        uint256 supply
    );

    event KeyCreated(uint256 indexed tokenId, address indexed creator, string tokenURI, uint256 initialSupply);

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

    function registerCreator() public returns (uint256) {
        address creator = msg.sender;
        uint256 id = ++_nextTokenId;
        creatorByTokenId[id] = creator;
        buyShares(id, 1); // Mint 1 share to the creator
        string memory tokenUri = uri(id);
        emit KeyCreated(id, creator, tokenUri, 1);
        return id;
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        address creator = creatorByTokenId[tokenId];
        require(creator != address(0), "Creator not registered");
        string memory tokenURI = tokenId.toString();
        string memory base = super.uri(tokenId);

        // If token URI is set, concatenate base URI and tokenURI (via string.concat).
        return bytes(base).length > 0 ? string.concat(base, tokenURI) : base;
    }

    // --- Pricing Logic ---

    function getPrice(uint256 supply, uint256 amount) public view returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : ((supply - 1) * (supply) * (2 * (supply - 1) + 1)) / 6;
        uint256 sum2 = supply == 0 && amount == 1
            ? 0
            : ((supply - 1 + amount) * (supply + amount) * (2 * (supply - 1 + amount) + 1)) / 6;
        uint256 summation = sum2 - sum1;
        return (summation * bondingTokenPriceUnit) / 16000;
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
        uint256 devFee = (price * devFeePercent) / BPS_SCALE;
        uint256 creatorFee = (price * creatorFeePercent) / BPS_SCALE;
        uint256 tradingPoolFee = (price * tradingPoolFeePercent) / BPS_SCALE;
        return price + devFee + creatorFee + tradingPoolFee;
    }

    function getSellPriceAfterFee(uint256 id, uint256 amount) public view returns (uint256) {
        uint256 price = getSellPrice(id, amount);
        uint256 devFee = (price * devFeePercent) / BPS_SCALE;
        uint256 creatorFee = (price * creatorFeePercent) / BPS_SCALE;
        uint256 tradingPoolFee = (price * tradingPoolFeePercent) / BPS_SCALE;
        uint256 totalFees = devFee + creatorFee + tradingPoolFee;
        return price > totalFees ? price - totalFees : 0;
    }

    // --- Buy and Sell Shares ---

    function buyShares(uint256 tokenId, uint256 amount) public {
        require(amount > 0, "Amount must be greater than zero");
        address creatorAddress = creatorByTokenId[tokenId];
        require(creatorAddress != address(0), "Creator not registered or no token ID associated");

        uint256 currentSupply = totalSupply(tokenId);
        if (currentSupply == 0) {
            require(msg.sender == creatorAddress, "Only creator can buy the first share");
        }

        uint256 price = getPrice(currentSupply, amount);
        uint256 devFee = (price * devFeePercent) / BPS_SCALE;
        uint256 creatorFee = (price * creatorFeePercent) / BPS_SCALE;
        uint256 tradingPoolFee = (price * tradingPoolFeePercent) / BPS_SCALE;
        uint256 totalCost = price + devFee + creatorFee + tradingPoolFee;

        bondingCurveReserves[creatorAddress] += price;

        if (totalCost > 0) {
            bool ok = bondingToken.transferFrom(msg.sender, address(this), totalCost);
            require(ok, "Transfer failed");
        }

        _mint(msg.sender, tokenId, amount, "");

        if (devFee > 0 && devFeeDestination != address(0)) {
            bondingToken.transfer(devFeeDestination, devFee);
        }
        if (creatorFee > 0) {
            bondingToken.transfer(creatorAddress, creatorFee);
        }
        if (tradingPoolFee > 0 && tradingPoolFeeDestination != address(0)) {
            bondingToken.transfer(tradingPoolFeeDestination, tradingPoolFee);
        }

        emit Trade(tokenId, msg.sender, creatorAddress, true, amount, price, currentSupply + amount);
    }

    function sellShares(uint256 tokenId, uint256 amount) public {
        require(amount > 0, "Amount must be greater than zero");
        address creatorAddress = creatorByTokenId[tokenId];
        require(creatorAddress != address(0), "Creator not registered or no token ID associated");
        require(balanceOf(msg.sender, tokenId) >= amount, "Insufficient shares");

        uint256 currentSupply = totalSupply(tokenId);
        require(currentSupply > amount, "Cannot sell shares if it makes supply zero or less through this method");

        uint256 price = getPrice(currentSupply - amount, amount);
        uint256 devFee = (price * devFeePercent) / BPS_SCALE;
        uint256 creatorFee = (price * creatorFeePercent) / BPS_SCALE;
        uint256 tradingPoolFee = (price * tradingPoolFeePercent) / BPS_SCALE;

        uint256 totalFees = devFee + creatorFee + tradingPoolFee;
        uint256 proceeds = price > totalFees ? price - totalFees : 0;

        _burn(msg.sender, tokenId, amount);

        if (proceeds > 0) {
            bondingToken.transfer(msg.sender, proceeds);
            bondingCurveReserves[creatorAddress] -= price;
        }
        if (devFee > 0 && devFeeDestination != address(0)) {
            bondingToken.transfer(devFeeDestination, devFee);
        }
        if (creatorFee > 0) {
            bondingToken.transfer(creatorAddress, creatorFee);
        }
        if (tradingPoolFee > 0 && tradingPoolFeeDestination != address(0)) {
            bondingToken.transfer(tradingPoolFeeDestination, tradingPoolFee);
        }

        emit Trade(tokenId, msg.sender, creatorAddress, false, amount, price, currentSupply - amount);
    }

    // TODO: full withdraw when?
    // function withdrawCreatorFees() public {
    //     uint256 amount = creatorAccumulatedFees[msg.sender];
    //     require(amount > 0, "No fees accumulated");

    //     creatorAccumulatedFees[msg.sender] = 0;
    //     bondingToken.transfer(msg.sender, amount);
    // }

    /**
     * @dev Returns since when a user has been continuously holding at least one token of a specific ID
     * @param tokenId The ID of the token to check
     * @param user The address of the user to check
     * @return The timestamp when the user first obtained the token, or 0 if they don't currently hold any
     */
    function getKeyHoldingSince(uint256 tokenId, address user) public view returns (uint256) {
        return keyHoldingSince[tokenId][user];
    }

    /**
     * @dev Checks if a user is eligible for some action based on how long they have held a specific token
     * @param tokenId The ID of the token to check
     * @param user The address of the user to check
     * @return True if the user is eligible, false otherwise
     */
    function isUserEligible(uint256 tokenId, address user) public view returns (bool) {
        return block.timestamp >= getKeyHoldingSince(tokenId, user) + 24 hours; // Example: 1 day eligibility
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        // Call super first to get the updated balances when checking in the later conditions
        super._update(from, to, ids, values);

        // For each token ID in the batch
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 tokenId = ids[i];

            // Handle recipient (to) - for mint and transfer operations
            if (to != address(0) && balanceOf(to, tokenId) == values[i]) {
                keyHoldingSince[tokenId][to] = block.timestamp;
            }

            // Handle sender (from) - reset timestamp if they no longer hold the token
            if (from != address(0) && balanceOf(from, tokenId) == 0) {
                keyHoldingSince[tokenId][from] = 0;
            }
        }
    }
}
