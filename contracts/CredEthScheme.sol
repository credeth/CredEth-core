pragma solidity ^0.5.7;

import "@daostack/infra/contracts/votingMachines/ProposalExecuteInterface.sol";
import "@daostack/arc/contracts/universalSchemes/UniversalScheme.sol";
import "@daostack/arc/contracts/controller/ControllerInterface.sol";
import "@daostack/arc/contracts/votingMachines/VotingMachineCallbacks.sol";
import "./CredEthInterface.sol";


/**
 * @title A universal scheme for proposing "Credit reputation status" and rewarding proposers with reputation
 * @dev An agent can propose the organization a "reason of the credit reputation" to send.
 * if accepted the proposal will be posted by the organization
 * and the proposer will receive Credit reputation.
 */
contract CredEthScheme is UniversalScheme, VotingMachineCallbacks, ProposalExecuteInterface {

    // Peepeth contract address on the Ethereum Kovan testnet
    address public constant CREDETH_KOVAN = 0x91609ad30eba869c1f412e5656dead7bcaacaa5f;

    address public credEthContract;
    
    //event PeepethAccountRegistered(address indexed _avatar, bytes16 _name, string _ipfsHash);

    event NewCreditReputationProposal(
        address indexed _avatar,
        bytes32 indexed _proposalId,
        address indexed _intVoteInterface,
        address _proposer,
        string _applicationHash,
        uint _reputationChange,
        uint256 _proposedCreditReputation
    );

    event ProposalExecuted(address indexed _avatar, bytes32 indexed _proposalId, int _param);

    // A struct representing a proposal to send a new credit reputation by the avatar of an organization
    struct CreditReputationProposal {
        address proposer; // The proposer of the tweet
        string applicationHash; // The IPFS hash of the application Hash to accept
        uint reputationChange; // Organization reputation reward requested by the proposer.
        uint256 proposedCreditReputation;
    }

    // A mapping from the organization (Avatar) address to the saved proposals of the organization:
    mapping(address=>mapping(bytes32=>CreditReputationProposal)) public organizationsProposals;

    // A struct representing organization parameters in the Universal Scheme.
    // The parameters represent a specific configuration set for an organization.
    // The parameters should be approved and registered in the controller of the organization.
    struct Parameters {

        bytes32 voteApproveParams; // The hash of the approved parameters of a Voting Machine for a specific organization.
                                    // Used in the voting machine as the key in the parameters mapping to 
                                    // Note that these settings should be registered in the Voting Machine prior of using this scheme.
                                    // You can see how to register the parameters by looking on `2_deploy_dao.js` under the `migrations` folder at line #64.
        
        IntVoteInterface intVote; // The address of the Voting Machine to be used to propose and vote on a proposal.
    }
    // A mapping from hashes to parameters (use to store a particular configuration on the controller)
    mapping(bytes32 => Parameters) public parameters;
    
    // // A mapping from the organization (Avatar) address to its Peepeth account name.
    // mapping(address => bytes16) public peepethAccounts;

    constructor(address _credEthContract) public {
        credEthContract = _credEthContract;
    }

    /**
    * @dev hash the parameters, save them if necessary, and return the hash value
    */
    function setParameters(
        bytes32 _voteApproveParams,
        IntVoteInterface _intVote
    ) public returns(bytes32)
    {
        bytes32 paramsHash = getParametersHash(
            _voteApproveParams,
            _intVote
        );
        parameters[paramsHash].voteApproveParams = _voteApproveParams;
        parameters[paramsHash].intVote = _intVote;
        return paramsHash;
    }

    /**
    * @dev hash the parameters and return the hash
    */
    function getParametersHash(
        bytes32 _voteApproveParams,
        IntVoteInterface _intVote
    ) public pure returns(bytes32)
    {
        return (keccak256(abi.encodePacked(_voteApproveParams, _intVote)));
    }

   
    function proposeCreditReputation(
        Avatar _avatar,
        string memory _applicationHash,
        uint256 _reputationChange,
        uint256 _proposedCreditReputation
    ) public
      returns(bytes32)
    {
        Parameters memory controllerParams = parameters[getParametersFromController(_avatar)];

        bytes32 credId = controllerParams.intVote.propose(
            3,
            controllerParams.voteApproveParams,
            msg.sender,
            address(_avatar)
        );

        // Set the struct:
        CreditReputationProposal memory proposal = CreditReputationProposal({
            proposer: msg.sender,
            applicationHash: _applicationHash,
            reputationChange: _reputationChange,
            proposedCreditReputation: _proposedCreditReputation
        });
        //proposalInfo[address(controllerParams.intVote)][credId] = ProposalInfo(block.number, _avatar);
        organizationsProposals[address(_avatar)][credId] = proposal;

        emit NewCreditReputationProposal(
            address(_avatar),
            credId,
            address(controllerParams.intVote),
            msg.sender,
            _applicationHash,
            _reputationChange,
            _proposedCreditReputation
        );

        return credId;
    }

    /**
    * @dev execution of proposals, can only be called by the voting machine in which the vote is held.
    * @param _proposalId the ID of the voting in the voting machine
    * @param _param a parameter of the voting result, 1 yes and 2 is no.
    */
    function executeProposal(bytes32 _proposalId, int _param)  public returns(bool) {
        address avatar = proposalsInfo[_proposalId].avatar;

        // Check the caller is indeed the voting machine:
        require(
            parameters[getParametersFromController(Avatar(avatar))].intVote == msg.sender, 
            "Only the voting machine can execute proposal"
        );

        // Check if vote was successful:
        if (_param == 1) {
            CreditReputationProposal memory proposal = organizationsProposals[avatar][_proposalId];
            
            ControllerInterface controller = ControllerInterface(Avatar(avatar).owner());
            // Sends a call to the Peepeth contract to post a new peep.
            // The call will be made from the avatar address such that when received by the Peepeth contract, the msg.sender value will be the avatar's address
            controller.genericCall(credEthContract, abi.encodeWithSelector(CredEthInterface(credEthContract).daoDistribution.selector, proposal.proposer, proposal.proposedCreditReputation), avatar);
            
            // Mints reputation for the proposer of the Peep.
            require(
                ControllerInterface(Avatar(avatar).owner()).mintReputation(uint(proposal.reputationChange), proposal.proposer, avatar),
                "Failed to mint reputation to proposer"
            );
        } else {
            delete organizationsProposals[avatar][_proposalId];
        }

        emit ProposalExecuted(avatar, _proposalId, _param);

        return true;
    }
}