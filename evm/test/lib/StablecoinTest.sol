// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {MockBeacon} from "test/lib/mocks/MockBeacon.sol";
import {OverrideableBeaconProxy} from "src/OverrideableBeaconProxy.sol";
import {Stablecoin} from "src/Stablecoin.sol";

/// @dev Base test contract for Stablecoin. Deploys a full proxy stack and seeds actors
/// with tokens. All test files inherit from this. Override setUp() with super.setUp() to add
/// per-file preconditions.
contract StablecoinTest is Test {
    // ── EIP-712 typehashes (mirror private constants in ERC3009Upgradeable) ─────────────
    bytes32 internal constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 internal constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 internal constant CANCEL_AUTHORIZATION_TYPEHASH =
        keccak256("CancelAuthorization(address authorizer,bytes32 nonce)");

    // ── Signing keys ─────────────────────────────────────────────────────────────────────
    uint256 internal constant ALICE_KEY = 0xa11ce;
    uint256 internal constant BOB_KEY = 0xb0b;

    // ── Actors ───────────────────────────────────────────────────────────────────────────
    address internal alice; // vm.addr(ALICE_KEY) — can sign ERC3009 authorizations
    address internal bob; // vm.addr(BOB_KEY)   — can sign ERC3009 authorizations
    address internal admin = makeAddr("admin");
    address internal carol = makeAddr("carol");
    address internal minter = makeAddr("minter");
    address internal burner = makeAddr("burner");
    address internal rateLimitAdmin = makeAddr("rateLimitAdmin");
    address internal sanctioner = makeAddr("sanctioner");
    address internal pauser = makeAddr("pauser");
    address internal metadataAdmin = makeAddr("metadataAdmin");
    address internal relayer = makeAddr("relayer");
    address internal attacker = makeAddr("attacker");

    // ── Contracts ────────────────────────────────────────────────────────────────────────
    Stablecoin internal stablecoin;
    Stablecoin internal stablecoinImpl;
    MockBeacon internal beacon;
    OverrideableBeaconProxy internal proxy;

    // ── Defaults ─────────────────────────────────────────────────────────────────────────
    string internal constant TOKEN_NAME = "Test USD";
    string internal constant TOKEN_SYMBOL = "TUSD";
    uint8 internal constant TOKEN_DECIMALS = 6;
    uint256 internal constant MINT_LIMIT = 1_000_000e6;
    uint256 internal constant MINT_INTERVAL = 1 days;
    uint256 internal constant INITIAL_MINT = 100_000e6;

    // ── Setup ─────────────────────────────────────────────────────────────────────────────
    function setUp() public virtual {
        alice = vm.addr(ALICE_KEY);
        bob = vm.addr(BOB_KEY);

        // Deploy implementation and beacon
        stablecoinImpl = new Stablecoin();
        beacon = new MockBeacon(address(stablecoinImpl));

        // Deploy proxy and initialize in one step via constructor calldata
        bytes memory initData = abi.encodeCall(Stablecoin.initialize, (TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, admin));
        proxy = new OverrideableBeaconProxy(address(beacon), initData);
        stablecoin = Stablecoin(address(proxy));

        // Labels
        vm.label(address(stablecoin), "Stablecoin");
        vm.label(address(stablecoinImpl), "Stablecoin(impl)");
        vm.label(address(beacon), "MockBeacon");
        vm.label(address(proxy), "Proxy");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(admin, "admin");
        vm.label(carol, "carol");
        vm.label(minter, "minter");
        vm.label(burner, "burner");
        vm.label(rateLimitAdmin, "rateLimitAdmin");
        vm.label(sanctioner, "sanctioner");
        vm.label(pauser, "pauser");
        vm.label(metadataAdmin, "metadataAdmin");
        vm.label(relayer, "relayer");
        vm.label(attacker, "attacker");

        // Grant roles as admin
        vm.startPrank(admin);
        stablecoin.grantRole(stablecoin.MINT_ROLE(), minter);
        stablecoin.grantRole(stablecoin.BURN_ROLE(), burner);
        stablecoin.grantRole(stablecoin.MINT_RATE_LIMIT_ROLE(), rateLimitAdmin);
        stablecoin.grantRole(stablecoin.SANCTION_ROLE(), sanctioner);
        stablecoin.grantRole(stablecoin.PAUSE_ROLE(), pauser);
        stablecoin.grantRole(stablecoin.METADATA_ROLE(), metadataAdmin);
        vm.stopPrank();

        // Configure minter rate limit (requires MINT_RATE_LIMIT_ROLE + minter has MINT_ROLE)
        vm.prank(rateLimitAdmin);
        stablecoin.configureMinter(minter, MINT_LIMIT, MINT_INTERVAL);

        // Seed actors with tokens
        vm.prank(minter);
        stablecoin.mint(alice, INITIAL_MINT);
        vm.prank(minter);
        stablecoin.mint(bob, INITIAL_MINT);
        vm.prank(minter);
        stablecoin.mint(burner, INITIAL_MINT);
    }

    // ── Mint helpers ──────────────────────────────────────────────────────────────────────

    /// @dev Mints `amount` tokens to `to` as the minter.
    function _mint(address to, uint256 amount) internal {
        vm.prank(minter);
        stablecoin.mint(to, amount);
    }

    /// @dev Mints INITIAL_MINT tokens to `to`.
    function _mint(address to) internal {
        _mint(to, INITIAL_MINT);
    }

    // ── Burn helpers ──────────────────────────────────────────────────────────────────────

    /// @dev Burns `amount` from `caller`'s own balance. Caller must have BURN_ROLE.
    function _burn(address caller, uint256 amount) internal {
        vm.prank(caller);
        stablecoin.burn(amount);
    }

    // ── Transfer helpers ──────────────────────────────────────────────────────────────────

    /// @dev Calls transfer from `from` to `to`.
    function _transfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        stablecoin.transfer(to, amount);
    }

    // ── Pause helpers ─────────────────────────────────────────────────────────────────────

    /// @dev Pauses the stablecoin as the pauser.
    function _pause() internal {
        vm.prank(pauser);
        stablecoin.pause();
    }

    /// @dev Unpauses the stablecoin as the pauser.
    function _unpause() internal {
        vm.prank(pauser);
        stablecoin.unpause();
    }

    // ── Sanction helpers ──────────────────────────────────────────────────────────────────

    /// @dev Sanctions `account` as the sanctioner.
    function _sanction(address account) internal {
        vm.prank(sanctioner);
        stablecoin.updateSanctionStatus(account, true);
    }

    /// @dev Unsanctions `account` as the sanctioner.
    function _unsanction(address account) internal {
        vm.prank(sanctioner);
        stablecoin.updateSanctionStatus(account, false);
    }

    // ── EIP-712 digest helpers ────────────────────────────────────────────────────────────

    /// @dev Returns the EIP-712 digest for a TransferWithAuthorization.
    function _transferAuthDigest(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
        );
        return keccak256(abi.encodePacked("\x19\x01", stablecoin.DOMAIN_SEPARATOR(), structHash));
    }

    /// @dev Returns the EIP-712 digest for a ReceiveWithAuthorization.
    function _receiveAuthDigest(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
        );
        return keccak256(abi.encodePacked("\x19\x01", stablecoin.DOMAIN_SEPARATOR(), structHash));
    }

    /// @dev Returns the EIP-712 digest for a CancelAuthorization.
    function _cancelAuthDigest(address authorizer, bytes32 nonce) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce));
        return keccak256(abi.encodePacked("\x19\x01", stablecoin.DOMAIN_SEPARATOR(), structHash));
    }

    // ── ERC3009 signing helpers ───────────────────────────────────────────────────────────

    /// @dev Signs a TransferWithAuthorization and returns a packed (r, s, v) signature.
    function _signTransferAuth(
        uint256 signerKey,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (bytes memory) {
        bytes32 digest = _transferAuthDigest(from, to, value, validAfter, validBefore, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Signs a ReceiveWithAuthorization and returns a packed (r, s, v) signature.
    function _signReceiveAuth(
        uint256 signerKey,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (bytes memory) {
        bytes32 digest = _receiveAuthDigest(from, to, value, validAfter, validBefore, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Signs a CancelAuthorization and returns a packed (r, s, v) signature.
    function _signCancelAuth(uint256 signerKey, address authorizer, bytes32 nonce)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = _cancelAuthDigest(authorizer, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // ── ERC3009 call helpers ──────────────────────────────────────────────────────────────

    /// @dev Executes a TransferWithAuthorization as `caller`.
    function _transferWithAuth(
        address caller,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) internal {
        vm.prank(caller);
        stablecoin.transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, signature);
    }

    /// @dev Default: alice signs a transfer to bob, relayed by the relayer.
    /// Uses validAfter=0 and validBefore=max so timing is never a concern.
    function _transferWithAuth(uint256 amount, bytes32 nonce) internal {
        bytes memory sig = _signTransferAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        _transferWithAuth(relayer, alice, bob, amount, 0, type(uint256).max, nonce, sig);
    }

    /// @dev Default: alice signs a receive-auth to bob, submitted by bob (required by receiveWithAuth).
    function _receiveWithAuth(uint256 amount, bytes32 nonce) internal {
        bytes memory sig = _signReceiveAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        vm.prank(bob);
        stablecoin.receiveWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);
    }
}
