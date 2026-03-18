// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";
import {Stablecoin} from "src/Stablecoin.sol";

/// @dev Handler contract for stateful fuzzing. Restricts all operations to known actors so that
/// ghost-balance and ghost-sanction state remain consistent with on-chain state throughout the run.
contract StablecoinHandler is Test {
    // ── Constants ─────────────────────────────────────────────────────────────────────────

    uint256 internal constant ALICE_KEY = 0xa11ce;

    bytes32 internal constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    // ── Contracts ─────────────────────────────────────────────────────────────────────────

    Stablecoin public stablecoin;

    // ── Privileged addresses ──────────────────────────────────────────────────────────────

    address public alice;
    address public minter;
    address public burner;
    address public sanctioner;

    /// @dev All token-holding actors. Mint recipients and transfer participants are restricted
    /// to this set so that sumBalances() accounts for every token in circulation.
    address[] public actors;

    // ── Ghost state ───────────────────────────────────────────────────────────────────────

    /// @dev Records each actor's balance at the moment they were most recently sanctioned.
    mapping(address => uint256) public balanceAtSanctionTime;

    /// @dev True when the actor is currently sanctioned according to ghost state.
    mapping(address => bool) public ghostSanctioned;

    /// @dev ERC-3009 nonces that alice has successfully consumed on-chain.
    bytes32[] internal _aliceUsedNonces;

    /// @dev Monotonic counter for generating unique nonces without hash collisions.
    uint256 internal _nonceCounter;

    // ── Constructor ───────────────────────────────────────────────────────────────────────

    constructor(
        Stablecoin stablecoin_,
        address alice_,
        address bob_,
        address carol_,
        address burner_,
        address minter_,
        address sanctioner_
    ) {
        stablecoin = stablecoin_;
        alice = alice_;
        minter = minter_;
        burner = burner_;
        sanctioner = sanctioner_;
        actors.push(alice_);
        actors.push(bob_);
        actors.push(carol_);
        actors.push(burner_);
    }

    // ── Handler actions ───────────────────────────────────────────────────────────────────

    /// @dev Mints up to the current rate-limit capacity to a randomly selected tracked actor.
    function mint(uint256 amount, uint256 recipientSeed) external {
        address to = actors[recipientSeed % actors.length];
        if (ghostSanctioned[to]) return;
        uint256 limit = stablecoin.currentMintLimit(minter);
        if (limit == 0) return;
        amount = bound(amount, 1, limit);
        vm.prank(minter);
        stablecoin.mint(to, amount);
    }

    /// @dev Burns a bounded amount from the burner's balance.
    function burn(uint256 amount) external {
        if (ghostSanctioned[burner]) return;
        uint256 balance = stablecoin.balanceOf(burner);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);
        vm.prank(burner);
        stablecoin.burn(amount);
    }

    /// @dev Transfers tokens between two randomly selected tracked actors.
    function transfer(uint256 amount, uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        if (ghostSanctioned[from] || ghostSanctioned[to]) return;
        uint256 balance = stablecoin.balanceOf(from);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);
        vm.prank(from);
        stablecoin.transfer(to, amount);
    }

    /// @dev Sanctions a randomly selected tracked actor and snapshots their current balance.
    function sanction(uint256 actorSeed) external {
        address target = actors[actorSeed % actors.length];
        if (ghostSanctioned[target]) return;
        balanceAtSanctionTime[target] = stablecoin.balanceOf(target);
        ghostSanctioned[target] = true;
        vm.prank(sanctioner);
        stablecoin.updateSanctionStatus(target, true);
    }

    /// @dev Unsanctions a randomly selected tracked actor.
    function unsanction(uint256 actorSeed) external {
        address target = actors[actorSeed % actors.length];
        if (!ghostSanctioned[target]) return;
        ghostSanctioned[target] = false;
        vm.prank(sanctioner);
        stablecoin.updateSanctionStatus(target, false);
    }

    /// @dev Submits a transferWithAuthorization signed by alice, consuming a unique nonce.
    function consumeNonce(uint256 amount, uint256 toSeed) external {
        address to = actors[toSeed % actors.length];
        if (ghostSanctioned[alice] || ghostSanctioned[to]) return;
        uint256 aliceBalance = stablecoin.balanceOf(alice);
        if (aliceBalance == 0) return;
        amount = bound(amount, 1, aliceBalance);

        // Each call gets a distinct nonce derived from the monotonic counter.
        bytes32 nonce = bytes32(_nonceCounter++);

        bytes32 structHash =
            keccak256(abi.encode(TRANSFER_WITH_AUTHORIZATION_TYPEHASH, alice, to, amount, 0, type(uint256).max, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", stablecoin.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_KEY, digest);

        stablecoin.transferWithAuthorization(alice, to, amount, 0, type(uint256).max, nonce, abi.encodePacked(r, s, v));
        _aliceUsedNonces.push(nonce);
    }

    // ── Ghost state reads ─────────────────────────────────────────────────────────────────

    /// @dev Returns the sum of on-chain balances across all tracked actors.
    function sumBalances() external view returns (uint256 total) {
        for (uint256 i = 0; i < actors.length; i++) {
            total += stablecoin.balanceOf(actors[i]);
        }
    }

    /// @dev Returns the number of ERC-3009 nonces alice has successfully consumed.
    function aliceUsedNoncesLength() external view returns (uint256) {
        return _aliceUsedNonces.length;
    }

    /// @dev Returns the i-th nonce consumed by alice.
    function aliceUsedNonces(uint256 i) external view returns (bytes32) {
        return _aliceUsedNonces[i];
    }
}

/// @dev Stateful fuzzer invariant tests. Forge calls targetContract functions in random sequences
/// and asserts these properties hold after every call. Actors: alice, bob, carol as token holders;
/// minter and burner as privileged roles.
contract StablecoinInvariantTest is StablecoinTest {
    StablecoinHandler internal handler;

    function setUp() public override {
        super.setUp();

        handler = new StablecoinHandler(stablecoin, alice, bob, carol, burner, minter, sanctioner);

        targetContract(address(handler));
    }

    // ── Supply accounting ─────────────────────────────────────────────────────────────────

    /// @notice Invariant: total supply always equals the sum of all individual account balances
    /// @dev Stateful: the fuzzer calls mint, burn, transfer in arbitrary sequences; accounting must hold throughout
    function invariant_totalSupplyEqualsSumOfTrackedBalances() public view {
        assertEq(stablecoin.totalSupply(), handler.sumBalances());
    }

    // ── Sanction enforcement ──────────────────────────────────────────────────────────────

    /// @notice Invariant: a sanctioned address can never receive tokens via any transfer path
    /// @dev Sanction: _requireNotSanctioned(to) in _update blocks all inbound transfers; balance must never increase while sanctioned
    function invariant_sanctionedAddressCannotReceiveTokens() public view {
        for (uint256 i = 0; i < 4; i++) {
            address actor = handler.actors(i);
            if (handler.ghostSanctioned(actor)) {
                assertLe(stablecoin.balanceOf(actor), handler.balanceAtSanctionTime(actor));
            }
        }
    }

    /// @notice Invariant: a sanctioned address can never send tokens via any transfer path
    /// @dev Sanction: _requireNotSanctioned(from) and _requireNotSanctioned(msg.sender) in _update block all outbound transfers
    function invariant_sanctionedAddressCannotSendTokens() public view {
        for (uint256 i = 0; i < 4; i++) {
            address actor = handler.actors(i);
            if (handler.ghostSanctioned(actor)) {
                assertGe(stablecoin.balanceOf(actor), handler.balanceAtSanctionTime(actor));
            }
        }
    }

    // ── Mint rate limit ───────────────────────────────────────────────────────────────────

    /// @notice Invariant: currentMintLimit for any minter never exceeds the configured limit
    /// @dev Cap: Math.min(remaining + replenishment, limit) must hold regardless of elapsed time or call order
    function invariant_mintLimitNeverExceedsConfiguredLimit() public view {
        assertLe(stablecoin.currentMintLimit(minter), MINT_LIMIT);
    }

    // ── Authorization nonce monotonicity ──────────────────────────────────────────────────

    /// @notice Invariant: once an authorization nonce is marked as used, it is never cleared
    /// @dev Permanent: authorizationState(authorizer, nonce) can only transition false → true, never true → false
    function invariant_authorizationStateOnceSetNeverCleared() public view {
        uint256 n = handler.aliceUsedNoncesLength();
        for (uint256 i = 0; i < n; i++) {
            assertTrue(stablecoin.authorizationState(alice, handler.aliceUsedNonces(i)));
        }
    }
}
