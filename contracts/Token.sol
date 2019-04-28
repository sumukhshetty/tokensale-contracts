pragma solidity ^0.5.0;

import './SafeMath.sol';
import './Controllable.sol';
import './ControllerInterface.sol';
import './TokenFactoryInterface.sol';
import './TokenInterface.sol';


contract Token is Controllable {

  using SafeMath for uint256;
  TokenInterface public parentToken;
  TokenFactoryInterface public tokenFactory;

  string public name;
  string public symbol;
  string public version;
  uint8 public decimals;

  uint256 public parentSnapShotBlock;
  uint256 public creationBlock;
  bool public transfersEnabled;

  bool public masterTransfersEnabled;
  address public masterWallet = 0xD8271285C255Ce31b9b25E46ac63619322Af5934;

  struct Checkpoint {
    uint128 fromBlock;
    uint128 value;
  }

  Checkpoint[] totalSupplyHistory;
  mapping(address => Checkpoint[]) balances;
  mapping (address => mapping (address => uint)) allowed;

  bool public mintingFinished = false;
  bool public presaleBalancesLocked = false;

  uint256 public TOTAL_PRESALE_TOKENS = 112386712924725508802400;

  event Mint(address indexed to, uint256 amount);
  event MintFinished();
  event ClaimedTokens(address indexed _token, address indexed _owner, uint _amount);
  event Approval(address indexed _owner, address indexed _spender, uint256 _amount);
  event Transfer(address indexed from, address indexed to, uint256 value);




  constructor(
    address _tokenFactory,
    address _parentToken,
    uint256 _parentSnapShotBlock,
    string memory _tokenName,
    string memory _tokenSymbol
    ) public {
      tokenFactory = TokenFactoryInterface(_tokenFactory);
      parentToken = TokenInterface(_parentToken);
      parentSnapShotBlock = _parentSnapShotBlock;
      name = _tokenName;
      symbol = _tokenSymbol;
      decimals = 18;
      transfersEnabled = false;
      masterTransfersEnabled = false;
      creationBlock = block.number;
      version = '0.1';
  }

  function() external payable {
    revert();
  }


  /**
  * Returns the total token supply at the current block
  * @return total supply {uint256}
  */
  function totalSupply() public view returns (uint256) {
    return totalSupplyAt(block.number);
  }

  /**
  * Returns the total token supply at the given block number
  * @param _blockNumber {uint256}
  * @return total supply {uint256}
  */
  function totalSupplyAt(uint256 _blockNumber) public view returns(uint256) {
    // These next few lines are used when the totalSupply of the token is
    //  requested before a check point was ever created for this token, it
    //  requires that the `parentToken.totalSupplyAt` be queried at the
    //  genesis block for this token as that contains totalSupply of this
    //  token at this block number.
    if ((totalSupplyHistory.length == 0) || (totalSupplyHistory[0].fromBlock > _blockNumber)) {
        if (address(parentToken) != address(0)) {
            return parentToken.totalSupplyAt(min(_blockNumber, parentSnapShotBlock));
        } else {
            return 0;
        }

    // This will return the expected totalSupply during normal situations
    } else {
        return getValueAt(totalSupplyHistory, _blockNumber);
    }
  }

  /**
  * Returns the token holder balance at the current block
  * @param _owner {address}
  * @return balance {uint256}
   */
  function balanceOf(address _owner) public view returns (uint256 balance) {
    return balanceOfAt(_owner, block.number);
  }

  /**
  * Returns the token holder balance the the given block number
  * @param _owner {address}
  * @param _blockNumber {uint256}
  * @return balance {uint256}
  */
  function balanceOfAt(address _owner, uint256 _blockNumber) public view returns (uint256) {
    // These next few lines are used when the balance of the token is
    //  requested before a check point was ever created for this token, it
    //  requires that the `parentToken.balanceOfAt` be queried at the
    //  genesis block for that token as this contains initial balance of
    //  this token
    if ((balances[_owner].length == 0) || (balances[_owner][0].fromBlock > _blockNumber)) {
        if (address(parentToken) != address(0)) {
            return parentToken.balanceOfAt(_owner, min(_blockNumber, parentSnapShotBlock));
        } else {
            // Has no parent
            return 0;
        }

    // This will return the expected balance during normal situations
    } else {
        return getValueAt(balances[_owner], _blockNumber);
    }
  }

  /**
  * Standard ERC20 transfer tokens function
  * @param _to {address}
  * @param _amount {uint}
  * @return success {bool}
  */
  function transfer(address _to, uint256 _amount) public returns (bool success) {
    return doTransfer(msg.sender, _to, _amount);
  }

  /**
  * Standard ERC20 transferFrom function
  * @param _from {address}
  * @param _to {address}
  * @param _amount {uint256}
  * @return success {bool}
  */
  function transferFrom(address _from, address _to, uint256 _amount) public returns (bool success) {
    require(allowed[_from][msg.sender] >= _amount);
    allowed[_from][msg.sender] -= _amount;
    return doTransfer(_from, _to, _amount);
  }

  /**
  * Standard ERC20 approve function
  * @param _spender {address}
  * @param _amount {uint256}
  * @return success {bool}
  */
  function approve(address _spender, uint256 _amount) public returns (bool success) {
    require(transfersEnabled);

    //https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    require((_amount == 0) || (allowed[msg.sender][_spender] == 0));

    allowed[msg.sender][_spender] = _amount;
    emit Approval(msg.sender, _spender, _amount);
    return true;
  }

  /**
  * Standard ERC20 allowance function
  * @param _owner {address}
  * @param _spender {address}
  * @return remaining {uint256}
   */
  function allowance(address _owner, address _spender) public view returns (uint256 remaining) {
    return allowed[_owner][_spender];
  }

  /**
  * Internal Transfer function - Updates the checkpoint ledger
  * @param _from {address}
  * @param _to {address}
  * @param _amount {uint256}
  * @return success {bool}
  */
  function doTransfer(address _from, address _to, uint256 _amount) internal returns(bool) {

    if (msg.sender != masterWallet) {
      require(transfersEnabled);
    } else {
      require(masterTransfersEnabled);
    }

    require(_amount > 0);
    require(parentSnapShotBlock < block.number);
    require((_to != address(0)) && (_to != address(this)));

    // If the amount being transfered is more than the balance of the
    // account the transfer returns false
    uint256 previousBalanceFrom = balanceOfAt(_from, block.number);
    require(previousBalanceFrom >= _amount);

    // First update the balance array with the new value for the address
    //  sending the tokens
    updateValueAtNow(balances[_from], previousBalanceFrom - _amount);

    // Then update the balance array with the new value for the address
    //  receiving the tokens
    uint256 previousBalanceTo = balanceOfAt(_to, block.number);
    require(previousBalanceTo + _amount >= previousBalanceTo); // Check for overflow
    updateValueAtNow(balances[_to], previousBalanceTo + _amount);

    // An event to make the transfer easy to find on the blockchain
    emit Transfer(_from, _to, _amount);
    return true;
  }


  /**
  * Token creation functions - can only be called by the tokensale controller during the tokensale period
  * @param _owner {address}
  * @param _amount {uint256}
  * @return success {bool}
  */
  function mint(address _owner, uint256 _amount) public onlyController canMint returns (bool) {
    uint256 curTotalSupply = totalSupply();
    uint256 previousBalanceTo = balanceOf(_owner);

    require(curTotalSupply + _amount >= curTotalSupply); // Check for overflow
    require(previousBalanceTo + _amount >= previousBalanceTo); // Check for overflow

    updateValueAtNow(totalSupplyHistory, curTotalSupply + _amount);
    updateValueAtNow(balances[_owner], previousBalanceTo + _amount);
    emit Transfer(address(0), _owner, _amount);
    return true;
  }

  modifier canMint() {
    require(!mintingFinished);
    _;
  }


  /**
   * Import presale balances before the start of the token sale. After importing
   * balances, lockPresaleBalances() has to be called to prevent further modification
   * of presale balances.
   * @param _addresses {address[]} Array of presale addresses
   * @param _balances {uint256[]} Array of balances corresponding to presale addresses.
   * @return success {bool}
   */
  function importPresaleBalances(address[] memory _addresses, uint256[] memory _balances) public onlyController returns (bool) {
    require(presaleBalancesLocked == false);

    for (uint256 i = 0; i < _addresses.length; i++) {
      updateValueAtNow(balances[_addresses[i]], _balances[i]);
      emit Transfer(address(0), _addresses[i], _balances[i]);
    }

    updateValueAtNow(totalSupplyHistory, TOTAL_PRESALE_TOKENS);
    return true;
  }

  /**
   * Lock presale balances after successful presale balance import
   * @return A boolean that indicates if the operation was successful.
   */
  function lockPresaleBalances() public onlyController returns (bool) {
    presaleBalancesLocked = true;
    return true;
  }

  /**
   * Lock the minting of Tokens - to be called after the presale
   * @return {bool} success
  */
  function finishMinting() public onlyController returns (bool) {
    mintingFinished = true;
    emit MintFinished();
    return true;
  }

  /**
   * Enable or block transfers - to be called in case of emergency
   * @param _value {bool}
  */
  function enableTransfers(bool _value) public onlyController {
    transfersEnabled = _value;
  }

  /**
   * Enable or block transfers - to be called in case of emergency
   * @param _value {bool}
  */
  function enableMasterTransfers(bool _value) public onlyController {
    masterTransfersEnabled = _value;
  }

  /**
   * Internal balance method - gets a certain checkpoint value a a certain _block
   * @param _checkpoints {Checkpoint[]} List of checkpoints - supply history or balance history
   * @return value {uint256} Value of _checkpoints at _block
  */
  function getValueAt(Checkpoint[] storage _checkpoints, uint256 _block) view internal returns (uint256) {

      if (_checkpoints.length == 0)
        return 0;
      // Shortcut for the actual value
      if (_block >= _checkpoints[_checkpoints.length-1].fromBlock)
        return _checkpoints[_checkpoints.length-1].value;
      if (_block < _checkpoints[0].fromBlock)
        return 0;

      // Binary search of the value in the array
      uint256 min = 0;
      uint256 max = _checkpoints.length-1;
      while (max > min) {
          uint256 mid = (max + min + 1) / 2;
          if (_checkpoints[mid].fromBlock<=_block) {
              min = mid;
          } else {
              max = mid-1;
          }
      }
      return _checkpoints[min].value;
  }


  /**
  * Internal update method - updates the checkpoint ledger at the current block
  * @param _checkpoints {Checkpoint[]}  List of checkpoints - supply history or balance history
  * @return value {uint256} Value to add to the checkpoints ledger
   */
  function updateValueAtNow(Checkpoint[] storage _checkpoints, uint256 _value) internal {
      if ((_checkpoints.length == 0) || (_checkpoints[_checkpoints.length-1].fromBlock < block.number)) {
              Checkpoint storage newCheckPoint = _checkpoints[_checkpoints.length++];
              newCheckPoint.fromBlock = uint128(block.number);
              newCheckPoint.value = uint128(_value);
          } else {
              Checkpoint storage oldCheckPoint = _checkpoints[_checkpoints.length-1];
              oldCheckPoint.value = uint128(_value);
          }
  }


  function min(uint256 a, uint256 b) internal pure returns (uint) {
      return a < b ? a : b;
  }