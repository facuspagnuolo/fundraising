pragma solidity ^0.4.24;

import "@aragon/os/contracts/lib/ens/ENS.sol";
import "@aragon/os/contracts/lib/ens/PublicResolver.sol";
import "@aragon/os/contracts/apm/Repo.sol";
import "@aragon/os/contracts/factory/DAOFactory.sol";
import "@aragon/apps-shared-minime/contracts/MiniMeToken.sol";
import "@aragon/apps-vault/contracts/Vault.sol";
import "@aragon/apps-finance/contracts/Finance.sol";
import "@aragon/apps-voting/contracts/Voting.sol";
import "@aragon/apps-token-manager/contracts/TokenManager.sol";

// Fundraising Apps
import "@ablack/controller-aragon-fundraising/contracts/AragonFundraisingController.sol";
import "@ablack/fundraising-market-maker-bancor/contracts/BancorMarketMaker.sol";
import "@ablack/fundraising-module-pool/contracts/Pool.sol";
import "@ablack/fundraising-module-tap/contracts/Tap.sol";

// We will probably need to hardcode these addresses to save gas
contract APMNamehash {
    bytes32 constant public ETH_NODE = keccak256(bytes32(0), keccak256("eth"));
    bytes32 constant public APM_NODE = keccak256(ETH_NODE, keccak256("aragonpm"));
    bytes32 constant public OPEN_NODE = keccak256(APM_NODE, keccak256("open"));

    function apmNamehash(string name, bool open) internal pure returns (bytes32) {
        if (open) {
            return keccak256(OPEN_NODE, keccak256(name));
        } else {
            return keccak256(APM_NODE, keccak256(name));
        }
    }
}


contract KitBase is APMNamehash {
    ENS        public ens;
    DAOFactory public fac;

    event DeployInstance(address dao);
    event InstalledApp(address appProxy, bytes32 appId);

    constructor(DAOFactory _fac, ENS _ens) public {
        ens = _ens;

        // If no factory is passed, get it from on-chain bare-kit
        if (address(_fac) == address(0)) {
            bytes32 bareKit = apmNamehash("bare-kit", false);
            fac = KitBase(latestVersionAppBase(bareKit)).fac();
        } else {
            fac = _fac;
        }
    }

    function latestVersionAppBase(bytes32 appId) public view returns (address base) {
        Repo repo = Repo(PublicResolver(ens.resolver(appId)).addr(appId));
        (,base,) = repo.getLatest();

        return base;
    }
}


