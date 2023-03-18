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
import "../MMR/VerusBlake2b.sol";
import "../VerusBridge/UpgradeManager.sol";

contract VerusNotarizer {
        
    uint8 constant FLAG_FRACTIONAL = 1;
    uint8 constant FLAG_REFUNDING = 4;
    uint8 constant FLAG_LAUNCHCONFIRMED = 0x10;
    uint8 constant FLAG_LAUNCHCOMPLETEMARKER = 0x20;
    uint8 constant OFFSET_FOR_HEIGHT = 224;
    uint8 constant TYPE_REVOKE = 2;
    uint8 constant TYPE_RECOVER = 3;
    uint8 constant NUM_ADDRESSES_FOR_REVOKE = 2;
    uint8 constant COMPLETE = 2;
    uint8 constant ERROR = 4;


    // notarization vdxf key
    bytes20 constant vdxfcode = bytes20(0x367Eaadd291E1976ABc446A143f83c2D4D2C5a84);

    VerusSerializer verusSerializer;
    VerusNotarizerStorage verusNotarizerStorage;
    VerusBridgeMaster verusBridgeMaster;
    NotarizationSerializer notarizationSerializer;
    UpgradeManager verusUpgradeContract;

    // list of all notarizers mapped to allow for quick searching
    mapping (address => VerusObjects.notarizer ) public notaryAddressMapping;
    mapping (bytes32 => bool) knownNotarizationTxids;

    address[] public notaries;

    bool public poolAvailable;
    bytes[] public bestForks;
    // Notifies when a new block hash is published
    event NewNotarization (bytes32);
    using VerusBlake2b for bytes;

    constructor(address _verusSerializerAddress, address upgradeContractAddress, 
        address[] memory _notaries, address[] memory _notariesEthAddress, address[] memory _notariesColdStoreEthAddress, 
        address verusNotarizerStorageAddress, address verusBridgeMasterAddress, address notarizationSerializerAddress) {
            verusSerializer = VerusSerializer(_verusSerializerAddress);
            verusUpgradeContract = UpgradeManager(upgradeContractAddress);
            verusNotarizerStorage = VerusNotarizerStorage(verusNotarizerStorageAddress); 
            verusBridgeMaster = VerusBridgeMaster(payable(verusBridgeMasterAddress));
            notarizationSerializer = NotarizationSerializer(notarizationSerializerAddress);

            // when contract is launching/upgrading copy in to global bool pool available.
            if(verusNotarizerStorage.poolAvailable(VerusConstants.VerusBridgeAddress) > 0 )
                poolAvailable = true;

            for(uint i =0; i < _notaries.length; i++){
                notaryAddressMapping[_notaries[i]] = VerusObjects.notarizer(_notariesEthAddress[i], _notariesColdStoreEthAddress[i], VerusConstants.NOTARY_VALID);
                notaries.push(_notaries[i]);
            }
    }

    function setContracts(address[13] memory contracts) public {

        require(msg.sender == address(verusUpgradeContract));

        if(contracts[uint(VerusConstants.ContractType.NotarizationSerializer)] != address(notarizationSerializer)) {
            notarizationSerializer = NotarizationSerializer(contracts[uint(VerusConstants.ContractType.NotarizationSerializer)]);
        }
        
        if(contracts[uint(VerusConstants.ContractType.VerusSerializer)] != address(verusSerializer)) {
            verusSerializer = VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]);
        }
        
        if(contracts[uint(VerusConstants.ContractType.VerusBridgeMaster)] != address(verusBridgeMaster))     
            verusBridgeMaster = VerusBridgeMaster(payable(contracts[uint(VerusConstants.ContractType.VerusBridgeMaster)]));

    }
          
    function currentNotariesLength() public view returns(uint8){

        return uint8(notaries.length);

    }
 
    function setLatestData(bytes calldata serializedNotarization, bytes32 txid, uint32 n, bytes calldata data
        ) external {

        require(!knownNotarizationTxids[txid], "known TXID");
        knownNotarizationTxids[txid] = true;

        (uint8[] memory _vs,
        bytes32[] memory _rs,
        bytes32[] memory _ss,
        uint32[] memory blockheights,
        address[] memory notaryAddresses) = abi.decode(data,(uint8[],bytes32[], bytes32[],uint32[],address[]));

        bytes32 keccakNotarizationHash;
        bytes32 txidHash;
        
        txidHash = keccak256(abi.encodePacked(txid, verusSerializer.serializeUint32(n)));

        keccakNotarizationHash = keccak256(serializedNotarization);

        checkunique(notaryAddresses);
        uint i;

        for(; i < notaryAddresses.length; i++)
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

            if (ecrecover(hashedNotarizationByID, _vs[i]-4, _rs[i], _ss[i]) != notaryAddressMapping[notaryAddresses[i]].main)
            {
                revert("Invalid notary signature");  
            }
            if (notaryAddressMapping[notaryAddresses[i]].state != VerusConstants.NOTARY_VALID)
            {
                revert("Notary revoked"); 
            }
        }

        if(i < ((notaries.length >> 1) + 1 ))
        {
            revert("not enough notary signatures");
        }

        checkNotarization(serializedNotarization, txid, uint64(n));

    }

    function checkNotarization(bytes calldata serializedNotarization, bytes32 txid, uint64 voutAndHeight ) private {

    
        bytes32 blakeNotarizationHash;

        blakeNotarizationHash = serializedNotarization.createHash();
        
        (bytes32 launchedAndProposer, bytes32 prevnotarizationtxid, bytes32 hashprevnotarization, bytes32 stateRoot, bytes32 blockHash, 
                uint32 verusProofheight) = notarizationSerializer.deserilizeNotarization(serializedNotarization);

        verusNotarizerStorage.pushNewProof(abi.encode(stateRoot, blockHash), verusProofheight);

        if (!poolAvailable && (((uint256(launchedAndProposer) >> 176) & 0xff) == 1)) { //shift to read if bridge launched in packed uint256
            verusNotarizerStorage.setPoolAvailable();
            poolAvailable = true;
            verusBridgeMaster.sendVRSC();
        }

        voutAndHeight |= uint64(verusProofheight) << 32;
        launchedAndProposer |= bytes32(uint256(voutAndHeight) << 192); //also pack in the voutnum

        setNotarizationProofRoot(blakeNotarizationHash, hashprevnotarization, txid, prevnotarizationtxid, launchedAndProposer, stateRoot);

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
            bytes32 slotHash;
            VerusObjectsNotarization.NotarizationForks[] memory retval = new VerusObjectsNotarization.NotarizationForks[]((tempArray.length / 128) + 1);
            if (tempArray.length > 1)
            {
                bytes32 slot;
                assembly {
                            mstore(add(slot, 32),tempArray.slot)
                            slotHash := keccak256(add(slot, 32), 32)
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

        bestForks[index] = abi.encodePacked(bestForks[index], notarizations.hashOfNotarization, 
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
            bytes32 hashprevnotarization, bytes32 txidHash, bytes32 hashprevtxid, bytes32 proposer, bytes32 stateRoot) private 
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

    function checkunique(address[] memory ids) private pure
    {

        for (uint i = 0; i < ids.length - 1; i++)
        {
                for (uint j = i + 1; j < ids.length; j++)
                {
                    if (ids[i] == ids[j])
                        revert("duplicate signatures found");
                }
        }
    }

    function getLastConfirmedVRSCStateRoot() public view returns (bytes32) {

        bytes32 stateRoot;
        bytes32 slotHash;
        bytes storage tempArray = bestForks[0];
        uint32 nextOffset;

        if (tempArray.length > 0)
        {
            bytes32 slot;
            assembly {
                        mstore(add(slot, 32),tempArray.slot)
                        slotHash := keccak256(add(slot, 32), 32)
                        nextOffset := add(nextOffset, 1)  
                        nextOffset := add(nextOffset, 1)  
                        stateRoot := sload(add(slotHash, nextOffset))
            }
        }

        return stateRoot;
    }

    function updateNotarizer(address notarizer, address mainAddress, address revokeAddress, uint8 state) private
    {
        notaryAddressMapping[notarizer] = VerusObjects.notarizer(mainAddress, revokeAddress, state);
    }

    function getNotaryETHAddress(uint number) public view returns (address)
    {
        return notaryAddressMapping[notaries[number]].main;

    }

    function getNewProofs (bytes32 height) public view returns (bytes memory) {
        
        require(msg.sender == address(verusBridgeMaster));

        return verusNotarizerStorage.getProof(bytes32(height >> OFFSET_FOR_HEIGHT));

    }

    function getProof(uint height) public view returns (bytes memory) {

        require(msg.sender == address(verusBridgeMaster));
        
        VerusObjectsNotarization.NotarizationForks[] memory latestForks;

        latestForks = decodeNotarization(0);

        require(height < uint256(latestForks[0].proposerPacked >> OFFSET_FOR_HEIGHT), "Latest proofs require paid service");

        return verusNotarizerStorage.getProof(bytes32(height));
    }

    function getProofCosts(bool latest) public pure returns (uint256) {

        return latest ? (0.0125 ether) : (0.00625 ether);
    }

     function recoverString(bytes memory be, uint8 vs, bytes32 rs, bytes32 ss) public view returns (address)
    {
        bytes32 hashValue;

        hashValue = sha256(abi.encodePacked(verusSerializer.writeCompactSize(be.length),be));
        hashValue = sha256(abi.encodePacked(uint8(19),hex"5665727573207369676e656420646174613a0a", hashValue)); // prefix = 19(len) + "Verus signed data:\n"

        return ecrecover(hashValue, vs - 4, rs, ss);

    }

    function revoke(VerusObjects.revokeInfo memory _revokePacket) public returns (bool) {

        bytes memory be; 

        require(verusUpgradeContract.saltsUsed(_revokePacket.salt) == false, "salt Already used");
        verusUpgradeContract.setSaltsUsed(_revokePacket.salt);

        be = bytesToString(abi.encodePacked(uint8(TYPE_REVOKE), _revokePacket.salt));

        address signer = recoverString(be, _revokePacket._vs, _revokePacket._rs, _revokePacket._ss);

        if (notaryAddressMapping[_revokePacket.notaryID].main != signer || notaryAddressMapping[_revokePacket.notaryID].state == VerusConstants.NOTARY_REVOKED)
        {
            return false;  
        }

        updateNotarizer(_revokePacket.notaryID, address(0), notaryAddressMapping[_revokePacket.notaryID].recovery, VerusConstants.NOTARY_REVOKED);

        return true;
    }

    function recover(VerusObjects.upgradeInfo memory _newContractPackage) public returns (uint8) {

        bytes memory be; 

        require(verusUpgradeContract.saltsUsed(_newContractPackage.salt) == false, "salt Already used");
        verusUpgradeContract.setSaltsUsed(_newContractPackage.salt);
        
        require(_newContractPackage.contracts.length == NUM_ADDRESSES_FOR_REVOKE, "Input Identities wrong length");
        require(_newContractPackage.upgradeType == TYPE_RECOVER, "Wrong type of package");
        
        be = bytesToString(abi.encodePacked(_newContractPackage.contracts[0],_newContractPackage.contracts[1], uint8(_newContractPackage.upgradeType), _newContractPackage.salt));

        address signer = recoverString(be, _newContractPackage._vs, _newContractPackage._rs, _newContractPackage._ss);

        if (signer != notaryAddressMapping[_newContractPackage.notarizerID].recovery)
        {
            return ERROR;  
        }
        updateNotarizer(_newContractPackage.notarizerID, _newContractPackage.contracts[0], 
                                       _newContractPackage.contracts[1], VerusConstants.NOTARY_VALID);

        return COMPLETE;
    }
    
    function bytesToString (bytes memory input) private pure returns (bytes memory output)
    {
        bytes memory _string = new bytes(input.length * 2);
        bytes memory HEX = "0123456789abcdef";

        for(uint i = 0; i < input.length; i++) 
        {
            _string[i*2] = HEX[uint8(input[i] >> 4)];
            _string[1+i*2] = HEX[uint8(input[i] & 0x0f)];
        }
        return _string;
    }

}
