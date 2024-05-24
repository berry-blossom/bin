--!strict

-- Easy cleanup utility.
-- Runs functions, destroys instances/tables, disconnects events, and stops threads.
-- Usage:
--[[
	```lua
	local new = Bin.new()
	
	new.hello_world = function()
		print("Hello World!")
	end
	new.hello_world = nil; -- Runs the hello_world function
	
	new.baseplate = workspace.Baseplate
	new.baseplate = nil -- Destroys workspace.Baseplate
	
	local index_of_task = new:Add(function() 
		print("Hello World!")
	end)
	

	new:Clean() -- Destroys any remaining tasks
	```
]]

local SPECIAL_KEYS = {
	["__IS_BIN_FROZEN"] = true,
	["__b"] = true,
	["__t"] = true,
}

local Bin = {}

type acceptable_destroy = { Destroy: (acceptable_destroy) -> () }
export type bin_task = (() -> () | Instance | RBXScriptConnection | thread | acceptable_destroy)?
export type Bin = typeof(setmetatable(
	{} :: {
		__b: { [any]: bin_task },
		__t: { [number]: bin_task, __IS_BIN_FROZEN: boolean },
	} & typeof(Bin),
	Bin
)) & { [any]: any }

local function isPromise(tsk)
	if
		typeof(tsk) ~= "table"
		or typeof(tsk.getStatus) ~= "function"
		or typeof(tsk.finally) ~= "function"
		or typeof(tsk.cancel) ~= "function"
	then
		return false
	end
	return true
end

-- I know I'm cheating with the typing here but whatever.
-- Private function to return cleanup functions for tasks.
local function cleanTask(tsk: bin_task | any): () -> ()
	local map = {
		["function"] = function()
			pcall(tsk :: () -> ())
		end,
		["Instance"] = function()
			pcall(tsk.Destroy, tsk)
		end,
		RBXScriptConnection = function()
			if tsk and tsk.Connected then
				pcall(tsk.Disconnect, tsk)
			end
		end,
		thread = function()
			pcall(task.cancel, tsk :: thread)
		end,
		["table"] = function()
			if (tsk :: any)["cancel"] then
				pcall(tsk.cancel, tsk)
			elseif (tsk :: any)["Cancel"] then
				pcall(tsk.Cancel, tsk)
			end
			if tsk.Destroy and typeof(tsk.Destroy) == "function" then
				pcall(tsk.Destroy, tsk)
			end
		end,
		["nil"] = function() end,
	}
	return (tsk and map[typeof(tsk)]) or function() end
end

-- Creates a new bin.
function Bin.new(): Bin
	local self = setmetatable({
		__b = {},
		__t = {},
		__IS_BIN_FROZEN = false,
	}, Bin)
	return (self :: any) :: Bin
end

function Bin.__index(self: Bin, key)
	if SPECIAL_KEYS[key] then
		return rawget(self, key)
	end

	-- We're probably accessing a table method.
	if Bin[key] then
		return Bin[key]
	end

	-- Now we're safe to grab whatever value out of the __b table.
	local trashcan = rawget(self, "__b")
	return trashcan and trashcan[key]
end

function Bin.__newindex(self: Bin, key, value)
	if SPECIAL_KEYS[key] then
		-- We don't want the user overwriting where we store our tasks, now do we?
		if not rawget(self, key) then
			rawset(self, key, value)
		end
		return
	end
	if rawget(self, "__IS_BIN_FROZEN") then
		error("Bin is currently frozen, so no new tasks may be added!")
		return
	end
	local trashcan = rawget(self, "__b")
	if trashcan then
		cleanTask(trashcan[key])()
		trashcan[key] = value
	end
end

function Bin:__tostring()
	local frozen_message = rawget(self, "__IS_BIN_FROZEN") and " (Frozen)" or ""
	local bin_tasks = 0
	for _, v in pairs(rawget(self, "__b")) do
		bin_tasks += 1
	end
	return `Bin ({#(rawget(self, "__t"))} trash tasks) ({bin_tasks} bin tasks){frozen_message}`
end

