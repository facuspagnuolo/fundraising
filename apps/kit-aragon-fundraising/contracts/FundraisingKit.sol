pragma solidity 0.4.24;

import "@aragon/os/contracts/common/Uint256Helpers.sol";
import "@aragon/os/contracts/apm/APMNamehash.sol";
import "@aragon/kits-beta-base/contracts/BetaKitBase.sol";
import "@ablack/fundraising-interface-core/contracts/IMarketMakerController.sol";
import "@ablack/fundraising-market-maker-bancor/contracts/BancorMarketMaker.sol";
import "@ablack/fundraising-controller-aragon-fundraising/contracts/AragonFundraisingController.sol";
import "@ablack/fundraising-market-maker-bancor/contracts/BancorMarketMaker.sol";
import "@ablack/fundraising-module-pool/contracts/Pool.sol";
import "@ablack/fundraising-module-tap/contracts/Tap.sol";


contract FundraisingKit is APMNamehash, BetaKitBase {
    using Uint256Helpers for uint256;

    constructor(
        DAOFactory _fac,
        ENS _ens,
        MiniMeTokenFactory _minimeFac,
        IFIFSResolvingRegistrar _aragonID,
        bytes32[4] _appIds
    )
        BetaKitBase(_fac, _ens, _minimeFac, _aragonID, _appIds) public
    {
        // solium-disable-previous-line no-empty-blocks
    }

    function newTokenAndInstance(
        string tokenName,
        string tokenSymbol,
        string aragonID,
        address[] holders,
        uint256[] tokens,
        IMarketMakerController controller,
        IBancorFormula formula
    ) public
    {
        newInstance(aragonID, holders, tokens, controller, formula);
        newToken(tokenName, tokenSymbol);
    }

    function newToken(string tokenName, string tokenSymbol) public returns (MiniMeToken token) {
        token = minimeFac.createCloneToken(
            MiniMeToken(address(0)),
            0,
            tokenName,
            0,
            tokenSymbol,
            true
        );
        cacheToken(token, msg.sender);
    }

    function newInstance(
        string aragonId,
        address[] holders,
        uint256[] tokens,
        IMarketMakerController controller,
        IBancorFormula formula
    )
        public
    {
        MiniMeToken token = popTokenCache(msg.sender);
        Kernel dao;
        ACL acl;
        TokenManager tokenManager;
        Voting voting;
        Finance finance;
        Vault vault;

        (dao, acl, finance, tokenManager, vault, voting) = createDAO(
            aragonId,
            token,
            holders,
            tokens,
            1
        );

        newFundraisingInstance(dao, acl, controller, formula, tokenManager, vault, voting);

        // Initialize all apps
        finance.initialize(vault, 30 days);
        token.changeController(tokenManager);
        tokenManager.initialize(token, true, 0);
        voting.initialize(token, uint64(50 * 10 ** 16), uint64(20 * 10 ** 16), 1 days);

        cleanupPermission(acl, voting, acl, acl.CREATE_PERMISSIONS_ROLE());
    }

    function newFundraisingInstance(
        Kernel dao,
        ACL acl,
        IMarketMakerController controller,
        IBancorFormula formula,
        TokenManager tokenManager,
        Vault vault,
        Voting voting
    ) internal
    {
        // Install app instances
        Pool pool = Pool(
            dao.newAppInstance(
                apmNamehash("pool"),
                latestVersionAppBase(apmNamehash("pool"))
            )
        );
        emit InstalledApp(pool, apmNamehash("pool"));

        Tap tap = Tap(
            dao.newAppInstance(
                apmNamehash("tap"),
                latestVersionAppBase(apmNamehash("tap"))
            )
        );

        AragonFundraisingController fundraising = AragonFundraisingController(
            dao.newAppInstance(
                apmNamehash("fundraising"),
                latestVersionAppBase(apmNamehash("fundraising"))
            )
        );
        emit InstalledApp(fundraising, apmNamehash("fundraising"));

        BancorMarketMaker marketMaker = BancorMarketMaker(
            dao.newAppInstance(
                apmNamehash("bancor-market-maker"),
                latestVersionAppBase(apmNamehash("bancor-market-maker"))
            )
        );
        emit InstalledApp(marketMaker, apmNamehash("bancor-market-maker"));

        // Permissions -- ANY_ENTITY === address(-1)
        acl.grantPermission(fundraising, dao, dao.APP_MANAGER_ROLE());
        acl.grantPermission(fundraising, acl, acl.CREATE_PERMISSIONS_ROLE());

        // Token Manager
        acl.createPermission(voting, tokenManager, tokenManager.ISSUE_ROLE(), voting);
        acl.createPermission(voting, tokenManager, tokenManager.ASSIGN_ROLE(), voting);
        acl.createPermission(voting, tokenManager, tokenManager.REVOKE_VESTINGS_ROLE(), voting);
        acl.createPermission(marketMaker, tokenManager, tokenManager.BURN_ROLE(), voting);
        acl.createPermission(marketMaker, tokenManager, tokenManager.MINT_ROLE(), voting);

        // Tap
        acl.createPermission(voting, tap, tap.UPDATE_RESERVE_ROLE(), voting);
        acl.createPermission(voting, tap, tap.UPDATE_BENEFICIARY_ROLE(), voting);
        acl.createPermission(voting, tap, tap.UPDATE_MONTHLY_TAP_INCREASE_ROLE(), voting);
        acl.createPermission(voting, tap, tap.ADD_TOKEN_TAP_ROLE(), voting);
        acl.createPermission(voting, tap, tap.REMOVE_TOKEN_TAP_ROLE(), voting);
        acl.createPermission(voting, tap, tap.UPDATE_TOKEN_TAP_ROLE(), voting);
        acl.createPermission(address(-1), tap, tap.WITHDRAW_ROLE(), voting);

        // BancorMarketMaker
        acl.createPermission(voting, marketMaker, marketMaker.ADD_COLLATERAL_TOKEN_ROLE(), voting);
        acl.createPermission(voting, marketMaker, marketMaker.UPDATE_COLLATERAL_TOKEN_ROLE(), voting);
        acl.createPermission(voting, marketMaker, marketMaker.UPDATE_FEE_ROLE(), voting);
        acl.createPermission(voting, marketMaker, marketMaker.UPDATE_GAS_COSTS_ROLE(), voting);
        acl.createPermission(address(-1), marketMaker, marketMaker.CREATE_BUY_ORDER_ROLE(), marketMaker);
        acl.createPermission(address(-1), marketMaker, marketMaker.CREATE_SELL_ORDER_ROLE(), marketMaker);

        // Pool
        acl.createPermission(marketMaker, pool, pool.SAFE_EXECUTE_ROLE(), voting);
        acl.createPermission(tap, pool, pool.SAFE_EXECUTE_ROLE(), voting);
        acl.createPermission(voting, pool, pool.ADD_COLLATERAL_TOKEN_ROLE(), voting);
        acl.createPermission(voting, pool, pool.REMOVE_COLLATERAL_TOKEN_ROLE(), voting);

        // Voting
        acl.createPermission(address(-1), voting, voting.CREATE_VOTES_ROLE(), voting);
        acl.createPermission(voting, voting, voting.MODIFY_SUPPORT_ROLE(), voting);

        // Vault
        acl.createPermission(tap, vault, vault.TRANSFER_ROLE(), vault);

        // Intialization
        pool.initialize();
        tap.initialize(vault, vault, uint256(50 * 10 ** 16));
        marketMaker.initialize(
          controller,
          tokenManager,
          vault,
          vault,
          formula,
          1,
          uint256(10 * 10 ** 16)
        );
        fundraising.initialize(marketMaker, pool, tap);
    }
}
