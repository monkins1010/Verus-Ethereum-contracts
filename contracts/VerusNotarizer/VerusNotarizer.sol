// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../VerusBridge/VerusSerializer.sol";
import "../VerusNotarizer/VerusNotarizerStorage.sol";
import "../VerusBridge/VerusBridgeMaster.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract VerusNotarizer {
        
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

    bool public poolAvailable;
    VerusObjectsNotarization.NotarizationForks[12][8] public bestForks;
    int32 lastForkIndex;
    int32[8] notarizationLength;
    int32 amountsOfForks;
    // Notifies when a new block hash is published
    event NewNotarization(uint32 notarizedDataHeight);

    constructor(address _verusSerializerAddress, address upgradeContractAddress, 
    address[] memory _notaries, address[] memory _notariesEthAddress, address[] memory _notariesColdStoreEthAddress, 
    address verusNotarizerStorageAddress, address verusBridgeMasterAddress) {
        verusSerializer = VerusSerializer(_verusSerializerAddress);
        upgradeContract = upgradeContractAddress;
        verusNotarizerStorage = VerusNotarizerStorage(verusNotarizerStorageAddress); 
        verusBridgeMaster = VerusBridgeMaster(verusBridgeMasterAddress);

        // when contract is launching/upgrading copy in to global bool pool available.
        if(verusNotarizerStorage.poolAvailable(VerusConstants.VerusBridgeAddress) > 0 )
            poolAvailable = true;

        for(uint i =0; i < _notaries.length; i++){
            notaryAddressMapping[_notaries[i]] = VerusObjects.notarizer(_notariesEthAddress[i], _notariesColdStoreEthAddress[i], VerusConstants.NOTARY_VALID);
            notaries.push(_notaries[i]);
        }
        lastForkIndex  = -1;
    }

    function setContract(address contractAddress) public {

        require(msg.sender == upgradeContract);

        verusSerializer = VerusSerializer(contractAddress);

    }
          
    function currentNotariesRequired() public view returns(uint8){

        return uint8((notaries.length/2) + 1);

    }
 
    function setLatestData(VerusObjectsNotarization.CPBaaSNotarization memory _pbaasNotarization, bytes memory data
        ) public returns(bool output) {

       ( uint8[] memory _vs,
        bytes32[] memory _rs,
        bytes32[] memory _ss,
        uint32[] memory blockheights,
        address[] memory notaryAddresses) = abi.decode(data,(uint8[],bytes32[], bytes32[],uint32[],address[]));

        bytes32 hashedNotarization;
        bytes memory serializedNotarisation = verusSerializer.serializeCPBaaSNotarization(_pbaasNotarization);

        // Notarizations are keyed by blake2b hash of notarization
        hashedNotarization = verusSerializer.blake2bDefault(serializedNotarisation);

        require(!verusNotarizerStorage.notarizationHashes(hashedNotarization));

        bytes32 hashedNotarizationByID;
        uint validSignatures;

        checkunique(notaryAddresses);

        for(uint i = 0; i < notaryAddresses.length; i++)
        {
            // hash the notarizations with the vdxf key, system, height & NotaryID
            hashedNotarizationByID = keccak256(abi.encodePacked(uint8(1),
                vdxfcode,
                VerusConstants.VerusSystemId,
                verusSerializer.serializeUint32(blockheights[i]),
                notaryAddresses[i],
                abi.encodePacked(keccak256(serializedNotarisation))));

            if (recoverSigner(hashedNotarizationByID, _vs[i]-4, _rs[i], _ss[i]) != notaryAddressMapping[notaryAddresses[i]].main || sigCheck[notaryAddresses[i]] != i)
            {
                revert("Invalid notary signature");  
            }
            if (notaryAddressMapping[notaryAddresses[i]].state != VerusConstants.NOTARY_VALID)
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
        for(uint k= 0; k < _pbaasNotarization.currencystates.length && !poolAvailable; k++)
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
        
        int forkIdx = -1;
        int forkPos;
        
        for (int i = 0; i < int(amountsOfForks) ; i++) 
        {
            for (int j = int(notarizationLength[uint256(i)]) - 1; j >= 0; j--)
            {
                if (_pbaasNotarization.hashprevnotarization == reversebytes32(bestForks[uint(i)][uint(j)].hashOfNotarization))
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

        if (forkIdx == -1 && amountsOfForks != 0)
        {
            revert("invalid notarization hash");
        }
        lastForkIndex++;
                  
        if (forkIdx == -1){
            forkIdx = 0;
            amountsOfForks = 1;
        }
        
        if (forkIdx >= 0 && forkPos != int(notarizationLength[uint(forkIdx)]) - 1 && lastForkIndex > 0)  
        {
            notarizationLength[uint32(amountsOfForks)]++;
            bestForks[uint32(amountsOfForks)][0] = (bestForks[uint(forkIdx)][uint(forkPos)]);
            forkIdx = amountsOfForks;
            amountsOfForks++;
        }

        notarizationLength[uint256(forkIdx)]++;
        bestForks[uint256(forkIdx)][uint32(notarizationLength[uint256(forkIdx)] - 1)] = 
            VerusObjectsNotarization.NotarizationForks(reversebytes32(hashedNotarization), stateRoot, 
            _pbaasNotarization.txid, _pbaasNotarization.notarizationheight, uint32(lastForkIndex));
      
        //prune if poss
                for (int i = 0; i < int(amountsOfForks); i++) 
        {
            int chainCounter;
            for (int j = int(notarizationLength[uint256(i)]) - 1; j > 0; j--)
            {
                if ((bestForks[uint(i)][uint(j - 1)].forkIndex + 1) == bestForks[uint(i)][uint(j)].forkIndex)
                {
                    chainCounter++;

                    if (chainCounter >= 2)
                    {
                        VerusObjectsNotarization.NotarizationForks[] memory tempProof = new VerusObjectsNotarization.NotarizationForks[](2);
                        tempProof[0] = bestForks[uint(i)][uint32(notarizationLength[uint(i)]) - 2];
                        tempProof[0].forkIndex = 0;
                        tempProof[1] = bestForks[uint(i)][uint32(notarizationLength[uint(i)]) - 1];
                        tempProof[1].forkIndex = 1;
                        delete bestForks;
                        bestForks[0][0] = tempProof[0];
                        bestForks[0][1] = tempProof[1];
                        lastForkIndex = 1;
                        amountsOfForks = 1;
                        delete notarizationLength;
                        notarizationLength[0] = 2;
                        break;
                    }
                }
                else 
                {
                    chainCounter = 0;
                }
            }
            if (amountsOfForks == 1)
                break;
        } 
        
    }

    function getVRSCStateRoot(VerusObjectsNotarization.CProofRoot[] memory proofroots) private pure returns (bytes32) {

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

    function recoverSigner(bytes32 _h, uint8 _v, bytes32 _r, bytes32 _s) private pure returns (address) {

        return ecrecover(_h, _v, _r, _s);
    }

    function getBestStateroot() public view returns (bytes32)
    {
        return bestForks[0][0].stateRoot;
    }

    function setClaimableFees(address _feeRecipient, uint256 _ethAmount, address bridgekeeper) public returns (uint256){

        require(msg.sender == address(verusBridgeMaster)); 
        
        uint256 notaryFees;
        uint256 LPFees;
        uint256 exporterFees;
        uint256 proposerFees;  
        uint256 bridgekeeperFees;              

        address proposer;
        bytes memory proposerBytes = verusNotarizerStorage.getNotarization(bestForks[0][0].hashOfNotarization).proposer.destinationaddress;

        assembly {
                proposer := mload(add(proposerBytes,20))
        } 

        notaryFees = (_ethAmount / 10 ) * 3 ; 

        exporterFees = _ethAmount / 10 ;
        proposerFees = _ethAmount / 10 ;
        bridgekeeperFees = (_ethAmount / 10 ) * 3 ;

        LPFees = _ethAmount - (notaryFees + exporterFees + proposerFees + bridgekeeperFees);

        setNotaryFees(notaryFees);
        verusBridgeMaster.setClaimedFees(_feeRecipient, exporterFees);
        verusBridgeMaster.setClaimedFees(proposer, proposerFees);
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

    function reversebytes32(bytes32 input) private pure returns (bytes32) {

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
