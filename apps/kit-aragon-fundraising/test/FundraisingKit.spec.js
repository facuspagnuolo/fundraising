/* eslint-disable no-undef */
const Kernel = artifacts.require('Kernel')
const ACL = artifacts.require('ACL')
const EVMScriptRegistry = artifacts.require('EVMScriptRegistry')
const MiniMeTokenFactory = artifacts.require('MiniMeTokenFactory')
const Vault = artifacts.require('Vault')
const Finance = artifacts.require('Finance')
const TokenManager = artifacts.require('TokenManager')
const Voting = artifacts.require('Voting')
const Tap = artifacts.require('Tap')
const Pool = artifacts.require('Pool')
const BancorMarketMaker = artifacts.require('BancorMarketMaker')
const Fundraising = artifacts.require('AragonFundraisingController')
const FundraisingKit = artifacts.require('FundraisingKit')

const namehash = require('eth-ens-namehash').hash
const arapp = require('../arapp.json')

const ANY_ADDRESS = '0xffffffffffffffffffffffffffffffffffffffff'
const NULL_ADDRESS = '0x00'
const ENS_ADDRESS = arapp.environments.default.registry

contract('FundraisingKit', accounts => {
  context('> #newInstance', () => {
    let factory
    let kit
    let receipt

    beforeEach(async () => {
      factory = await MiniMeTokenFactory.new()
      // kit = await FundraisingKit.new(ENS_ADDRESS, factory.address, true)
      const tokenReceipt = await kit.newToken('Native Governance Token', 'NGT')
      const token = tokenReceipt.logs.filter(l => l.event === 'DeployToken')[0].args.token
      receipt = await kit.newInstance(token)
    })

    it('it should deploy DAO', async () => {
      const address = receipt.logs.filter(l => l.event === 'DeployInstance')[0].args.dao
      assert.notEqual(address, NULL_ADDRESS)
    })
  })
})
