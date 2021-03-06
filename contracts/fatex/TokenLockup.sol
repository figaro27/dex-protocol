// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

/**
 * This was copied from OpenZeppelin's TokenLockup contract to work for solidity version 5.0.
 */
contract TokenLockup is Ownable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event BeneficiarySet(address beneficary);
    event Released(uint256 amount);
    event Revoked();

    // beneficiary of tokens after they are released
    address public beneficiary;

    uint256 public cliff;
    uint256 public start;
    uint256 public duration;

    bool public revocable;

    mapping(address => uint256) public released;
    mapping(address => bool) public revoked;

    /**
     * @dev Creates a vesting contract that vests its balance of any ERC20 token to the
     * _beneficiary, gradually in a linear fashion until _start + _duration. By then all
     * of the balance will have vested.
     * @param _beneficiary address of the beneficiary to whom vested tokens are transferred
     * @param _startTimestamp the time (as Unix time) at which point vesting starts
     * @param _cliffDurationInSeconds duration in seconds of the cliff in which tokens will begin to vest
     * @param _durationInSeconds duration in seconds of the period in which the tokens will vest
     * @param _revocable whether the vesting is revocable or not
     */
    constructor(
        address _beneficiary,
        uint256 _startTimestamp,
        uint256 _cliffDurationInSeconds,
        uint256 _durationInSeconds,
        bool _revocable
    )
    public
    {
        require(_beneficiary != address(0));
        require(_cliffDurationInSeconds <= _durationInSeconds);

        beneficiary = _beneficiary;
        revocable = _revocable;
        duration = _durationInSeconds;
        cliff = _startTimestamp.add(_cliffDurationInSeconds);
        start = _startTimestamp;

        emit BeneficiarySet(_beneficiary);
    }

    function setBeneficiary(address _beneficiary) public {
        require(
            msg.sender == beneficiary,
            "TokenLockup:: UNAUTHORIZED"
        );
        require(
            _beneficiary != address(0),
            "TokenLockup:: INVALID_BENEFICIARY"
        );

        beneficiary = _beneficiary;
        emit BeneficiarySet(_beneficiary);
    }

    /**
     * @notice Transfers vested tokens to beneficiary.
     * @param _token ERC20 token which is being vested
     */
    function release(IERC20 _token) public {
        require(
            msg.sender == owner() || msg.sender == beneficiary,
            "TokenLockup: UNAUTHORIZED"
        );

        uint256 unreleased = releasableAmount(_token);

        require(
            unreleased > 0,
            "TokenLockup: NOTHING_TO_RELEASE"
        );

        released[address(_token)] = released[address(_token)].add(unreleased);

        _token.safeTransfer(beneficiary, unreleased);

        emit Released(unreleased);
    }

    /**
     * @notice Allows the owner to revoke the vesting. Tokens already vested
     * remain in the contract, the rest are returned to the owner.
     * @param _token ERC20 token which is being vested
     */
    function revoke(IERC20 _token) public onlyOwner {
        require(
            revocable,
            "TokenLockup: NOT_REVOCABLE"
        );
        require(
            !revoked[address(_token)],
            "TokenLockup: NOT_REVOCABLE"
        );

        uint256 balance = _token.balanceOf(address(this));

        uint256 unreleased = releasableAmount(_token);
        uint256 refund = balance.sub(unreleased);

        revoked[address(_token)] = true;

        _token.safeTransfer(owner(), refund);

        emit Revoked();
    }

    /**
     * @dev Calculates the amount that has already vested but hasn't been released yet.
     * @param _token ERC20 token which is being vested
     */
    function releasableAmount(IERC20 _token) public view returns (uint256) {
        return vestedAmount(_token).sub(released[address(_token)]);
    }

    /**
     * @dev Calculates the amount that has already vested.
     * @param _token ERC20 token which is being vested
     */
    function vestedAmount(IERC20 _token) public view returns (uint256) {
        uint256 currentBalance = _token.balanceOf(address(this));
        uint256 totalBalance = currentBalance.add(released[address(_token)]);

        if (block.timestamp < cliff) {
            return 0;
        } else if (block.timestamp >= start.add(duration) || revoked[address(_token)]) {
            return totalBalance;
        } else {
            return totalBalance.mul(block.timestamp.sub(start)).div(duration);
        }
    }
}
