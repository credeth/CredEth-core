pragma solidity ^0.5.7;

interface CredEthInterface {

    function daoDistribution(address _to, uint256 _rep) external;

    function issueReputation(address _to, uint256 _reputation) external;
    
}