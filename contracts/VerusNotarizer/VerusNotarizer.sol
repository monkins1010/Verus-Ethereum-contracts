// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.8.9;
pragma abicoder v2;

import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "./NotarizationSerializer.sol";
import "../MMR/VerusBlake2b.sol";
import "../VerusBridge/UpgradeManager.sol";
import "../Storage/StorageMaster.sol";

contract VerusNotarizer is VerusStorage {
        
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
    uint32 constant CONFIRMED_PROPOSER = 128;
    uint32 constant PROOF_HEIGHT_LOCATION = 68;


    // notarization vdxf key
    bytes20 constant vdxfcode = bytes20(0x367Eaadd291E1976ABc446A143f83c2D4D2C5a84);
    event NewNotarization (bytes32);
    using VerusBlake2b for bytes;
    
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
        
        txidHash = keccak256(abi.encodePacked(txid, serializeUint32(n)));

        keccakNotarizationHash = keccak256(serializedNotarization);

        uint i;

        for(; i < notaryAddresses.length; i++)
        {
            if (i < (notaryAddresses.length - 1)) {
                checkunique(notaryAddresses, i);
            }
            
            bytes32 hashedNotarizationByID;
            // hash the notarizations with the vdxf key, system, height & NotaryID
            hashedNotarizationByID = keccak256(
                abi.encodePacked(
                    uint8(1),
                    vdxfcode,
                    uint8(1),
                    txidHash,
                    VerusConstants.VerusSystemId,
                    serializeUint32(blockheights[i]),
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

        address notarizationSerializerAddress = contracts[uint(VerusConstants.ContractType.NotarizationSerializer)];

        (bool success, bytes memory returnBytes) = notarizationSerializerAddress.delegatecall(abi.encodeWithSignature("deserializeNotarization(bytes)", serializedNotarization));
        require(success);

        (bytes32 launchedAndProposer, bytes32 prevnotarizationtxid, bytes32 hashprevnotarization, bytes32 stateRoot, bytes32 blockHash, 
                uint32 verusProofheight) = abi.decode(returnBytes, (bytes32, bytes32, bytes32, bytes32, bytes32, uint32));

        // If the bridge is active and VRSC remaining has not been sent
        if (bridgeConverterActive && remainingLaunchFeeReserves != 0) { 
            
            address submitImportsAddress = contracts[uint(VerusConstants.ContractType.SubmitImports)];
            if (remainingLaunchFeeReserves > (VerusConstants.verusTransactionFee * 2)) {
                (bool success2,) = submitImportsAddress.delegatecall(abi.encodeWithSignature("sendToVRSC(uint64,address,uint8)", 0, address(0), VerusConstants.DEST_PKH));
                require(success2);
                remainingLaunchFeeReserves = 0;
            }
        }

        voutAndHeight |= uint64(verusProofheight) << 32; // pack two 32bit numbers into one uint64
        launchedAndProposer |= bytes32(uint256(voutAndHeight) << 192); // Also pack in the voutnum at the end of the uint256

        setNotarizationProofRoot(blakeNotarizationHash, hashprevnotarization, txid, prevnotarizationtxid, launchedAndProposer, stateRoot, blockHash);

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
            bytes32 hashprevnotarization, bytes32 txidHash, bytes32 hashprevtxid, bytes32 proposer, bytes32 stateRoot, bytes32 blockHash) private 
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

            proofs[bytes32(uint256(uint32(uint256(proposer >> 224))))] = abi.encodePacked(stateRoot, blockHash, uint32(uint256(notarizations[1].proposerPacked) >> 224));

            // Set bridge launched if confirmed notarization contains Bridge Launched bit packed on the end of proposer

            if (!bridgeConverterActive && ((uint256(notarizations[1].proposerPacked) >> VerusConstants.UINT176_BITS_SIZE) & 0xff) == 1) {
                    bridgeConverterActive = true;
                
            }
        }
        else
        {
            encodeNotarization(uint(forkIdx), VerusObjectsNotarization.NotarizationForks(hashedNotarization,
                txidHash, stateRoot, proposer));
        }
    }

    function checkunique(address[] memory ids, uint i) private pure
    {

        for (uint j = i + 1; j < ids.length; j++)
        {
            if (ids[i] == ids[j])
                revert("duplicate signatures found");
        }

    }

    function getProofCosts(uint256 proofOption) external pure returns (uint256) {
        uint256[3] memory feePrices = [uint256(0.01 ether),uint256(0.005 ether),uint256(0.0025 ether)];
        return feePrices[proofOption];
    }

    //users can pass in 0,1,2 to get the latest confirmed / priorconfirmed  / second prior confirmed statroot and blockhash.
    //otherwise if they enter a height the proof is free.
    // returned value is uint32 height bytes32 blockhash and bytes32 stateroot serialized together. 
    function getProof(uint256 proofHeightOptions) public payable returns (bytes memory) {

        uint256 feePrice;
        uint256 feeShare;
        uint256 remainder;

        // Price for proofs being returned.
        uint256[3] memory feePrices = [uint256(0.01 ether),uint256(0.005 ether),uint256(0.0025 ether)];

        uint256 proposerAndHeight;
        bytes memory tempBytes = bestForks[0];

        assembly {
            proposerAndHeight := mload(add(tempBytes, CONFIRMED_PROPOSER))
        } 
        
        if (proofHeightOptions < 3) {
            feePrice = feePrices[proofHeightOptions];
            feeShare = (msg.value / VerusConstants.SATS_TO_WEI_STD) / 2;
            remainder = (msg.value / VerusConstants.SATS_TO_WEI_STD) % 2;
        
            require(msg.value == feePrice, "Not enough fee");

            // Proposer and notaries get share of fees
            // any remainder from divide by 2 or equal share to the notaries gets added to proposers share.
            feeShare += setNotaryFees(feeShare);
            setClaimedFees(bytes32(uint256(uint176(proposerAndHeight))), (feeShare + remainder));
        }

        if (proofHeightOptions == 0) {
            // if the most recent confrimed is requested just get the height from the bestforks
            return abi.encodePacked(uint32(proposerAndHeight >> OFFSET_FOR_HEIGHT), proofs[(bytes32(proposerAndHeight >> OFFSET_FOR_HEIGHT))]);

        } else if(proofHeightOptions == 1 || proofHeightOptions == 2) {

            // if the prior confirmed or second prior confirmed notarization is required extract the height from the newest confirmed.

            tempBytes = proofs[(bytes32(proposerAndHeight >> OFFSET_FOR_HEIGHT))];
            uint32 previousConfirmedHeight;

            assembly {
                previousConfirmedHeight := mload(add(tempBytes, PROOF_HEIGHT_LOCATION))
            } 

            if(proofHeightOptions == 1) {
                return abi.encodePacked(uint32(previousConfirmedHeight), proofs[bytes32(uint256(previousConfirmedHeight))]);
            }

            tempBytes = proofs[bytes32(uint256(previousConfirmedHeight))];

            uint32 secondPreviousConfirmedHeight;
            assembly {
                secondPreviousConfirmedHeight := mload(add(tempBytes, PROOF_HEIGHT_LOCATION))
            } 

            return abi.encodePacked(uint32(secondPreviousConfirmedHeight), proofs[bytes32(uint256(secondPreviousConfirmedHeight))]);

        } else {

           return abi.encodePacked(uint32(proofHeightOptions),proofs[bytes32(proofHeightOptions)]);
        }
    }

    function setNotaryFees(uint256 notaryFees) private returns (uint64 remainder){  //sent in as SATS
      
        uint256 numOfNotaries = notaries.length;
        uint64 notariesShare = uint64(notaryFees / numOfNotaries);
        for (uint i=0; i < numOfNotaries; i++)
        {
            uint176 notary;
            notary = uint176(uint160(notaryAddressMapping[notaries[i]].main));
            notary |= (uint176(0x0c14) << VerusConstants.UINT160_BITS_SIZE); //set at type eth
            claimableFees[bytes32(uint256(notary))] += notariesShare;
        }
        remainder = uint64(notaryFees % numOfNotaries);
    }

    function setClaimedFees(bytes32 _address, uint256 fees) private
    {
        claimableFees[_address] += fees;
    }

    function serializeUint32(uint32 number) public pure returns(uint32){
        // swap bytes
        number = ((number & 0xFF00FF00) >> 8) | ((number & 0x00FF00FF) << 8);
        number = (number >> 16) | (number << 16);
        return number;
    }


}