--[[
	Add a task to the bin, returns the index of the task.
	The task can be gotten with Bin:Get, and cleaned with Bin:CleanPosition.
]]
function Bin.Add(self: Bin, tsk: bin_task?): number
	local trashcan_array = rawget(self, "__t")

	if rawget(self, "__IS_BIN_FROZEN") then
		error("Bin is currently frozen, so no new tasks may be added!")
		return -1
	end

	if not trashcan_array then
		error("The Bin must be created to use Bin::Add")
	end

	table.insert(trashcan_array, tsk)

	return #trashcan_array
end

--[[
	Adds a Promise to the Bin as a task. This is done by doing the following:
		- Check if the Promise is started.
			! If not, it is assumed the Promise has resolved and is not added as a task.
		- Add the Promise to the bin as a task with a unique id.
		- Add `finally` to the Promise chain to cancel the Promise after it resolves.
	The Promise is then returned.
]]
function Bin.AddPromise(self: Bin, promise: any): any
	if not isPromise(promise) then
		error("Task is not a promise!")
	end
	if promise:getStatus() == "Started" then
		local promise_id = game:GetService("HttpService"):GenerateGUID();
		(self :: any)["PROMISE_" .. promise_id] = promise
		promise:finally(function()
			(self :: any)["PROMISE_" .. promise_id] = nil
		end)
	end
	return promise
end

-- Gets a task in the Bin based on the index return from Bin:Add
function Bin.Get(self: Bin, idx: number): bin_task
	local trashcan_array = rawget(self, "__t")

	if not trashcan_array then
		error("The Bin must be created to use Bin::Get")
	end

	return trashcan_array[idx]
end

--[[
	Cleans an index in the bin. 
	This method will not move any of the slots in the Bin.
]]
function Bin.CleanPosition(self: Bin, idx: number)
	local trashcan_array = rawget(self, "__t")

	if not trashcan_array then
		error("The Bin must be created to use Bin::CleanPosition")
	end

	if trashcan_array[idx] then
		cleanTask(trashcan_array[idx])()
		trashcan_array[idx] = nil
	end
end

--[[
	Cleans all tasks in the bin.
	
	Any values stored within the bin will be cleaned up as following:
		* Functions are ran.
			! Be sure any functions will not yield, as this will cause this method to yield as well.
			! The function is called with pcall, so no errors will occur
		* Instances are destroyed with :Destroy().
		* RBXScriptConnections will first check if they are connected. If they are, they will disconnect.
		* Threads will be canceled with task.cancel. 
			! The cancellation is wrapped in a pcall, so no errors will occur 
		* Tables with a "Destroy" method will call that method.
			! This is wrapped in a pcall, and the first argument should always be self! 
			! Tables without a "Destroy" method will throw a warning to the console, but will be dereferenced.
		* All other values will be dereferenced with `table.clear`.
]]
function Bin.Clean(self: Bin)
	local trashcan = rawget(self, "__b") or {}
	local trashcan_array = rawget(self, "__t") or {}
	for key, tsk in pairs(trashcan) do
		cleanTask(tsk)()
	end
	for key, tsk in pairs(trashcan) do
		rawset(trashcan, key, nil)
	end
	for i, tsk in ipairs(trashcan_array) do
		cleanTask(tsk)()
	end
	table.clear(trashcan_array)
end

-- Freezes the bin, not allowing for any more tasks to be added.
-- Tasks are still allowed to be cleaned up while frozen.
function Bin.Freeze(self: Bin)
	if self.__IS_BIN_FROZEN then
		return
	end
	self.__IS_BIN_FROZEN = true
end

-- Unfreezes the bin, allowing for new tasks to be added.
function Bin.Unfreeze(self: Bin)
	if not self.__IS_BIN_FROZEN then
		return
	end
	self.__IS_BIN_FROZEN = false
end

-- Gets whether or not the bin is frozen.
function Bin.IsFrozen(self: Bin)
	return self.__IS_BIN_FROZEN
end

-- Destroy the bin entirely, meaning it will be ready to be GC'd.
function Bin.Destroy(self: Bin)
	self.Freeze(self)
	self.Clean(self)
	setmetatable(self, {})
	table.clear(self)
end

return Bin
