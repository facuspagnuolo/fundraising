/*
 * SPDX-License-Identitifer:    GPL-3.0-or-later
 */

pragma solidity 0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/common/SafeERC20.sol";
import "@aragon/os/contracts/lib/token/ERC20.sol";

import "@ablack/fundraising-interface-core/contracts/IMarketMakerController.sol";
import { BancorMarketMaker } from "../../BancorMarketMaker.sol";


contract SimpleMarketMakerController is IMarketMakerController, AragonApp {
    using SafeERC20 for ERC20;

    function initialize() external onlyInit {
        initialized();
    }

    function balanceOf(address _who, address _token) public view returns (uint256) {
         if (_token == ETH) {
            return _who.balance;
        } else {
            return ERC20(_token).staticBalanceOf(_who);
        }
    }
}
