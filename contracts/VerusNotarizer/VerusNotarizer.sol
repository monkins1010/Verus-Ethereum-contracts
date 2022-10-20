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
import "./NotarizationSerializer.sol";

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
    NotarizationSerializer notarizationSerializer;
    address upgradeContract;

    // list of all notarizers mapped to allow for quick searching
    mapping (address => VerusObjects.notarizer ) public notaryAddressMapping;
    mapping (address => uint) sigCheck;

    address[] public notaries;

    bool public poolAvailable;
    bytes[] public bestForks;
    // Notifies when a new block hash is published
    event NewNotarization (bytes32);

    constructor(address _verusSerializerAddress, address upgradeContractAddress, 
    address[] memory _notaries, address[] memory _notariesEthAddress, address[] memory _notariesColdStoreEthAddress, 
    address verusNotarizerStorageAddress, address verusBridgeMasterAddress, address notarizationSerializerAddress) {
        verusSerializer = VerusSerializer(_verusSerializerAddress);
        upgradeContract = upgradeContractAddress;
        verusNotarizerStorage = VerusNotarizerStorage(verusNotarizerStorageAddress); 
        verusBridgeMaster = VerusBridgeMaster(verusBridgeMasterAddress);
        notarizationSerializer = NotarizationSerializer(notarizationSerializerAddress);

        // when contract is launching/upgrading copy in to global bool pool available.
        if(verusNotarizerStorage.poolAvailable(VerusConstants.VerusBridgeAddress) > 0 )
            poolAvailable = true;

        for(uint i =0; i < _notaries.length; i++){
            notaryAddressMapping[_notaries[i]] = VerusObjects.notarizer(_notariesEthAddress[i], _notariesColdStoreEthAddress[i], VerusConstants.NOTARY_VALID);
            notaries.push(_notaries[i]);
        }
    }

    function setContract(address serializerAddress, address notarizationSerializerAddress) public {

        require(msg.sender == upgradeContract);

        verusSerializer = VerusSerializer(serializerAddress);
        notarizationSerializer = NotarizationSerializer(notarizationSerializerAddress);

    }
          
    function currentNotariesLength() public view returns(uint8){

        return uint8(notaries.length);

    }
 
    function setLatestData(bytes calldata serializedNotarization, bytes32 txid, uint32 n, bytes calldata data
        ) public returns(bool) {

       ( uint8[] memory _vs,
        bytes32[] memory _rs,
        bytes32[] memory _ss,
        uint32[] memory blockheights,
        address[] memory notaryAddresses) = abi.decode(data,(uint8[],bytes32[], bytes32[],uint32[],address[]));

        bytes32 keccakNotarizationHash;
        bytes32 txidHash;
        
        txidHash = keccak256(abi.encodePacked(reversebytes32(txid), verusSerializer.serializeUint32(n)));

        keccakNotarizationHash = keccak256(serializedNotarization);

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

        return true;        

    }

    function checkNotarization(bytes calldata serializedNotarization, bytes32 txid, uint32 n ) public {

        require(msg.sender == address(verusBridgeMaster), "WS");
       
        bytes32 blakeNotarizationHash;

        blakeNotarizationHash = verusSerializer.notarizationBlakeHash(serializedNotarization);
        
        (uint64 packedPositions, bytes32 prevnotarizationtxid, bytes32 hashprevnotarization) = notarizationSerializer.deserilizeNotarization(serializedNotarization);

        if (!poolAvailable && (((packedPositions >> 16) & 0xff) == 1)) { //shift 2 bytes to read if bridge launched in packed uint64
            verusNotarizerStorage.setPoolAvailable();
            poolAvailable = true;
            verusBridgeMaster.sendVRSC();
        }

        verusNotarizerStorage.setNotarization(serializedNotarization);
        setNotarizationProofRoot(serializedNotarization, blakeNotarizationHash, hashprevnotarization, txid, n, prevnotarizationtxid, packedPositions);

        emit NewNotarization(blakeNotarizationHash);

    }

    function decodeNotarization(uint index) public view returns (VerusObjectsNotarization.NotarizationForks[] memory)
        {
            uint32 nextOffset;

            bytes storage tempArray = bestForks[index];

            bytes32 hashOfNotarization;
            bytes32 txid;
            uint32 txidvout;
            uint64 packedPositions;
            uint160 forkIndex;
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
                        packedPositions := shr(160,sload(add(slotHash,nextOffset)))
                        forkIndex := sload(add(slotHash,nextOffset))
                        nextOffset := add(nextOffset, 1)
                    }
                    retval[uint(i)] =  VerusObjectsNotarization.NotarizationForks(hashOfNotarization, txid, txidvout, packedPositions, forkIndex);
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
                                            notarizations.proposerPosition,
                                            notarizations.forkIndex);
    }

    function encodeStandardNotarization(VerusObjectsNotarization.NotarizationForks[] memory notarizations)private  {
        
        bestForks[0] = abi.encodePacked(notarizations[1].hashOfNotarization, 
                                            notarizations[1].txid,
                                            notarizations[1].n,
                                            notarizations[1].proposerPosition,
                                            notarizations[1].forkIndex,
                                            notarizations[2].hashOfNotarization, 
                                            notarizations[2].txid,
                                            notarizations[2].n,
                                            notarizations[2].proposerPosition,
                                            notarizations[2].forkIndex);

    }

    function setNotarizationProofRoot(bytes memory serializedNotarization, bytes32 hashedNotarization, 
            bytes32 hashprevnotarization, bytes32 txidHash, uint32 voutnum, bytes32 hashprevtxid, uint64 proposerPosition) private 
    {
        
        int forkIdx = -1;
        int forkPos;
        
        VerusObjectsNotarization.NotarizationForks[] memory notarizations;   
        for (int i = 0; i < int(bestForks.length) ; i++) 
        {
            notarizations =  decodeNotarization(uint(i));
            for (int j = int(notarizations.length) - 2; j >= 0; j--)
            {
                if (hashprevnotarization == notarizations[uint(j)].hashOfNotarization ||
                        hashprevtxid == notarizations[uint(j)].txid)
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

        if (forkIdx == -1){
            forkIdx = 0;
        }
        
        if (forkPos != int(notarizations.length) - 2 && bestForks.length != 0)  
        {
            forkIdx = int(bestForks.length);
            encodeNotarization(uint(forkIdx), notarizations[uint(forkPos)]);
        }

        if(forkIdx == 0 && forkPos == 1)
        {
            notarizations[notarizations.length - 1] = VerusObjectsNotarization.NotarizationForks(reversebytes32(hashedNotarization), 
            txidHash, voutnum, proposerPosition, uint32(verusNotarizerStorage.nextNotarizationIndex()));

        }
        else{

        encodeNotarization(uint(forkIdx), VerusObjectsNotarization.NotarizationForks(reversebytes32(hashedNotarization),
            txidHash, voutnum, proposerPosition, uint32(verusNotarizerStorage.nextNotarizationIndex())));

        }
     
        for (int i = 0; i < int(bestForks.length); i++) 
        {
            if(forkIdx != 0 && forkPos != 1 )
                notarizations = decodeNotarization(uint(i));
            if (notarizations.length > 2)
            {
                verusNotarizerStorage.resetNotarization(serializedNotarization, notarizations[1].forkIndex);
                notarizations[1].forkIndex = 0;
                notarizations[2].forkIndex = 1;
                if (bestForks.length != 1)
                {
                    delete bestForks;
                    bestForks.push("");
                }
                encodeStandardNotarization(notarizations);
                return;
            }
        } 
        verusNotarizerStorage.setNotarization(serializedNotarization);
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

    function getLastConfirmedVRSCStateRoot() public view returns (bytes32) {

        bytes32 stateRoot;
        uint64 packedPositions;
        bytes32 slotHash;
        bytes storage tempArray = bestForks[0];
        uint32 nextOffset;

        if (tempArray.length > 0)
        {
            assembly {
                        slotHash := keccak256(add(tempArray.slot, 32), 32)
                        nextOffset := add(nextOffset, 1)  
                        nextOffset := add(nextOffset, 1)  
                        packedPositions := shr(160,sload(add(slotHash,nextOffset)))
            }
        }
        stateRoot = verusNotarizerStorage.getLastStateRoot(packedPositions >> 32);

        return stateRoot;
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
