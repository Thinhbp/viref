// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";
abstract contract usdc {
    function decimals() external virtual returns (uint256) ;
}

contract VREF is ERC20 {
    constructor() ERC20("Virtual Referral Network", "VREF") {
    }

    address USDC = 0xD867D16EB1F8446300276f4c625040d391968e0b; // 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48 at ETH
    uint decimalUSDC = 18 - usdc(USDC).decimals() ; // 0 at BSC and 12 at ETH
    bool public status = true; 
    address owner = msg.sender;
    address withdrawAddress = msg.sender;
    uint public _tokenInPool;
    uint public _moneyInPool;
    enum statusEnum { ICO, IDO, subIDO }
    statusEnum public state = statusEnum.ICO;
    uint public currentStep = 0;
    uint public subIDOSold = 0;
    uint[30] icoPrice =[10,20,40,80,160,320,640,1280,2560,5120,10240,20480,40960,81920,163840,327680,655360,1310720,
    2621440,5242880,10485760,20971520,41943040,83886080,167772160,335544320,671088640,1342177280,2684354560,5368709120]; // * 100 already
    uint[30] tokenBeforeICO = [0,353553390593273762200422,603553390593273762200422,780330085889910643300633,905330085889910643300633,
    993718433538229083850739,1056218433538229083850739,1100412607362388304125792,1131662607362388304125792,1153759694274467914263318,
    1169384694274467914263318,1180433237730507719332081,1188245737730507719332081,1193770009458527621866463,1197676259458527621866463,
    1200438395322537573133654,1202391520322537573133654,1203772588254542548767249,1204749150754542548767249,1205439684720545036584047,
    1205927965970545036584047,1206273232953546280492445,1206517373578546280492445,1206690007070046902446645,1206812077382546902446645,
    1206898394128297213423745,1206959429284547213423745,1207002587657422368912294,1207033105235547368912294,1207054684421984946656569];
    uint moneyWithdrawed = 0;
    uint poolConstant = 0;
    
    event buy(address _address, uint _amount);
    event sell(address _address, uint _amount);
    event changestatus(bool _status);
    event withdraw(uint _amount);

    function buyToken(uint amount, uint expected) public {
        require(status, "Contract is maintaining");
        require(amount > 0, "Please input amount greater than 0");
        if (msg.sender !=  withdrawAddress) {
            require(IERC20(USDC).transferFrom(msg.sender, address(this), amount), "transfer USDC failed");
        } else {
            uint realMoneyInPool = IERC20(USDC).balanceOf(address(this)) * 10**decimalUSDC; // USDC uses 6 decimal places of precision, convert to 18
            uint moneyCanWithdraw = _tokenInPool*_moneyInPool/totalSupply() + realMoneyInPool+moneyWithdrawed-_moneyInPool;
            // _tokenInPool*_moneyInPool/totalSupply() : money unused base on AMM algorithm
            // most of time, realMoneyInPool = _moneyInPool-moneyWithdrawed , sometime, someone may send USDC to this address without any further action
            uint withdrawThisTime = (moneyCanWithdraw - moneyWithdrawed)/ 10**decimalUSDC;
            require(withdrawThisTime > 0, "no money can withdraw");
            moneyWithdrawed += withdrawThisTime * 10**decimalUSDC;
            amount = withdrawThisTime;
        }
        uint nextBreak;
        uint assumingToken;
        uint buyNowCost = 0;
        uint buyNowToken;

        amount = amount * 10**decimalUSDC; // Base on USDC's decimal, convert to 18
        uint tokenMint = 0;
        uint tokenTransferForUser = 0;
        uint currentMoney = _moneyInPool;
        uint moneyLeft = amount;

        while (moneyLeft > 0) {
            if (state == statusEnum.ICO) {
                nextBreak = (tokenBeforeICO[currentStep] + 5 * 10**5 * 10 **18) - _tokenInPool;
                assumingToken = moneyLeft * 100/icoPrice[currentStep];
            } else {
                if (currentStep==29 && state==statusEnum.IDO) { // nomore ICO
                    nextBreak = 2**256 - 1; // MAX_INT
                } else {
                    nextBreak = state == statusEnum.subIDO ? subIDOSold : (_tokenInPool - tokenBeforeICO[currentStep + 1]);
                }
                assumingToken = _tokenInPool - (poolConstant / (_moneyInPool + moneyLeft));
            }

            buyNowToken = nextBreak<assumingToken ? nextBreak : assumingToken;
            buyNowCost = moneyLeft;

            if (assumingToken>nextBreak) {
                buyNowCost = state == statusEnum.ICO ?
                                    buyNowToken * icoPrice[currentStep]/100 :
                                    (poolConstant/(_tokenInPool - buyNowToken) - _moneyInPool);
            }
            _moneyInPool += buyNowCost;

            if (state == statusEnum.ICO) {
                tokenMint += buyNowToken;
                _tokenInPool += buyNowToken;
            } else {
                tokenTransferForUser += buyNowToken;
                _tokenInPool -= buyNowToken;
            }

            if (assumingToken>=nextBreak) {
                if (state == statusEnum.ICO) {
                    state = statusEnum.IDO;
                    poolConstant = _tokenInPool * _moneyInPool;
                } else {
                    if (state == statusEnum.IDO) {
                        currentStep += 1;
                    }
                    state = statusEnum.ICO;
                    subIDOSold = 0;
                }
            } else if ( state==statusEnum.subIDO ) {
                subIDOSold -= buyNowToken;
            }
            moneyLeft = moneyLeft - buyNowCost;
        }
        require(tokenTransferForUser+tokenMint >= expected, "price slippage detected");
        require(_moneyInPool-currentMoney == amount, "something wrong with money");

        if (tokenMint > 0)  {
            _mint(address(this), tokenMint*2);
        }
        _transfer(address(this), msg.sender, tokenMint + tokenTransferForUser);

        require(_tokenInPool<=balanceOf(address(this)), "something wrong with _tokenInPool");
        emit buy(msg.sender, amount);
    }

    function sellToken(uint amount, uint expected) public {
        require(status, "Contract is maintaining");
        require(amount > 0, "invalid amount");
        if (state == statusEnum.ICO) {
            poolConstant = _tokenInPool * _moneyInPool;
        }
        uint currentMoney = _moneyInPool;
        uint moneyInpool = poolConstant / (_tokenInPool + amount);
        uint receivedMoney = currentMoney - moneyInpool;
        require(receivedMoney >= expected, "price slippage detected");
        require(transfer(address(this), amount), "transfer VREF failed");
        require(IERC20(USDC).transfer(msg.sender, receivedMoney/10**decimalUSDC), "transfer USDC failed");
        _moneyInPool -= receivedMoney;
        _tokenInPool += amount;
        if (state == statusEnum.ICO) {
            state = statusEnum.subIDO;
        }
        if (state == statusEnum.subIDO) {
            subIDOSold +=amount;
        }
        require(_tokenInPool<=balanceOf(address(this)), "something wrong with _tokenInPool");

        emit sell(msg.sender, amount);
    }

    function changeOwner(address _address) public {
        require(_address != address(0), "invalid address");
        require(msg.sender == owner, "permission denied");
        owner = _address;
    }
    
    function changeWithdrawAddress(address _address) public {
        require(_address != address(0), "invalid address");
        require(msg.sender == owner, "permission denied");
        withdrawAddress = _address;
    }

    function changeStatus(bool _status) public {
        require(msg.sender == owner, "permission denied");
        status = _status;
        emit changestatus(_status);
    }

    function collectWastedToken() public {
        require(msg.sender == withdrawAddress, "permission denied");
        uint wastedToken = balanceOf(address(this)) - _tokenInPool;
        require(wastedToken>0, "no token wasted");
        _transfer(address(this), withdrawAddress, wastedToken);
    }

}
