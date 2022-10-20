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
        
    uint8 constant FLAG_FRACTIONAL = 1;
    uint8 constant FLAG_REFUNDING = 4;
    uint8 constant FLAG_LAUNCHCONFIRMED = 0x10;
    uint8 constant FLAG_LAUNCHCOMPLETEMARKER = 0x20;
    // notarization vdxf key
    bytes20 constant vdxfcode = bytes20(0x367Eaadd291E1976ABc446A143f83c2D4D2C5a84);

    VerusSerializer verusSerializer;
    VerusNotarizerStorage verusNotarizerStorage;
    VerusBridgeMaster verusBridgeMaster;
    address upgradeContract;

    // list of all notarizers mapped to allow for quick searching
    mapping (address => VerusObjects.notarizer ) public notaryAddressMapping;
    mapping (address => uint) sigCheck;

    address[] public notaries;

    bool public poolAvailable;
    bytes[] public bestForks;
    int32 lastForkIndex = -1;
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
          
    function currentNotariesLength() public view returns(uint8){

        return uint8(notaries.length);

    }
 
    function setLatestData(VerusObjectsNotarization.CPBaaSNotarization memory _pbaasNotarization, bytes memory data
        ) public returns(bool output) {

       ( uint8[] memory _vs,
        bytes32[] memory _rs,
        bytes32[] memory _ss,
        uint32[] memory blockheights,
        address[] memory notaryAddresses) = abi.decode(data,(uint8[],bytes32[], bytes32[],uint32[],address[]));

        bytes32 hashedNotarization;
        bytes32 keccakNotarizationHash;
        bytes32 txidHash;
        
        txidHash = keccak256(abi.encodePacked(reversebytes32(_pbaasNotarization.txid.hash), verusSerializer.serializeUint32(_pbaasNotarization.txid.n)));

        // Notarizations are keyed by blake2b hash of notarization
        (hashedNotarization, keccakNotarizationHash) = verusSerializer.returnNotarizationHashes(_pbaasNotarization);

        uint validSignatures;

        checkunique(notaryAddresses);

        for(uint i = 0; i < notaryAddresses.length; i++)
        {
            bytes32 hashedNotarizationByID;
            // hash the notarizations with the vdxf key, system, height & NotaryID
            hashedNotarizationByID = keccak256(
                abi.encodePacked(
                    uint8(1),
                    vdxfcode,
                    uint8(1),
                    txidHash,
                    VerusConstants.VerusSystemId,
                    verusSerializer.serializeUint32(blockheights[i]),
                    notaryAddresses[i], 
                    keccakNotarizationHash));

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

        if(validSignatures < ((notaries.length >> 1) + 1 ))
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

     function decodeNotarization(uint index) private view returns (VerusObjectsNotarization.NotarizationForks[] memory)
        {
            uint32 nextOffset;

            bytes storage tempArray = bestForks[index];

            bytes32 hashOfNotarization;
            bytes32 txid;
            uint32 txidvout;
            uint32 height;
            uint192 forkIndex;
            bytes32 slotHash;
            VerusObjectsNotarization.NotarizationForks[] memory retval = new VerusObjectsNotarization.NotarizationForks[]((tempArray.length / 96) + 1);
            if (tempArray.length > 1)
            {
                assembly {
                            slotHash := keccak256(add(tempArray.slot, 32), 32)
                         }

                for (int i = 0; i < int(tempArray.length / 128); i++) 
                {
                    assembly {
                        hashOfNotarization := sload(add(slotHash,nextOffset))
                        nextOffset := add(nextOffset, 1)  
                        txid := sload(add(slotHash,nextOffset))
                        nextOffset := add(nextOffset, 1)  
                        txidvout := shr(224,sload(add(slotHash,nextOffset)))
                        height := shr(192,sload(add(slotHash,nextOffset)))
                        forkIndex := sload(add(slotHash,nextOffset))
                        nextOffset := add(nextOffset, 1)
                    }
                    retval[uint(i)] =  VerusObjectsNotarization.NotarizationForks(hashOfNotarization, txid, txidvout, height, forkIndex);
                }
            }
            return retval;
        }

    function encodeNotarization(uint index, VerusObjectsNotarization.NotarizationForks memory notarizations)private  {

        if (bestForks.length < index + 1)
        {
            bestForks.push("");  //initialize empty bytes array
        }

        bestForks[index] = abi.encodePacked(bestForks[index],notarizations.hashOfNotarization, 
                                            notarizations.txid,
                                            notarizations.n,
                                            notarizations.height,
                                            notarizations.forkIndex);
    }

    function encodeStandardNotarization(VerusObjectsNotarization.NotarizationForks[] memory notarizations)private  {

        
        bestForks[0] = abi.encodePacked(notarizations[1].hashOfNotarization, 
                                            notarizations[1].txid,
                                            notarizations[1].n,
                                            notarizations[1].height,
                                            notarizations[1].forkIndex,
                                            notarizations[2].hashOfNotarization, 
                                            notarizations[2].txid,
                                            notarizations[2].n,
                                            notarizations[2].height,
                                            notarizations[2].forkIndex);

    }

    function setNotarizationProofRoot(VerusObjectsNotarization.CPBaaSNotarization memory _pbaasNotarization, bytes32 hashedNotarization) private 
    {
        
        int forkIdx = -1;
        int forkPos;
        
        VerusObjectsNotarization.NotarizationForks[] memory notarizations;   
        for (int i = 0; i < int(bestForks.length) ; i++) 
        {
            notarizations =  decodeNotarization(uint(i));
            for (int j = int(notarizations.length) - 2; j >= 0; j--)
            {
                if (_pbaasNotarization.hashprevnotarization == notarizations[uint(j)].hashOfNotarization ||
                    _pbaasNotarization.prevnotarization.hash == notarizations[uint(j)].txid)
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

        if (forkIdx == -1 && bestForks.length != 0)
        {
            revert("invalid notarization hash");
        }
        lastForkIndex++;

        if (forkIdx == -1){
            forkIdx = 0;
        }
        
        if (forkPos != int(notarizations.length) - 2 && lastForkIndex > 0)  
        {
            forkIdx = int(bestForks.length);
            encodeNotarization(uint(forkIdx), notarizations[uint(forkPos)]);
        }

        if(forkIdx == 0 && forkPos == 1)
        {
            notarizations[notarizations.length - 1] = VerusObjectsNotarization.NotarizationForks(reversebytes32(hashedNotarization), 
            _pbaasNotarization.txid.hash, _pbaasNotarization.txid.n, _pbaasNotarization.notarizationheight, uint32(lastForkIndex));

        }
        else{

        encodeNotarization(uint(forkIdx), VerusObjectsNotarization.NotarizationForks(reversebytes32(hashedNotarization),
            _pbaasNotarization.txid.hash, _pbaasNotarization.txid.n, _pbaasNotarization.notarizationheight, uint32(lastForkIndex)));

        }
      
        for (int i = 0; i < int(bestForks.length); i++) 
        {
            if(forkIdx != 0 && forkPos != 1 )
                notarizations = decodeNotarization(uint(i));
            if (notarizations.length > 2)
            {
                notarizations[1].forkIndex = 0;
                notarizations[2].forkIndex = 1;
                if (bestForks.length != 1)
                {
                    delete bestForks;
                    bestForks.push("");
                }
                encodeStandardNotarization(notarizations);
                lastForkIndex = 1;
                break;
            }
        } 
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

    function getLastConfirmedNotarizationHash() public view returns (bytes32)
    {
        bytes memory input = bestForks[0];
        bytes32 hashOfNotarization;

        if (input.length > 0)
        {
            assembly {
                        hashOfNotarization := mload(add(input, 32))
            }
        }
        return reversebytes32(hashOfNotarization);
    }

    function getBestStateRoot() public view returns (bytes32)
    {
            return getVRSCStateRoot(verusNotarizerStorage.getNotarization(getLastConfirmedNotarizationHash()).proofroots);
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
