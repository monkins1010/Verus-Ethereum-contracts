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

    VerusBlake2b blake2b;
    VerusSerializer verusSerializer;
    VerusNotarizerStorage verusNotarizerStorage;
    address upgradeContract;
    address verusBridgeMaster;
    // notarization vdxf key

    //list of all notarizers mapped to allow for quick searching
    mapping (address => bool) public komodoNotaries;
    mapping (address => address) public notaryAddressMapping;
    address[] private notaries;

    uint32 public notaryCount;
    bool public poolAvailable;
    uint32 public notaryTurn = 100;

    // Notifies when a new block hash is published
    event NewBlock(VerusObjectsNotarization.CPBaaSNotarization,uint32 notarizedDataHeight);

    constructor(address _verusBLAKE2bAddress,address _verusSerializerAddress, address upgradeContractAddress, 
    address[] memory _notaries, address[] memory _notariesEthAddress, address verusNotarizerStorageAddress, address verusBridgeMasterAddress) {
        verusSerializer = VerusSerializer(_verusSerializerAddress);
        blake2b = VerusBlake2b(_verusBLAKE2bAddress);
        upgradeContract = upgradeContractAddress;
        notaryCount = uint32(_notaries.length);
        verusNotarizerStorage = VerusNotarizerStorage(verusNotarizerStorageAddress); 
        verusBridgeMaster = verusBridgeMasterAddress;

        // when contract is launching/upgrading copy in to global bool pool available.
        if(verusNotarizerStorage.poolAvailable(VerusConstants.VerusBridgeAddress) > 0 )
            poolAvailable = true;

        for(uint i =0; i < _notaries.length; i++){
            komodoNotaries[_notaries[i]] = true;
            notaryAddressMapping[_notaries[i]] = _notariesEthAddress[i];
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

        return (numberOfSignatures >= currentNotariesRequired());

    }
 
    function setLatestData(VerusObjectsNotarization.CPBaaSNotarization memory _pbaasNotarization,
        uint8[] memory _vs,
        bytes32[] memory _rs,
        bytes32[] memory _ss,
        uint32[] memory blockheights,
        address[] memory notaryAddress
        ) public returns(bool output) {

        require((_rs.length == _ss.length) && (_rs.length == _vs.length),"Signature arrays must be of equal length");
        require(_pbaasNotarization.notarizationheight > verusNotarizerStorage.lastBlockHeight(),"Block Height must be greater than current block height");

        bytes memory serializedNotarisation = verusSerializer.serializeCPBaaSNotarization(_pbaasNotarization);
        
        //add in the extra fields for the hashing
        //add in the other pieces for encoding
        bytes32 hashedNotarization;

        for(uint i=0; i < blockheights.length;i++)
        {
            //build the hashing sequence
            hashedNotarization = keccak256(abi.encodePacked(uint8(1),
                vdxfcode,VerusConstants.VerusSystemId,
                verusSerializer.serializeUint32(blockheights[i]),
                notaryAddress[i],
                abi.encodePacked(keccak256(serializedNotarisation))));

            if (recoverSigner(hashedNotarization, _vs[i]-4, _rs[i], _ss[i]) != notaryAddressMapping[notaryAddress[i]])
            {
                   revert("Invalid notary signer");  
            }

            if((i + 1) >= currentNotariesRequired())
            {

                //valid amount of notarizations achieved
                //loop through the currencystates and confirm if the bridge is active
                if(!poolAvailable)
                {
                    for(uint k= 0; k < _pbaasNotarization.currencystates.length; k++)
                    {
                        if (_pbaasNotarization.currencystates[k].currencystate.flags & 
                                (FLAG_FRACTIONAL + FLAG_REFUNDING + FLAG_LAUNCHCONFIRMED + FLAG_LAUNCHCOMPLETEMARKER) == 
                                    (FLAG_FRACTIONAL + FLAG_LAUNCHCONFIRMED + FLAG_LAUNCHCOMPLETEMARKER) &&
                                    verusNotarizerStorage.poolAvailable(_pbaasNotarization.currencystates[k].currencyid) == 0) 
                            {
                                verusNotarizerStorage.setPoolAvailable(uint32(block.number), _pbaasNotarization.currencystates[k].currencyid);
                                poolAvailable = true;
                            }
                    }
                }

                verusNotarizerStorage.setNotarization(_pbaasNotarization, _pbaasNotarization.notarizationheight);
              
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
        LPFees = _ethAmount - (LPFees + exporterFees + proposerFees);

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

}
