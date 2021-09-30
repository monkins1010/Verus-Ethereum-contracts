// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../VerusBridge/VerusSerializer.sol";
import "../MMR/VerusBlake2b.sol";

contract VerusNotarizer{

    //last notarized blockheight
    uint32 public lastBlockHeight;
    //CurrencyState private lastCurrencyState;
    //allows for the contract to be upgradable
    bool public deprecated;
    address public upgradedAddress;
    //number of notaries required
    uint8 requiredNotaries = 13;
    VerusBlake2b blake2b;
    VerusSerializer verusSerializer;
    bytes20 vdxfcode = bytes20(0x367Eaadd291E1976ABc446A143f83c2D4D2C5a84);
    //8c ea 50 fa 0f c6 78 7f 0f f3 d6 88 58 b2 fa dd 36 e7 a4 85
    //0322174Cb35c1E987a8cbD39D3A3Ce29b290fbed 
    //0x280a0514338bbcdd2889f4809592816b388d4e7a;


    //list of all notarizers mapped to allow for quick searching
    mapping (address => bool) public komodoNotaries;
    mapping (address => address) public notaryAddressMapping;
    address[] private notaries;
    //mapped blockdetails
    mapping (uint32 => VerusObjectsNotarization.CProofRoot) public notarizedProofRoots;
    mapping (uint32 => bytes32) public notarizedStateRoots;
    
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
 
    struct teststruct {
        address[] signer;
        bytes[] toHash;
    }

    function setLatestData(VerusObjectsNotarization.CPBaaSNotarization memory _pbaasNotarization,
        uint8[] memory _vs,
        bytes32[] memory _rs,
        bytes32[] memory _ss,
        uint32[] memory blockheights,
        address[] memory notaryAddress
        ) public returns(teststruct memory output){

        require(!deprecated,"Contract has been deprecated");
        //require(komodoNotaries[msg.sender],"Only a notary can call this function");
        require((_rs.length == _ss.length) && (_rs.length == _vs.length),"Signature arrays must be of equal length");
        require(_pbaasNotarization.notarizationheight > lastBlockHeight,"Block Height must be greater than current block height");

        bytes memory serializedNotarisation = verusSerializer.serializeCPBaaSNotarization(_pbaasNotarization);
        
        //add in the extra fields for the hashing
        //add in the other pieces for encoding
        bytes32 hashedNotarization;
        address signer;
        uint8 numberOfSignatures = 0;
        bytes memory toHash;
        output.signer = new address[](blockheights.length);
        output.toHash = new bytes[](blockheights.length);
        //output = "start";
        
        for(uint i=0; i < blockheights.length;i++){
            //build the hashing sequence
            output.toHash[i] = toHash = abi.encodePacked(uint8(1),
                vdxfcode,VerusConstants.VerusSystemId,
                verusSerializer.serializeUint32(blockheights[i]),
                notaryAddress[i],
                abi.encodePacked(keccak256(serializedNotarisation)));
            //output = toHash;
            hashedNotarization = keccak256(toHash);
            //output = hashedNotarization;
            signer = recoverSigner(hashedNotarization, _vs[i]-4, _rs[i], _ss[i]);
            output.signer[i] = signer;
            if(signer == notaryAddressMapping[notaryAddress[i]]){
                   numberOfSignatures++;
                   //output = string(abi.encodePacked(output," signature correct"));
            }
            if(numberOfSignatures >= requiredNotaries){
                break;
            }
        }
       // require(numberOfSignatures >= currentNotariesRequired(),"Not enough signatures");
        if(numberOfSignatures >= currentNotariesRequired()){
                //output = string(abi.encodePacked(output," enough notaries"));
            for(uint j = 0 ; j < _pbaasNotarization.proofroots.length;j++){
                //output = string(abi.encodePacked(output," adding notarized data "));
                if(_pbaasNotarization.proofroots[j].systemid == VerusConstants.VerusCurrencyId){
                    
                    notarizedStateRoots[_pbaasNotarization.notarizationheight] =  _pbaasNotarization.proofroots[j].stateroot;       
                    notarizedProofRoots[_pbaasNotarization.notarizationheight] = _pbaasNotarization.proofroots[j];
                    blockHeights.push(_pbaasNotarization.notarizationheight);
                    if(lastBlockHeight <_pbaasNotarization.notarizationheight){
                         //output = string(abi.encodePacked(output," setting lastBlockHeight"));
                        lastBlockHeight = _pbaasNotarization.notarizationheight;
                    }
                }
            }
            emit NewBlock(_pbaasNotarization,lastBlockHeight);
            
        
        }
      
        return output;
    }

    function recoverSigner(bytes32 _h, uint8 _v, bytes32 _r, bytes32 _s) public pure returns (address) {
        address addr = ecrecover(_h, _v, _r, _s);
        return addr;
    }
/*
"0x0bc6ceeca1778117d9547d03c57cbe944de11cecf37ee01a84c193b82c712440"
4024712cb893c1841ae07ef3ec1ce14d94be7cc5037d54d9178177a1eccec60b*/

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
