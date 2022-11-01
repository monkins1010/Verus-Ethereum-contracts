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

        require(msg.sender == address(verusBridgeMaster), "SLD");

       ( uint8[] memory _vs,
        bytes32[] memory _rs,
        bytes32[] memory _ss,
        uint32[] memory blockheights,
        address[] memory notaryAddresses) = abi.decode(data,(uint8[],bytes32[], bytes32[],uint32[],address[]));

        bytes32 keccakNotarizationHash;
        bytes32 txidHash;
        
        txidHash = keccak256(abi.encodePacked(txid, verusSerializer.serializeUint32(n)));

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
        
        (bytes32 launchedAndProposer, bytes32 prevnotarizationtxid, bytes32 hashprevnotarization, bytes32 stateRoot) = notarizationSerializer.deserilizeNotarization(serializedNotarization);

        if (!poolAvailable && ((uint256(launchedAndProposer >> 176) & 0xff) == 1)) { //shift to read if bridge launched in packed uint256
            verusNotarizerStorage.setPoolAvailable();
            poolAvailable = true;
            verusBridgeMaster.sendVRSC();
        }

        setNotarizationProofRoot(blakeNotarizationHash, hashprevnotarization, txid, n, prevnotarizationtxid, launchedAndProposer, stateRoot);

        emit NewNotarization(blakeNotarizationHash);

    }

    function decodeNotarization(uint index) public view returns (VerusObjectsNotarization.NotarizationForks[] memory)
        {
            uint32 nextOffset;

            bytes storage tempArray = bestForks[index];

            bytes32 hashOfNotarization;
            bytes32 txid;
            bytes32 stateRoot;
            bytes32 packedPositions;
           // uint32 forkIndex;
            bytes32 slotHash;
            VerusObjectsNotarization.NotarizationForks[] memory retval = new VerusObjectsNotarization.NotarizationForks[]((tempArray.length / 128) + 1);
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
                        stateRoot := sload(add(slotHash,nextOffset))
                        nextOffset := add(nextOffset, 1) 
                        packedPositions :=sload(add(slotHash,nextOffset))
                        nextOffset := add(nextOffset, 1)
                    }

                  //  forkIndex = (packedPositions >> 176) & 0xffffffff;

                    retval[uint(i)] =  VerusObjectsNotarization.NotarizationForks(hashOfNotarization, txid, stateRoot, packedPositions);
                }
            }
            return retval;
        }

    function encodeNotarization(uint index, VerusObjectsNotarization.NotarizationForks memory notarizations)private  {

        if (bestForks.length < index + 1)
        {
            bestForks.push("");  //initialize empty bytes array
        }

        bestForks[index] = abi.encodePacked(notarizations.hashOfNotarization, 
                                            notarizations.txid,
                                            notarizations.stateroot,
                                            notarizations.proposerPacked);
    }

    function encodeStandardNotarization(VerusObjectsNotarization.NotarizationForks memory firstNotarization, bytes memory secondNotarization)private  {
        
        bestForks[0] = abi.encodePacked(firstNotarization.hashOfNotarization, 
                                            firstNotarization.txid,
                                            firstNotarization.stateroot,
                                            firstNotarization.proposerPacked,
                                            secondNotarization);

    }

    function setNotarizationProofRoot(bytes32 hashedNotarization, 
            bytes32 hashprevnotarization, bytes32 txidHash, uint32 voutnum, bytes32 hashprevtxid, bytes32 proposer, bytes32 stateRoot) private 
    {
        
        int forkIdx = -1;
        int forkPos;
        
        VerusObjectsNotarization.NotarizationForks[] memory notarizations;   
        for (int i = 0; i < int(bestForks.length) ; i++) 
        {
            notarizations =  decodeNotarization(uint(i));
            // Notarization length alway +1 more as slot ready to be filled.
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
            encodeNotarization(uint(forkIdx), notarizations[uint(0)]);
        }

        proposer |= bytes32(uint256(voutnum) << 192);

        // If the position that is matched is the second stored one, then that becomes the new confirmed.
        if(forkPos == 1)
        {
            if (bestForks.length > 1)
            {
                delete bestForks;
                bestForks.push("");
            }
            
            //pack vout in at the end of the proposer 22 bytes ctransferdest
            encodeStandardNotarization(notarizations[1], abi.encode(hashedNotarization, 
                txidHash, stateRoot, proposer));
        }
        else
        {
            encodeNotarization(uint(forkIdx), VerusObjectsNotarization.NotarizationForks(hashedNotarization,
                txidHash, stateRoot, proposer));
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

    function getLastConfirmedVRSCStateRoot() public view returns (bytes32) {

        bytes32 stateRoot;
        bytes32 slotHash;
        bytes storage tempArray = bestForks[0];
        uint32 nextOffset;

        if (tempArray.length > 0)
        {
            assembly {
                        slotHash := keccak256(add(tempArray.slot, 32), 32)
                        nextOffset := add(nextOffset, 1)  
                        nextOffset := add(nextOffset, 1)  
                        stateRoot := sload(add(slotHash, nextOffset))
            }
        }

        return stateRoot;
    }

    function updateNotarizer(address notarizer, address mainAddress, address revokeAddress, uint8 state) public
    {
        require(msg.sender == upgradeContract);
        notaryAddressMapping[notarizer] = VerusObjects.notarizer(mainAddress, revokeAddress, state);

    }

    function getNotaryETHAddress(uint number) public view returns (address)
    {
        return notaryAddressMapping[notaries[number]].main;

    }



}
