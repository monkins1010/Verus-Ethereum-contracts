// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../VerusBridge/VerusSerializer.sol";
import "../MMR/VerusBlake2b.sol";
import "../VerusNotarizer/VerusNotarizerStorage.sol";
import "../VerusBridge/VerusBridgeMaster.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract VerusNotarizer {
        
    using SafeMath for uint;

    //number of notaries required
    uint8 requiredNotaries = 13;

    uint8 constant FLAG_FRACTIONAL = 1;
    uint8 constant FLAG_REFUNDING = 4;
    uint8 constant FLAG_LAUNCHCONFIRMED = 0x10;
    uint8 constant FLAG_LAUNCHCOMPLETEMARKER = 0x20;
    bytes20 constant vdxfcode = bytes20(0x367Eaadd291E1976ABc446A143f83c2D4D2C5a84);

    VerusSerializer verusSerializer;
    VerusNotarizerStorage verusNotarizerStorage;
    VerusBridgeMaster verusBridgeMaster;
    address upgradeContract;
    // notarization vdxf key

    // list of all notarizers mapped to allow for quick searching
    mapping (address => VerusObjects.notarizer ) public notaryAddressMapping;
    mapping (address => uint) sigCheck;

    address[] private notaries;

    uint32 public notaryCount;
    bool public poolAvailable;
    VerusBlake2b blake2b;
    VerusObjectsNotarization.NotarizationForks[][] public bestForks;
    uint32 lastForkIndex;

    // Notifies when a new block hash is published
    event NewNotarization(uint32 notarizedDataHeight);
    uint8 constant PENDING = 1;
    uint8 constant CONFIRMED = 2;

    constructor(address _verusSerializerAddress, address upgradeContractAddress, 
    address[] memory _notaries, address[] memory _notariesEthAddress, address[] memory _notariesColdStoreEthAddress, 
    address verusNotarizerStorageAddress, address verusBridgeMasterAddress, address verusBLAKE2bAddress) {
        verusSerializer = VerusSerializer(_verusSerializerAddress);
        upgradeContract = upgradeContractAddress;
        notaryCount = uint32(_notaries.length);
        verusNotarizerStorage = VerusNotarizerStorage(verusNotarizerStorageAddress); 
        verusBridgeMaster = VerusBridgeMaster(verusBridgeMasterAddress);
        blake2b = VerusBlake2b(verusBLAKE2bAddress);

        // when contract is launching/upgrading copy in to global bool pool available.
        if(verusNotarizerStorage.poolAvailable(VerusConstants.VerusBridgeAddress) > 0 )
            poolAvailable = true;

        for(uint i =0; i < _notaries.length; i++){
            notaryAddressMapping[_notaries[i]] = VerusObjects.notarizer(_notariesEthAddress[i], _notariesColdStoreEthAddress[i], VerusConstants.NOTARY_VALID);
            notaries.push(_notaries[i]);
        }
    }

    function setContract(address contractAddress) public {

        require(msg.sender == upgradeContract);

        verusSerializer = VerusSerializer(contractAddress);

    }

    //NOTE: This modifier is not used, is it to be used it should be in the verusBridgeMAster contract.
    modifier onlyNotary() {
        address msgSender = msg.sender;
        bytes memory errorMessage = abi.encodePacked("Caller is not a notary",msgSender);
        require(notaryAddressMapping[msgSender].state == VerusConstants.NOTARY_VALID, string(errorMessage));
        _;
    }
    
    function getNotaries() public view returns(address[] memory){
        return notaries;
    }
        
    function isNotary(address _notary) public view returns(bool) {
       return (notaryAddressMapping[_notary].state == VerusConstants.NOTARY_VALID);  
    }

    //this function allows for intially expanding out the number of notaries
    function currentNotariesRequired() public view returns(uint8){

        if(notaryCount < 3 ) return 1;
        uint halfNotaryCount = (notaryCount/2) + 1;
        if(halfNotaryCount > requiredNotaries) return requiredNotaries;
        else return uint8(halfNotaryCount);
    }
 
    function setLatestData(VerusObjectsNotarization.CPBaaSNotarization memory _pbaasNotarization, bytes memory data
        ) public returns(bool output) {

       ( uint8[] memory _vs,
        bytes32[] memory _rs,
        bytes32[] memory _ss,
        uint32[] memory blockheights,
        address[] memory notaryAddress) = abi.decode(data,(uint8[],bytes32[], bytes32[],uint32[],address[]));

        bytes32 hashedNotarization;
        bytes memory serializedNotarisation = verusSerializer.serializeCPBaaSNotarization(_pbaasNotarization);

        // Notarizations are keyed by blake2b hash of notarization
        hashedNotarization = blake2b.createDefaultHash(serializedNotarisation);

        require(!verusNotarizerStorage.notarizationHashes(hashedNotarization),"Known hash of Notarization");

        bytes32 hashedNotarizationByID;
        uint validSignatures;

        checkunique(notaryAddress);

        for(uint i = 0; i < blockheights.length; i++)
        {
            // hash the notarizations with the vdxf key, system, height & NotaryID
            hashedNotarizationByID = keccak256(abi.encodePacked(uint8(1),
                vdxfcode,
                VerusConstants.VerusSystemId,
                verusSerializer.serializeUint32(blockheights[i]),
                notaryAddress[i],
                abi.encodePacked(keccak256(serializedNotarisation))));

            if (recoverSigner(hashedNotarizationByID, _vs[i]-4, _rs[i], _ss[i]) != notaryAddressMapping[notaryAddress[i]].main || sigCheck[notaryAddress[i]] != i)
            {
                revert("Invalid notary signature");  
            }
            if (notaryAddressMapping[notaryAddress[i]].state != VerusConstants.NOTARY_VALID)
            {
                revert("Notary revoked"); 
            }

            validSignatures++;
            
        }

        if(validSignatures < currentNotariesRequired())
        {
            return false;
        }
            
        //valid amount of notarizations achieved
        //loop through the currencystates and confirm if the bridge is active
        for(uint k= 0; k < _pbaasNotarization.currencystates.length || poolAvailable; k++)
        {
            if (!poolAvailable &&  _pbaasNotarization.currencystates[k].currencyid == VerusConstants.VerusBridgeAddress &&
                _pbaasNotarization.currencystates[k].currencystate.flags & (FLAG_FRACTIONAL + FLAG_REFUNDING + FLAG_LAUNCHCONFIRMED + FLAG_LAUNCHCOMPLETEMARKER) == 
                (FLAG_FRACTIONAL + FLAG_LAUNCHCONFIRMED + FLAG_LAUNCHCOMPLETEMARKER)) 
            {
                verusNotarizerStorage.setPoolAvailable();
                poolAvailable = true;
                verusBridgeMaster.sendVRSC();
            }
        }

        setNotarizationProofRoot(_pbaasNotarization, hashedNotarization);
        verusNotarizerStorage.setNotarization(_pbaasNotarization, hashedNotarization);

        emit NewNotarization(_pbaasNotarization.notarizationheight);
        
        return true;        

    }

    function setNotarizationProofRoot(VerusObjectsNotarization.CPBaaSNotarization memory _pbaasNotarization, bytes32 hashedNotarization) private 
    {
        bytes32 stateRoot;

        stateRoot = getVRSCStateRoot(_pbaasNotarization.proofroots);
        
        int forksLength = int(bestForks.length);
        int forkIdx = -1;
        int forkPos;
        
        if(forksLength == 0)
        {
            bestForks[0].push(VerusObjectsNotarization.NotarizationForks(reversebytes32(hashedNotarization), stateRoot, 
                              _pbaasNotarization.txid, _pbaasNotarization.notarizationheight, CONFIRMED, 0));
            return;
        }

        for (int i = 0; i < forksLength; i++) 
        {
            if (bestForks[uint(i)].length > 1)
            {
                for (int j = int(bestForks[uint(i)].length) - 1; j >= 0; j--)
                {
                    if (reversebytes32(hashedNotarization) == bestForks[uint(i)][uint(j)].hashOfNotarization)
                    {
                        forkIdx = i;
                        forkPos = j;
                        break;
                    }
                }
                if (forkIdx > -1)
                {
                    break;
                }
            }
        }
        if (forkIdx == -1)
        {
            revert("invalid prior notarization - neither pending nor confirmed");
        }

        if (forksLength == 1)
        {
            if (bestForks[0].length == 2 && forkPos == 1 && lastForkIndex == 1)
            {
                //This should be the most common case where we have [[0,1,2]]
                VerusObjectsNotarization.NotarizationForks memory tempProof;
                tempProof = bestForks[0][1];
                delete bestForks;
                bestForks[0].push(tempProof);
                bestForks[0].push(VerusObjectsNotarization.NotarizationForks(reversebytes32(hashedNotarization), stateRoot, 
                              _pbaasNotarization.txid, _pbaasNotarization.notarizationheight, PENDING, 1));
                return;

            }

            if (bestForks[0].length == 1 && forkPos == 0 && lastForkIndex == 0)
            {
                bestForks[0].push(VerusObjectsNotarization.NotarizationForks(reversebytes32(hashedNotarization), stateRoot, 
                _pbaasNotarization.txid, _pbaasNotarization.notarizationheight, PENDING, 1));
                lastForkIndex = 1;
                return;
            }
        }
        else if (forksLength > 1)
        {
           

        }


 /* 
        for (uint i = 0; i < forksLength; i++) {

            VerusObjectsNotarization.NotarizationForks memory tempProof;
            uint idx;
            uint num;

            (idx, num) = verusNotarizerStorage.getbestFork(i);
            
            if (verusNotarizerStorage.getbestFork(i).hashOfNotarization == _pbaasNotarization.hashprevnotarization) {
                
                tempProof = verusNotarizerStorage.getbestFork(i);
                verusNotarizerStorage.deletebestFork();
                verusNotarizerStorage.setbestFork(tempProof);
                verusNotarizerStorage.setbestFork(NotarizationFork);
                return;
            }

        }
        revert("Hash of notarization not found"); */
 

    }

    function getVRSCStateRoot(VerusObjectsNotarization.CProofRoot[] memory proofroots) public pure returns (bytes32) {

        for (uint i = 0; i < proofroots.length; i++) 
        {
            if (proofroots[i].systemid == VerusConstants.VerusCurrencyId) 
            {
                 return proofroots[i].stateroot;
            }
        }  

        return bytes32(0);
    }

    function checkunique(address[] memory ids) private
    {
        for (uint i = 0; i < ids.length; i++)
        {
            sigCheck[ids[i]] = i;
        }
    }


    function recoverSigner(bytes32 _h, uint8 _v, bytes32 _r, bytes32 _s) public pure returns (address) {

        return ecrecover(_h, _v, _r, _s);
    }

    function setClaimableFees(address _feeRecipient, address _proposer, uint256 _ethAmount, address bridgekeeper) public returns (uint256){

        require(msg.sender == address(verusBridgeMaster)); 
        
        uint256 notaryFees;
        uint256 LPFees;
        uint256 exporterFees;
        uint256 proposerFees;  
        uint256 bridgekeeperFees;              

        notaryFees = _ethAmount.div(10).mul(3); 

        exporterFees = _ethAmount.div(10);
        proposerFees = _ethAmount.div(10);
        bridgekeeperFees = _ethAmount.div(10).mul(3); 

        LPFees = _ethAmount - (notaryFees + exporterFees + proposerFees + bridgekeeperFees);

        setNotaryFees(notaryFees);
        verusBridgeMaster.setClaimedFees(_feeRecipient, exporterFees);
        verusBridgeMaster.setClaimedFees(_proposer, proposerFees);
        verusBridgeMaster.setClaimedFees(bridgekeeper, bridgekeeperFees);

        //return total amount of unclaimed LP Fees accrued.
        return verusBridgeMaster.setClaimedFees(address(this), LPFees);
              
    }

    function setNotaryFees(uint256 notaryFees) private {
        
        uint32 psudorandom = uint32(uint(keccak256(abi.encodePacked(block.difficulty, block.timestamp))));

        uint32 notaryTurn = uint32(psudorandom % (notaries.length ));

        verusBridgeMaster.setClaimedFees(notaries[notaryTurn], notaryFees);

    }

    function updateNotarizer(address notarizer, address mainAddress, address revokeAddress, uint8 state) public
    {
        require(msg.sender == upgradeContract);
        notaryAddressMapping[notarizer] = VerusObjects.notarizer(mainAddress, revokeAddress, state);

    }

    function reversebytes32(bytes32 input) internal pure returns (bytes32) {

        uint256 v;
        v = uint256(input);
    
        // swap bytes
        v = ((v & 0xFF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00) >> 8) |
            ((v & 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF) << 8);
    
        // swap 2-byte long pairs
        v = ((v & 0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000) >> 16) |
            ((v & 0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF) << 16);
    
        // swap 4-byte long pairs
        v = ((v & 0xFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000) >> 32) |
            ((v & 0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF) << 32);
    
        // swap 8-byte long pairs
        v = ((v & 0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000) >> 64) |
            ((v & 0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF) << 64);
    
        // swap 16-byte long pairs
        v = (v >> 128) | (v << 128);
        
        return bytes32(v);
    }

}
