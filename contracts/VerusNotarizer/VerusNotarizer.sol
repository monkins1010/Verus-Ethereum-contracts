// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../VerusBridge/VerusSerializer.sol";
import "../MMR/VerusBlake2b.sol";
import "../VerusNotarizer/VerusNotarizerStorage.sol";
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
    address upgradeContract;
    address verusBridgeMaster;
    // notarization vdxf key

    // list of all notarizers mapped to allow for quick searching
    mapping (address => VerusObjects.notarizer ) public notaryAddressMapping;

    address[] private notaries;

    uint32 public notaryCount;
    bool public poolAvailable;
    uint32 public notaryTurn = 100;

    // Notifies when a new block hash is published
    event NewBlock(VerusObjectsNotarization.CPBaaSNotarization, uint32 notarizedDataHeight);

    constructor(address _verusSerializerAddress, address upgradeContractAddress, 
    address[] memory _notaries, address[] memory _notariesEthAddress, address[] memory _notariesColdStoreEthAddress, 
    address verusNotarizerStorageAddress, address verusBridgeMasterAddress) {
        verusSerializer = VerusSerializer(_verusSerializerAddress);
        upgradeContract = upgradeContractAddress;
        notaryCount = uint32(_notaries.length);
        verusNotarizerStorage = VerusNotarizerStorage(verusNotarizerStorageAddress); 
        verusBridgeMaster = verusBridgeMasterAddress;

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

    function isNotarized(bytes32 _notarizedDataHash,
        bytes32[] memory _rs,
        bytes32[] memory _ss,
        uint8[] memory _vs) public view returns(bool){
        
        address signingAddress;
        //total number of signatures that have been validated
        uint8 numberOfSignatures = 0;

        //loop through the arrays, check the following:
        //does the hash in the hashedBlocks match the komodoBlockHash passed in
        for(uint i = 0; i < _rs.length; i++){
            //if the address is in the notary array increment the number of signatures
            signingAddress = recoverSigner(_notarizedDataHash, _vs[i], _rs[i], _ss[i]);
            if(notaryAddressMapping[signingAddress].state == VerusConstants.NOTARY_VALID) {
                numberOfSignatures++;
            }
        }

        return (numberOfSignatures >= currentNotariesRequired());

    }
 
    function setLatestData(VerusObjectsNotarization.CPBaaSNotarization memory _pbaasNotarization,
        uint8[] memory _vs,
        bytes32[] memory _rs,
        bytes32[] memory _ss,
        uint32[] memory blockheights,
        address[] memory notaryAddress
        ) public returns(bool output) {

        uint32 lastNotarizationHeight = verusNotarizerStorage.lastBlockHeight();

        require((_rs.length == _ss.length) && (_rs.length == _vs.length),"Signature arrays must be of equal length");
        require(lastNotarizationHeight != uint32(0xffffffff), "Notarizer Revoked");
        require(_pbaasNotarization.notarizationheight > lastNotarizationHeight,"Block Height must be greater than current block height");

        bytes memory serializedNotarisation = verusSerializer.serializeCPBaaSNotarization(_pbaasNotarization);
        
        //add in the extra fields for the hashing
        //add in the other pieces for encoding
        bytes32 hashedNotarization;
        uint validSignatures;

        for(uint i=0; i < blockheights.length;i++)
        {
            //build the hashing sequence
            hashedNotarization = keccak256(abi.encodePacked(uint8(1),
                vdxfcode,
                VerusConstants.VerusSystemId,
                verusSerializer.serializeUint32(blockheights[i]),
                notaryAddress[i],
                abi.encodePacked(keccak256(serializedNotarisation))));

            if (recoverSigner(hashedNotarization, _vs[i]-4, _rs[i], _ss[i]) != notaryAddressMapping[notaryAddress[i]].main ||
                notaryAddressMapping[notaryAddress[i]].state != VerusConstants.NOTARY_VALID)
            {
                   revert("Invalid notary signer");  
            }

            if (lastNotarizationHeight != 0)
            {
                bytes32 prevNotarizationHash = verusNotarizerStorage.getNotarization(lastNotarizationHeight).hashprevnotarization;
                if(reversebytes32(prevNotarizationHash) != hashedNotarization)
                {
                    notaryAddressMapping[notaryAddress[i]].state = VerusConstants.NOTARY_REVOKED;
                    continue;
                }
            }
            validSignatures++;
            
            if(validSignatures >= currentNotariesRequired())
            {
                //valid amount of notarizations achieved
                //loop through the currencystates and confirm if the bridge is active
                if(!poolAvailable)
                {
                    for(uint k= 0; k < _pbaasNotarization.currencystates.length; k++)
                    {
                        address currencyId = _pbaasNotarization.currencystates[k].currencyid;

                        if (_pbaasNotarization.currencystates[k].currencystate.flags & (FLAG_FRACTIONAL + FLAG_REFUNDING + FLAG_LAUNCHCONFIRMED + FLAG_LAUNCHCOMPLETEMARKER) == 
                                    (FLAG_FRACTIONAL + FLAG_LAUNCHCONFIRMED + FLAG_LAUNCHCOMPLETEMARKER) 
                                    && verusNotarizerStorage.poolAvailable(currencyId) == 0 
                                    && currencyId == VerusConstants.VerusBridgeAddress) 
                            {
                                verusNotarizerStorage.setPoolAvailable(uint32(block.number), currencyId);
                                poolAvailable = true;
                            }
                    }
                }

                verusNotarizerStorage.setNotarization(_pbaasNotarization, _pbaasNotarization.notarizationheight);
                emit NewBlock(_pbaasNotarization, _pbaasNotarization.notarizationheight);
                return true;        
            }
        }
      
        return false;
    }

    function recoverSigner(bytes32 _h, uint8 _v, bytes32 _r, bytes32 _s) public pure returns (address) {

        return ecrecover(_h, _v, _r, _s);
    }

    function setClaimableFees(address _feeRecipient, address _proposer, uint256 _ethAmount) public returns (uint256){

        require(msg.sender == verusBridgeMaster); 
        
        uint256 notaryFees;
        uint256 LPFees;
        uint256 exporterFees;
        uint256 proposerFees;                

        notaryFees = _ethAmount.div(10).mul(3); 

        exporterFees = _ethAmount.div(10);
        proposerFees = _ethAmount.div(10);
        LPFees = _ethAmount - (notaryFees + exporterFees + proposerFees);

        setNotaryFees(notaryFees);
        verusNotarizerStorage.setClaimedFees(_feeRecipient, exporterFees);
        verusNotarizerStorage.setClaimedFees(_proposer, proposerFees);

        //return total amount of unclaimed LP Fees accrued.
        return verusNotarizerStorage.setClaimedFees(address(this), LPFees);
              
    }

    function setNotaryFees(uint256 fees) private {
        
        uint256 feeRemainder;
        uint256 feeMinusRemainder;
        uint256 feeAllocation;

        feeRemainder = fees % (notaries.length );

        feeMinusRemainder = fees - feeRemainder;

        feeAllocation = feeMinusRemainder.div(notaries.length);

        for(uint i = 0; i< notaries.length; i++)
        {
            verusNotarizerStorage.setClaimedFees(notaries[i], feeAllocation);
        }

        //cycle through notaries each notarization to pay them the remainding dust.
        if(feeMinusRemainder !=0)
        {
            verusNotarizerStorage.setClaimedFees(notaries[notaryTurn % notaries.length], feeRemainder);
        }
        
        notaryTurn++;
    
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
