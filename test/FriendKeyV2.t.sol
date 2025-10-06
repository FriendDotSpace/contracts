// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {FriendKeyV2} from "src/upgrades/FriendKeyV2.sol";
import {FriendStake} from "src/FriendStake.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockERC20 is IERC20Metadata {
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;
    uint256 public totalSupply;
    string public name;
    string public symbol;
    uint8 public override decimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return balances[account];
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        balances[msg.sender] -= amount;
        balances[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        allowances[sender][msg.sender] -= amount;
        balances[sender] -= amount;
        balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function mint(address account, uint256 amount) external {
        balances[account] += amount;
        totalSupply += amount;
        emit Transfer(address(0), account, amount);
    }
}

contract FriendKeyV2Test is Test {
    FriendKeyV2 public instance;
    MockERC20 public mockUsdc;

    address public owner;
    address public devFeeDestination;
    address public creatorAccount;

    uint256 private constant OWNER_PRIVATE_KEY = 1;
    uint256 private constant DEV_FEE_PERCENT = 200;
    uint256 private constant CREATOR_FEE_PERCENT = 200;
    uint256 private constant TRADING_POOL_FEE_PERCENT = 600;

    bytes32 private constant REGISTER_CREATOR_TYPEHASH =
        keccak256("RegisterCreator(address account,uint8 tier,uint256 additionalKeys,uint256 nonce,string metadata)");
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256(bytes("FriendKey"));
    bytes32 private constant VERSION_HASH = keccak256(bytes("1"));

    function setUp() public {
        owner = vm.addr(1);
        devFeeDestination = vm.addr(2);
        creatorAccount = vm.addr(3);

        mockUsdc = new MockERC20("Mock USDC", "mUSDC", 6);
        FriendStake friendStakeImplementation = new FriendStake();

        FriendKeyV2 implementation = new FriendKeyV2();
        bytes memory initData = abi.encodeCall(
            FriendKeyV2.initialize,
            (
                owner,
                devFeeDestination,
                DEV_FEE_PERCENT,
                CREATOR_FEE_PERCENT,
                address(0),
                TRADING_POOL_FEE_PERCENT,
                0,
                0,
                address(mockUsdc),
                address(friendStakeImplementation)
            )
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        instance = FriendKeyV2(address(proxy));
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(instance))
        );
    }

    function _signRegister(
        address account,
        FriendKeyV2.RoomTier tier,
        uint256 additionalKeys,
        string memory metadata
    ) internal view returns (bytes memory) {
        uint256 nonce = instance.registerCreatorNonces(account);
        bytes32 structHash = keccak256(
            abi.encode(
                REGISTER_CREATOR_TYPEHASH,
                account,
                uint8(tier),
                additionalKeys,
                nonce,
                keccak256(bytes(metadata))
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function _register(
        address account,
        FriendKeyV2.RoomTier tier,
        uint256 additionalKeys,
        string memory metadata
    ) internal returns (uint256) {
        bytes memory signature = _signRegister(account, tier, additionalKeys, metadata);
        vm.prank(account);
        return instance.registerCreator(tier, additionalKeys, metadata, signature);
    }

    function testRegisterCreatorStoresMetadata() public {
        string memory metadata = "CREATOR_META_HASH";
        uint256 tokenId = _register(creatorAccount, FriendKeyV2.RoomTier.Casual, 0, metadata);

        assertEq(tokenId, 1, "Unexpected token id");
        assertEq(instance.creatorByTokenId(tokenId), creatorAccount, "Creator not stored");
        assertEq(instance.uri(tokenId), metadata, "Metadata should match provided string");
        assertEq(instance.registerCreatorNonces(creatorAccount), 1, "Nonce should increment");
    }

    function testRegisterCreatorAllowsEmptyMetadata() public {
        uint256 tokenId = _register(creatorAccount, FriendKeyV2.RoomTier.Casual, 0, "");
        assertEq(instance.uri(tokenId), "", "Empty metadata should yield empty URI");
    }

    function testRegisterCreatorRejectsMetadataMismatch() public {
        string memory authorizedMetadata = "AUTHORIZED_HASH";
        bytes memory signature = _signRegister(creatorAccount, FriendKeyV2.RoomTier.Casual, 0, authorizedMetadata);

        vm.expectRevert("Unauthorized register signature");
        vm.prank(creatorAccount);
        instance.registerCreator("OTHER_HASH", signature);
    }
}
