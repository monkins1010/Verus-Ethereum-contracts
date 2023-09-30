// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.8.9;
pragma abicoder v2;

import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "./NotarizationSerializer.sol";
import "../MMR/VerusBlake2b.sol";
import "../VerusBridge/CreateExports.sol";
import "../VerusBridge/UpgradeManager.sol";
import "../Storage/StorageMaster.sol";
import "../VerusBridge/SubmitImports.sol";

contract VerusNotarizer is VerusStorage {

    address immutable VETH;
    address immutable BRIDGE;
    address immutable VERUS;

    constructor(address vETH, address Bridge, address Verus){

        VETH = vETH;
        BRIDGE = Bridge;
        VERUS = Verus;
    }
        
    uint8 constant FORKS_DATA_OFFSET_FOR_HEIGHT = 224;

    uint32 constant FORKS_DATA_CONFIRMED_PROPOSER = 96;
    uint32 constant PROOF_HEIGHT_LOCATION = 68 - 32;  //NOTE: removed blockhash from proofroot, so this is now 68 bytes minus 32 bytes for the blockhash
    uint32 constant LENGTH_OF_FORK_DATA = 96;

    // notarization vdxf key
    bytes22 constant vdxfcodePlusVersion = bytes22(0x01367Eaadd291E1976ABc446A143f83c2D4D2C5a8401);
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
        bytes memory tempBytes;

        tempBytes =  abi.encodePacked(
                    vdxfcodePlusVersion,
                    txidHash,
                    VERUS,
                    serializeUint32(blockheights[i]),
                    notaryAddresses[i], 
                    keccakNotarizationHash);

        for(; i < notaryAddresses.length; i++)
        {
            if (i < (notaryAddresses.length - 1)) {
                checkunique(notaryAddresses, i);
            }
            
            bytes32 hashedNotarizationByID;
            // hash the notarizations with the vdxf key, system, height & NotaryID. the address is masked in 98 bytes in .
            assembly {
                mstore(add(tempBytes, 98), or(and(mload(add(tempBytes, 98)), shl(160, 0xffffffffffffffffffffffff)), mload(add(notaryAddresses, mul(add(i,1), 32)))))
                hashedNotarizationByID := keccak256(add(tempBytes, 0x20), mload(tempBytes))
            }

           // hashedNotarizationByID = keccak256(tempBytes);

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

        (bytes32 launchedAndProposer, bytes32 prevnotarizationtxid, bytes32 hashprevnotarization, bytes32 stateRoot, 
                uint32 verusProofheight) = abi.decode(returnBytes, (bytes32, bytes32, bytes32, bytes32, uint32));

        voutAndHeight |= uint64(verusProofheight) << 32; // pack two 32bit numbers into one uint64
        launchedAndProposer |= bytes32(uint256(voutAndHeight) << VerusConstants.NOTARIZATION_VOUT_NUM_INDEX); // Also pack in the voutnum at the end of the uint256

        setNotarizationProofRoot(blakeNotarizationHash, hashprevnotarization, txid, prevnotarizationtxid, launchedAndProposer, stateRoot);

        // If the bridge is active and VRSC remaining has not been sent
        if (remainingLaunchFeeReserves != 0 && bridgeConverterActive) { 

            if (remainingLaunchFeeReserves > (VerusConstants.verusTransactionFee * 2)) {
                bool success2; bytes memory retData;
                (success2, retData) = contracts[uint(VerusConstants.ContractType.SubmitImports)].delegatecall(abi.encodeWithSelector(SubmitImports.sendBurnBackToVerus.selector, 0, VERUS, 0));
                require(success2);
                (VerusObjects.CReserveTransfer memory LPtransfer,) = abi.decode(retData, (VerusObjects.CReserveTransfer, bool)); 

                (success2, retData) = contracts[uint(VerusConstants.ContractType.CreateExport)].delegatecall(abi.encodeWithSelector(CreateExports.externalCreateExportCall.selector, abi.encode(LPtransfer, true)));
                require(success2);
                remainingLaunchFeeReserves = 0;
            }
        }
        emit NewNotarization(blakeNotarizationHash);
    }

    function decodeNotarization(uint index) public view returns (VerusObjectsNotarization.NotarizationForks[] memory)
        {
            uint32 nextOffset;

            bytes storage tempArray = bestForks[index];

            bytes32 hashOfNotarization;
            bytes32 txid;
            bytes32 packedPositions;
            bytes32 slotHash;
            VerusObjectsNotarization.NotarizationForks[] memory retval = new VerusObjectsNotarization.NotarizationForks[]((tempArray.length / LENGTH_OF_FORK_DATA) + 1);
            if (tempArray.length > 1)
            {
                bytes32 slot;
                assembly {
                            mstore(add(slot, 32),tempArray.slot)
                            slotHash := keccak256(add(slot, 32), 32)
                         }

                for (int i = 0; i < int(tempArray.length / LENGTH_OF_FORK_DATA); i++) 
                {
                    assembly {
                        hashOfNotarization := sload(add(slotHash,nextOffset))
                        nextOffset := add(nextOffset, 1)  
                        txid := sload(add(slotHash,nextOffset))

                        nextOffset := add(nextOffset, 1) 
                        packedPositions :=sload(add(slotHash,nextOffset))
                        nextOffset := add(nextOffset, 1)
                    }

                    retval[uint(i)] =  VerusObjectsNotarization.NotarizationForks(hashOfNotarization, txid, packedPositions);
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
                                            notarizations.proposerPacked);
    }

    function encodeStandardNotarization(VerusObjectsNotarization.NotarizationForks memory firstNotarization, bytes memory secondNotarization)private  {
        
        bestForks[0] = abi.encodePacked(firstNotarization.hashOfNotarization, 
                                            firstNotarization.txid,
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
            // Notarization length is always +1 more than the amount we have, as slot is ready to be filled.
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
                txidHash, proposer));

            // The proofs are indexed by height, the height is stored in the proposers last 32 bits. Stored ine the proof is stateroot and the previous proof height.

            proofs[bytes32(uint256(uint32(uint256(proposer >> FORKS_DATA_OFFSET_FOR_HEIGHT))))] = abi.encodePacked(stateRoot, uint32(uint256(notarizations[1].proposerPacked) >> FORKS_DATA_OFFSET_FOR_HEIGHT));

            // Set bridge launched if confirmed notarization contains Bridge Launched bit packed on the end of proposer

            if (!bridgeConverterActive && ((uint256(notarizations[1].proposerPacked) >> VerusConstants.UINT176_BITS_SIZE) & 0xff) == 1) {
                    bridgeConverterActive = true;
            }
        }
        else
        {
            encodeNotarization(uint(forkIdx), VerusObjectsNotarization.NotarizationForks(hashedNotarization,
                txidHash, proposer));
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
            proposerAndHeight := mload(add(tempBytes, FORKS_DATA_CONFIRMED_PROPOSER))
        } 
        
        if (proofHeightOptions < 3) {
            feePrice = feePrices[proofHeightOptions];
            feeShare = (msg.value / VerusConstants.SATS_TO_WEI_STD) / 2;
            remainder = (msg.value / VerusConstants.SATS_TO_WEI_STD) % 2;
        
            require(msg.value == feePrice, "Not enough fee");

            // Proposer and notaries get share of fees
            // any remainder from divide by 2 or equal share to the notaries gets added to proposers share.
            claimableFees[VerusConstants.VDXF_SYSTEM_NOTARIZATION_NOTARYFEEPOOL] += feeShare;
            setClaimedFees(bytes32(uint256(uint176(proposerAndHeight))), (feeShare + remainder));
        }

        if (proofHeightOptions == 0) {
            // if the most recent confirmed is requested just get the height from the bestforks
            return abi.encodePacked(uint32(proposerAndHeight >> FORKS_DATA_OFFSET_FOR_HEIGHT), proofs[(bytes32(proposerAndHeight >> FORKS_DATA_OFFSET_FOR_HEIGHT))]);

        } else if(proofHeightOptions == 1 || proofHeightOptions == 2) {

            // if the prior confirmed or second prior confirmed notarization is required extract the height from the newest confirmed.

            tempBytes = proofs[(bytes32(proposerAndHeight >> FORKS_DATA_OFFSET_FOR_HEIGHT))];
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

           return abi.encodePacked(uint32(proofHeightOptions), proofs[bytes32(proofHeightOptions)]);
        }
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
