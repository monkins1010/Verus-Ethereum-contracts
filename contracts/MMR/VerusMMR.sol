// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

library VerusMMR {


function GetMMRProofIndex(uint64 pos, uint64 mmvSize, uint8 extrahashes) public pure returns (uint64, uint64) {

    uint64 retIndex = 0;
    uint64 bitPos = 0;

    if (mmvSize == 0 || pos >= mmvSize) {
        return (type(uint64).max, type(uint64).max);
    }

    // These three are needed by the final path-walk, so they live at function
    // scope. Everything used ONLY to build them is confined to the blocks below,
    // so the counters (j, x, layerNum, layerSize, passThrough) drop off the stack
    // before the walk begins — this is what resolves the stack-too-deep.
    uint64[] memory Sizes;
    uint32[] memory PeakIndexes;
    uint64[] memory MerkleSizes;

    // --- build Sizes: layer sizes from mmvSize down to 1 ---
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
        Sizes = new uint64[](j + 1);

        x = 0;
        Sizes[x++] = mmvSize;
        mmvSize >>= 1;

        while (mmvSize != 0)
        {
            Sizes[x++] = mmvSize;
            mmvSize >>= 1;
        }
    }

    // --- build PeakIndexes (count pass, then fill pass) ---
    {
        uint j = 0;
        for (int32 ht = int32(uint32(Sizes.length - 1)); ht != -1; ht--)
        {
            // if we're at the top or the layer above us is smaller than 1/2 the size of this layer, rounded up, we are a peak
            if (ht == int32(uint32(Sizes.length) - 1) || (Sizes[uint32(ht)] & 1) == 1)
            {
                j++;
            }
        }

        PeakIndexes = new uint32[](j);
        uint64 x = 0; //reset x
        for (int32 ht = int32(uint32(Sizes.length - 1)); ht != -1; ht--)
        {
            // if we're at the top or the layer above us is smaller than 1/2 the size of this layer, rounded up, we are a peak
            if (ht == int32(uint32(Sizes.length) - 1) || (Sizes[uint32(ht)] & 1) == 1)
            {
                PeakIndexes[x++] = uint32(ht);
            }
        }
    }

    // --- build MerkleSizes (count pass, then fill pass) ---
    {
        // figure out the peak merkle
        // with an odd number of elements below, the edge passes through
        uint j = 0;
        uint64 layerNum = 0;
        uint64 layerSize = uint64(PeakIndexes.length);

        //workout array size for MerkleSizes
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

        MerkleSizes = new uint64[](j);
        //reset variables
        uint64 x = 0;
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
    }

    // add extra hashes for a node on the right
    bitPos += extrahashes;

    // --- walk from pos up to the root: record direction bits and count steps (bitPos) ---
    uint64 p = pos;
    for (uint l = 0; l < Sizes.length; l++)
    {
        if (p & 1 == 1)
        {
            retIndex |= (uint64(1) << bitPos++);
            p >>= 1;
            bitPos += extrahashes;
        }
        else
        {
            // make sure there is one after us to hash with or we are a peak and should be hashed with the rest of the peaks
            if (Sizes[l] > (p + 1))
            {
                bitPos++;
                p >>= 1;
                bitPos += extrahashes;
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
                require(p < PeakIndexes.length, "MMR peak not found");

                // move up to the top, which is always a peak of size 1
                {
                    int64 layerNumA = -1;
                    uint64 layerSizeB;
                    for (layerSizeB = uint64(PeakIndexes.length); layerNumA == -1 || layerSizeB > 1; layerSizeB = MerkleSizes[uint64(++layerNumA)])
                    {
                        if (p < (layerSizeB - 1) || (p & 1) == 1)
                        {
                            if (p & 1 == 1)
                            {
                                // hash with the one before us
                                retIndex |= (uint64(1)) << bitPos;
                                bitPos++;
                                bitPos += extrahashes;
                            }
                            else
                            {
                                // hash with the one in front of us
                                bitPos++;
                                bitPos += extrahashes;
                            }
                        }
                        p >>= 1;
                    }
                }
                // finished
                break;
            }
        }
    }
    return (retIndex, bitPos);
    }
}
