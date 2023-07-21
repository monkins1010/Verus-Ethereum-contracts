// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

library VerusMMR {


function GetMMRProofIndex(uint64 pos, uint64 mmvSize, uint8 extrahashes) public pure returns (uint64) {
 
    uint64 retIndex = 0;
    uint64 bitPos = 0;

    // find a path from the indicated position to the root in the current view
    if (pos > 0 && pos < mmvSize)
    {
        // calculate array size first so we can use memory instead of storage
        // use x and j for counters
        uint j = 0;
        uint64 x = mmvSize;
        // count most significant bit position
        while ((x >>= 1) > 0) {
            ++j;
        }
        // Allocate array of defined size
        uint64[] memory Sizes = new uint64[](j + 1);
        
        x = 0;
        Sizes[x++] = mmvSize;
        mmvSize >>= 1;

        while (mmvSize != 0)
        {
            Sizes[x++] = mmvSize;
            mmvSize >>= 1;
        }
        // next work out PeakIndexes size for array
        j = 0;
        
        for (int32 ht = int32(uint32(Sizes.length - 1)); ht != -1; ht--)
        {
            // if we're at the top or the layer above us is smaller than 1/2 the size of this layer, rounded up, we are a peak
            if (ht == int32(uint32(Sizes.length) - 1) || (Sizes[uint32(ht)] & 1) == 1)
            {
                j++;
            }
        }

        uint32[] memory PeakIndexes = new uint32[](j);
        x = 0; //reset x
        for (int32 ht = int32(uint32(Sizes.length - 1)); ht != -1; ht--)
        {
            // if we're at the top or the layer above us is smaller than 1/2 the size of this layer, rounded up, we are a peak
            if (ht == int32(uint32(Sizes.length) - 1) || (Sizes[uint32(ht)] & 1) == 1)
            {
                PeakIndexes[x++] = uint32(ht);
            }
        }

        // figure out the peak merkle
        uint64 layerNum = 0;
        uint64 layerSize = uint64(PeakIndexes.length);
        // with an odd number of elements below, the edge passes through

        //workout array size for MerkleSizes
        j = 0;
        x = 0;
        for (uint64 passThrough = (layerSize & 1); layerNum == 0 || layerSize > 1;)
        {
            layerSize = (layerSize >> 1) + passThrough;
            if (layerSize != 0)
            {
                j++;
            }
            passThrough = (layerSize & 1); 
            layerNum++;
        }
        
        uint64[] memory MerkleSizes = new uint64[](j);
        //reset variables
        layerNum = 0;
        layerSize = uint64(PeakIndexes.length);
        for (uint64 passThrough = (layerSize & 1); layerNum == 0 || layerSize > 1;)
        {
            layerSize = (layerSize >> 1) + passThrough;
            if (layerSize != 0)
            {
                MerkleSizes[x++] = layerSize;
            }
            passThrough = (layerSize & 1); 
            layerNum++;
        }

        // add extra hashes for a node on the right
        for (uint8 i = 0; i < extrahashes; i++)
        {
            // move to the next position
            bitPos++;
        }

        uint64 p = pos;
        for (uint l = 0; l < Sizes.length; l++)
        {
            if (p & 1 == 1)
            {
                retIndex |= (uint64(1) << bitPos++);
                p >>= 1;

                for (uint8 i = 0; i < extrahashes; i++)
                {
                    bitPos++;
                }
            }
            else
            {
                // make sure there is one after us to hash with or we are a peak and should be hashed with the rest of the peaks
                if (Sizes[l] > (p + 1))
                {
                    bitPos++;
                    p >>= 1;

                    for (uint8 i = 0; i < extrahashes; i++)
                    {
                        bitPos++;
                    }
                }
                else
                {
                    for (p = 0; p < PeakIndexes.length; p++)
                    {
                        if (PeakIndexes[p] == l)
                        {
                            break;
                        }
                    }

                    // p is the position in the merkle tree of peaks
                    assert(p < PeakIndexes.length);

                    // move up to the top, which is always a peak of size 1
                    int64 layerNumA = -1;
                    uint64 layerSizeB;
                    for (layerSizeB = uint64(PeakIndexes.length); layerNumA == -1 || layerSizeB > 1; layerSizeB = MerkleSizes[uint64(++layerNumA)])
                    {
                        // printf("GetProofBits - Bits.size: %lu\n", Bits.size());
                        if (p < (layerSizeB - 1) || (p & 1) == 1)
                        {
                            if (p & 1 == 1)
                            {
                                // hash with the one before us
                                retIndex |= (uint64(1)) << bitPos;
                                bitPos++;

                                for (uint8 i = 0; i < extrahashes; i++)
                                {
                                    bitPos++;
                                }
                            }
                            else
                            {
                                // hash with the one in front of us
                                bitPos++;

                                for (uint8 i = 0; i < extrahashes; i++)
                                {
                                    bitPos++;
                                }
                            }
                        }
                        p >>= 1;
                    }
                    // finished
                    break;
                }
            }
        }
    }
    return retIndex;
    }
}