contract FundraisingKit is KitBase {
    bool devchain;
    MiniMeTokenFactory tokenFactory;

    uint256 constant PCT = 10 ** 16;
    address constant ANY_ENTITY = address(-1);
    uint256 constant MAX_MONTHLY_TAP_INCREASE_RATE = 50 * (10 ** 16) // 5% per month set by default
    uint256 constant DEFAULT_FEE = 10 * (10 ** 16) // 1%
    uint256 constant DEFAULT_BATCH_BLOCK_SIZE = 1

    event DeployToken(address token, string name, string symbol);

    constructor(ENS _ens, MiniMeTokenFactory _tokenFactory, bool _devchain) public KitBase(DAOFactory(0), _ens) {
        devchain = _devchain;
        tokenFactory = _tokenFactory;
    }

    function newToken(string _name, string _symbol) external {
        MiniMeToken token = tokenFactory.createCloneToken(MiniMeToken(address(0)), 0, _name, 0, _symbol, true);

        emit DeployToken(address(token), _name, _symbol);
    }

    function newInstance(MiniMeToken token) external {
        bytes32[8] memory appIds = [
            apmNamehash("vault", false),
            apmNamehash("finance", false),
            apmNamehash("pool", false),
            apmNamehash("tap", false),
            apmNamehash("token-manager", false),
            apmNamehash("voting", false),
            apmNamehash("fundraising", false)
            apmNamehash("bancor-market-maker", false)
        ];

        // DAO
        Kernel dao = fac.newDAO(this);
        ACL    acl = ACL(dao.acl());
        EVMScriptRegistry reg = EVMScriptRegistry(acl.getEVMScriptRegistry());
        acl.createPermission(this, dao, dao.APP_MANAGER_ROLE(), this);

        // Apps
        Vault vault = Vault(
            dao.newAppInstance(
                appIds[0],
                latestVersionAppBase(appIds[0]),
                new bytes(0),
                true
            )
        );
        emit InstalledApp(vault, appIds[0]);

        Finance finance = Finance(
            dao.newAppInstance(
                appIds[1],
                latestVersionAppBase(appIds[1])
            )
        );
        emit InstalledApp(finance, appIds[1]);

        Pool pool = Pool(
            dao.newAppInstance(
                appIds[2],
                latestVersionAppBase(appIds[2])
            )
        );
        emit InstalledApp(pool, appIds[2]);

        Tap tap = Tap(
            dao.newAppInstance(
                appIds[3],
                latestVersionAppBase(appIds[3])
            )
        );
        emit InstalledApp(tap, appIds[3]);

        TokenManager tokenManager = TokenManager(
            dao.newAppInstance(
                appIds[4],
                latestVersionAppBase(appIds[4])
            )
        );
        emit InstalledApp(tokenManager, appIds[4]);

        Voting metavoting = Voting(
            dao.newAppInstance(
                appIds[3],
                latestVersionAppBase(appIds[5])
            )
        );
        emit InstalledApp(metavoting, appIds[5]);

        AragonFundraisingController controller = AragonFundraisingController(
            dao.newAppInstance(
                appIds[6],
                latestVersionAppBase(appIds[6])
            )
        );
        emit InstalledApp(controller, appIds[6]);

        BancorMarketMaker marketMaker = BancorMarketMaker(
            dao.newAppInstance(
                appIds[7],
                latestVersionAppBase(appIds[7])
            )
        );
        emit InstalledApp(marketMaker, appIds[7]);

        // Permissions
        acl.grantPermission(controller, dao, dao.APP_MANAGER_ROLE());
        acl.grantPermission(controller, acl, acl.CREATE_PERMISSIONS_ROLE());
        acl.createPermission(finance, vault, vault.TRANSFER_ROLE(), metavoting);
        acl.createPermission(metavoting, finance, finance.CREATE_PAYMENTS_ROLE(), metavoting);
        acl.createPermission(metavoting, finance, finance.EXECUTE_PAYMENTS_ROLE(), metavoting);
        acl.createPermission(metavoting, finance, finance.MANAGE_PAYMENTS_ROLE(), metavoting);
        acl.createPermission(this, tokenManager, tokenManager.MINT_ROLE(), this);

        // acl.createPermission(metavoting, tokenManager, tokenManager.ISSUE_ROLE(), metavoting);
        // acl.createPermission(metavoting, tokenManager, tokenManager.ASSIGN_ROLE(), metavoting);
        // acl.createPermission(metavoting, tokenManager, tokenManager.REVOKE_VESTINGS_ROLE(), metavoting);
        // acl.createPermission(metavoting, tokenManager, tokenManager.BURN_ROLE(), metavoting);

        acl.createPermission(ANY_ENTITY, metavoting, metavoting.CREATE_VOTES_ROLE(), metavoting);
        acl.createPermission(metavoting, metavoting, metavoting.MODIFY_SUPPORT_ROLE(), metavoting);
        acl.createPermission(metavoting, metavoting, metavoting.MODIFY_QUORUM_ROLE(), metavoting);

        // Initialize apps
        token.changeController(tokenManager);
        vault.initialize();
        finance.initialize(vault, 30 days);
        tokenManager.initialize(token, true, 0);
        metavoting.initialize(token, uint64(50 * PCT), uint64(20 * PCT), 1 days);
        pool.initialize()
        tap.initialize(vault, msg.sender, MAX_MONTHLY_TAP_INCREASE_RATE)
        /* marketMaker.initialize(
            marketMakerInterface.addr,
            tokenManager,
            vault,
            msg.sender,
            bancorFormulaInterface.addr,
            DEFAULT_BATCH_BLOCK_SIZE,
            DEFAULT_FEE
          ) Hardcode interface addresses?
        */
        // controller.initialize(marketMaker, reserve, tap);

        // Mint token
        // tokenManager.mint(msg.sender, uint256(1));

        // Cleanup permissions
        acl.grantPermission(metavoting, dao, dao.APP_MANAGER_ROLE());
        acl.revokePermission(this, dao, dao.APP_MANAGER_ROLE());
        acl.setPermissionManager(metavoting, dao, dao.APP_MANAGER_ROLE());
        acl.grantPermission(metavoting, acl, acl.CREATE_PERMISSIONS_ROLE());
        acl.revokePermission(this, acl, acl.CREATE_PERMISSIONS_ROLE());
        acl.setPermissionManager(metavoting, acl, acl.CREATE_PERMISSIONS_ROLE());
        // acl.grantPermission(metavoting, tokenManager, tokenManager.MINT_ROLE()); Remove
        acl.revokePermission(this, tokenManager, tokenManager.MINT_ROLE());
        acl.setPermissionManager(metavoting, tokenManager, tokenManager.MINT_ROLE());

        emit DeployInstance(dao);
    }
}
