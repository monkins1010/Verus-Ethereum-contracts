// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../VerusBridge/VerusSerializer.sol";
import "../MMR/VerusBlake2b.sol";

contract VerusNotarizer {

    //last notarized blockheight
    uint32 public lastBlockHeight;
    //CurrencyState private lastCurrencyState;
    //allows for the contract to be upgradable
    bool public deprecated;
    address public upgradedAddress;

    //number of notaries required
    uint8 requiredNotaries = 13;

    uint8 constant FLAG_FRACTIONAL = 1;
    uint8 constant FLAG_REFUNDING = 4;
    uint8 constant FLAG_LAUNCHCONFIRMED = 0x10;
    uint8 constant FLAG_LAUNCHCOMPLETEMARKER = 0x20;

    VerusBlake2b blake2b;
    VerusSerializer verusSerializer;
    bytes20 vdxfcode = bytes20(0x367Eaadd291E1976ABc446A143f83c2D4D2C5a84);

    //list of all notarizers mapped to allow for quick searching
    mapping (address => bool) public komodoNotaries;
    mapping (address => address) public notaryAddressMapping;
    address[] private notaries;
    //mapped blockdetails
    mapping (uint32 => VerusObjectsNotarization.CProofRoot) public notarizedProofRoots;
    mapping (uint32 => bytes32) public notarizedStateRoots;
    
    mapping (address => uint32) public poolAvailable;

    uint32[] public blockHeights;
    //used to record the number of notaries
    uint8 private notaryCount;

    // Notifies when the contract is deprecated
    event Deprecate(address newAddress);

    // Notifies when a new block hash is published
    event NewBlock(VerusObjectsNotarization.CPBaaSNotarization,uint32 notarizedDataHeight);

    constructor(address _verusBLAKE2bAddress,address _verusSerializerAddress,address[] memory _notaries,address[] memory _notariesEthAddress) public {
        verusSerializer = VerusSerializer(_verusSerializerAddress);
        blake2b = VerusBlake2b(_verusBLAKE2bAddress);
        deprecated = false;
        notaryCount = 0;
        lastBlockHeight = 0;
        //add in the owner as the first notary
       // address msgSender = msg.sender;
        for(uint i =0; i < _notaries.length; i++){
            komodoNotaries[_notaries[i]] = true;
            notaryAddressMapping[_notaries[i]] = _notariesEthAddress[i];
            notaries.push(_notaries[i]);
            notaryCount++;
        }
    }

    modifier onlyNotary() {
        address msgSender = msg.sender;
        bytes memory errorMessage = abi.encodePacked("Caller is not a notary",msgSender);
        require(komodoNotaries[msgSender] == true, string(errorMessage));
        _;
    }
    
    function getNotaries() public view returns(address[] memory){
        return notaries;
    }
        
    function isNotary(address _notary) public view returns(bool) {
        if(komodoNotaries[_notary] == true) return true;
        else return false;
    }

    //this function allows for intially expanding out the number of notaries
    function currentNotariesRequired() public view returns(uint8){
        if(notaryCount == 1 || notaryCount == 2) return 1;
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
            if(komodoNotaries[signingAddress]) {
                numberOfSignatures++;
            }
        }
        uint8 _requiredNotaries = currentNotariesRequired();
        if(numberOfSignatures >= _requiredNotaries){
            return true;
        } else return false;

    }
 
    function setLatestData(VerusObjectsNotarization.CPBaaSNotarization memory _pbaasNotarization,
        uint8[] memory _vs,
        bytes32[] memory _rs,
        bytes32[] memory _ss,
        uint32[] memory blockheights,
        address[] memory notaryAddress
        ) public returns(bool output) {

        require(!deprecated,"Contract has been deprecated");
        require((_rs.length == _ss.length) && (_rs.length == _vs.length),"Signature arrays must be of equal length");
        require(_pbaasNotarization.notarizationheight > lastBlockHeight,"Block Height must be greater than current block height");

        bytes memory serializedNotarisation = verusSerializer.serializeCPBaaSNotarization(_pbaasNotarization);
        
        //add in the extra fields for the hashing
        //add in the other pieces for encoding
        bytes32 hashedNotarization;
        address signer;
        uint8 numberOfSignatures = 0;
        bytes memory toHash;

        for(uint i=0; i < blockheights.length;i++){
            //build the hashing sequence
            toHash = abi.encodePacked(uint8(1),
                vdxfcode,VerusConstants.VerusSystemId,
                verusSerializer.serializeUint32(blockheights[i]),
                notaryAddress[i],
                abi.encodePacked(keccak256(serializedNotarisation)));
            
            hashedNotarization = keccak256(toHash);
            
            signer = recoverSigner(hashedNotarization, _vs[i]-4, _rs[i], _ss[i]);
            if(signer == notaryAddressMapping[notaryAddress[i]]){
                   numberOfSignatures++;
            }
            if(numberOfSignatures >= requiredNotaries){
                break;
            }
        }
        if (numberOfSignatures >= currentNotariesRequired()){
            //valid notarization
            //loop through the currencystates and confirm if the bridge is active
            for(uint k= 0; k < _pbaasNotarization.currencystates.length; k++){
                if (_pbaasNotarization.currencystates[k].currencystate.flags & 
                        (FLAG_FRACTIONAL + FLAG_REFUNDING + FLAG_LAUNCHCONFIRMED + FLAG_LAUNCHCOMPLETEMARKER) == 
                            (FLAG_FRACTIONAL + FLAG_LAUNCHCONFIRMED + FLAG_LAUNCHCOMPLETEMARKER)
                    && poolAvailable[_pbaasNotarization.currencystates[k].currencyid] == 0) {
                    poolAvailable[_pbaasNotarization.currencystates[k].currencyid] = uint32(block.number);
                }
            }

            for(uint j = 0 ; j < _pbaasNotarization.proofroots.length;j++){
                if(_pbaasNotarization.proofroots[j].systemid == VerusConstants.VerusCurrencyId){
                    notarizedStateRoots[_pbaasNotarization.notarizationheight] =  _pbaasNotarization.proofroots[j].stateroot;       
                    notarizedProofRoots[_pbaasNotarization.notarizationheight] = _pbaasNotarization.proofroots[j];
                    blockHeights.push(_pbaasNotarization.notarizationheight);
                    if(lastBlockHeight <_pbaasNotarization.notarizationheight){
                        lastBlockHeight = _pbaasNotarization.notarizationheight;
                    }
                }
            }
            emit NewBlock(_pbaasNotarization, lastBlockHeight);
            
            return true;        
        }
      
        return false;
    }

    function recoverSigner(bytes32 _h, uint8 _v, bytes32 _r, bytes32 _s) public pure returns (address) {
        address addr = ecrecover(_h, _v, _r, _s);
        return addr;
    }

    function numNotarizedBlocks() public view returns(uint){
        return blockHeights.length;
    }

    function getLastProofRoot() public view returns(VerusObjectsNotarization.CProofRoot memory){
        return notarizedProofRoots[lastBlockHeight];
    }
    
    function notarizedDeprecation(address _upgradedAddress,bytes32 _addressHash,uint8[] memory _vs,bytes32[] memory _rs,bytes32[] memory _ss) public view returns(bool){
        require(isNotary(msg.sender),"Only a notary can deprecate this contract");
        bytes32 testingAddressHash = blake2b.createHash(abi.encodePacked(_upgradedAddress));
        require(testingAddressHash == _addressHash,"Hashed address does not match address hash passed in");
        require(isNotarized(_addressHash, _rs, _ss, _vs),"Deprecation requires the address to be notarized");
        return(true);
    }

    function deprecate(address _upgradedAddress,bytes32 _addressHash,uint8[] memory _vs,bytes32[] memory _rs,bytes32[] memory _ss) public {
        if(notarizedDeprecation(_upgradedAddress, _addressHash, _vs, _rs, _ss)){
            deprecated = true;
            upgradedAddress = _upgradedAddress;
            Deprecate(_upgradedAddress);
        }
    }
}
