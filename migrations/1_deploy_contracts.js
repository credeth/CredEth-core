const CredETH = artifacts.require("./CredEth.sol");

module.exports = async (deployer, network, accounts) => {
    let owner;
    if (network == "development") {
        owner = accounts[0];
    }
    else if (network == "kovan") {
        owner = accounts[0];
    }
    await deployer.deploy(CredETH, {from: owner});
}