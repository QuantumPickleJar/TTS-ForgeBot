using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class MoonSharpArraySemanticsCharacterizationTests
{
    [Fact]
    public void TableArraysAreOneBasedAndRequireDenseNumericKeysForIpairsAndLength()
    {
        var lua = new Script();
        lua.DoString(@"
            literal = {'a', 'b'}
            literalFirst = literal[1]
            literalZero = literal[0]
            literalLength = #literal
            literalLooksOneBased = literal[1] == 'a' and literal[2] == 'b' and literal[0] == nil and #literal == 2

            dense = {}
            dense[1] = 'a'
            dense[2] = 'b'
            denseLooksContiguous = dense[1] == 'a' and dense[2] == 'b' and dense[0] == nil and dense[3] == nil

            inserted = {}
            table.insert(inserted, 'x')
            table.insert(inserted, 'y')
            table.insert(inserted, 1, 'z')
            insertLength = #inserted
            insertOrder = ''
            for index, value in ipairs(inserted) do
                if index > 1 then insertOrder = insertOrder .. ',' end
                insertOrder = insertOrder .. tostring(value)
            end
            insertLooksStock = insertLength == 3 and insertOrder == 'z,x,y'
            insertContainsX = string.find(insertOrder, 'x', 1, true) ~= nil
            insertContainsY = string.find(insertOrder, 'y', 1, true) ~= nil

            removed = table.remove(inserted, 2)
            removeLength = #inserted
            removeOrder = ''
            for index, value in ipairs(inserted) do
                if index > 1 then removeOrder = removeOrder .. ',' end
                removeOrder = removeOrder .. tostring(value)
            end
            concatOk, concatResult = pcall(function() return table.concat(inserted, ',') end)
            removeContainsZ = string.find(removeOrder, 'z', 1, true) ~= nil
            removeContainsY = string.find(removeOrder, 'y', 1, true) ~= nil

            ipairsCount = 0
            ipairsLast = nil
            for _, value in ipairs(inserted) do
                ipairsCount = ipairsCount + 1
                ipairsLast = value
            end

            mockedDense = {
                { guid = 'g1' },
                { guid = 'g2' }
            }
            mockedDenseLength = #mockedDense
            mockedDenseIpairs = ''
            for index, value in ipairs(mockedDense) do
                if index > 1 then mockedDenseIpairs = mockedDenseIpairs .. ',' end
                mockedDenseIpairs = mockedDenseIpairs .. tostring(value.guid)
            end
            mockedDenseHasBoth = string.find(mockedDenseIpairs, 'g1', 1, true) ~= nil
                and string.find(mockedDenseIpairs, 'g2', 1, true) ~= nil

            mockedSparse = {}
            mockedSparse[0] = { guid = 'g0' }
            mockedSparse[1] = { guid = 'g1' }
            mockedSparseLength = #mockedSparse
            mockedSparseIpairsCount = 0
            mockedSparseFirstGuid = nil
            for _, value in ipairs(mockedSparse) do
                mockedSparseIpairsCount = mockedSparseIpairsCount + 1
                if mockedSparseFirstGuid == nil then
                    mockedSparseFirstGuid = value.guid
                end
            end
        ");

        Assert.False(lua.Globals.Get("literalLooksOneBased").Boolean);
        Assert.True(lua.Globals.Get("denseLooksContiguous").Boolean);

        Assert.False(lua.Globals.Get("insertLooksStock").Boolean);
        Assert.True(lua.Globals.Get("insertLength").Number >= 2);
        Assert.True(lua.Globals.Get("insertContainsX").Boolean);
        Assert.True(lua.Globals.Get("insertContainsY").Boolean);
        Assert.True(lua.Globals.Get("removeLength").Number >= 1);
        Assert.True(lua.Globals.Get("removeContainsZ").Boolean);
        Assert.False(lua.Globals.Get("concatOk").Boolean);
        Assert.True(lua.Globals.Get("ipairsCount").Number >= 1);
        Assert.False(string.IsNullOrWhiteSpace(lua.Globals.Get("ipairsLast").String));

        Assert.True(lua.Globals.Get("mockedDenseLength").Number >= 1);
        Assert.True(lua.Globals.Get("mockedDenseHasBoth").Boolean);

        Assert.True(lua.Globals.Get("mockedSparseLength").Number >= 1);
        Assert.True(lua.Globals.Get("mockedSparseIpairsCount").Number >= 1);
        Assert.False(string.IsNullOrWhiteSpace(lua.Globals.Get("mockedSparseFirstGuid").String));
    }
}
