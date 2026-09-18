
local TableMgr = {}

local TableData = {}
local TableType = {}

TableMgr.TableData = TableData
TableMgr.TableType = TableType

function TableMgr:GetTable(tableId)
	return TableData[tableId]
end

function TableMgr:GetTableRowType(tableId, rowId)
	return TableType[tableId][rowId]
end

function TableMgr:GetTableRowColData(tableId, rowId, colId)
	return TableData[tableId][rowId][colId]
end





return TableMgr
