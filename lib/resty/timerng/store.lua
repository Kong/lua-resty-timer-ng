local lrucache = require("resty.lrucache")
local array = require("resty.timerng.array")

local table_insert = table.insert

local setmetatable = setmetatable

local error = error
local assert = assert
local pairs = pairs
local type = type

local _M = {
    STORE_TYPE_GENERNAL = "general",
    STORE_TYPE_LRU = "lru",
    STORE_TYPE_AVERAGE = "average",
}

local meta_table = {
    __index = _M,
}


---append a number into namespace
---@param self table self
---@param namespace string namespace
---@param value number value
---@return nil
---@raise error if namespace not found
---@raise error if value is not a number
local function internal_append(self, namespace, value)
    if type(value) ~= "number" then
        error("value must be a number: " .. tostring(value))
    end

    if self.averages[namespace] then
        local cache = self.averages[namespace]

        if cache.array:length() >= cache.max_items then
            cache.sum = cache.sum - cache.array:pop_left()
        end

        cache.array:push_right(value)
        cache.sum = cache.sum + value
        return
    end

    error("namespace not found: " .. namespace)
end


---get all keys according to cache type
---@param self table the instance of this module
---@param namespace string the namespace of the cache
---@return table the keys of the cache (array-like table)
---@raise error if the namespace is not exist
local function internal_keys(self, namespace)
    if self.lru_caches[namespace] then
        local cache = self.lru_caches[namespace]
        return cache:get_keys()
    end

    if self.caches[namespace] then
        local cache = self.caches[namespace]
        local keys = {}
        for key, _ in pairs(cache) do
            table_insert(keys, key)
        end
        return keys
    end

    error("namespace not found: " .. namespace)
end


---set key-value according to cache type
---@param self table the instance of this module
---@param namespace string the name of namespace
---@param key any key
---@param value any value
---@return nil
---@raise error if the namespace is not exist
local function internal_set(self, namespace, key, value)
    if self.lru_caches[namespace] then
        local cache = self.lru_caches[namespace]
        cache:set(key, value)
        return
    end

    if self.caches[namespace] then
        local cache = self.caches[namespace]
        cache[key] = value
        return
    end

    error("namespace not found: " .. namespace)
end


---get value according to cache type
---@param self table the instance of this module
---@param namespace string the name of namespace
---@param key any key
---@return nil
---@raise error if the namespace is not exist
local function internal_get(self, namespace, key)
    if self.lru_caches[namespace] then
        local cache = self.lru_caches[namespace]
        return cache:get(key)
    end

    if self.caches[namespace] then
        local cache = self.caches[namespace]
        return cache[key]
    end

    error("namespace not found: " .. namespace)
end


---get average from a namespace
---@param self table the instance of this module
---@param namespace string the name of namespace
---@return number average
---@raise error if the namespace is not exist
---@raise error if any value is not a number
local function internal_average(self, namespace)
    if self.lru_caches[namespace] then
        local keys = internal_keys(self, namespace)
        local count = 0
        local sum = 0

        for _, key in ipairs(keys) do
            local value = internal_get(self, namespace, key)

            if type(value) ~= "number" then
                error("value is not number: " .. tostring(value))
            end

            count = count + 1
            sum = sum + value
        end

        if count == 0 then
            return 0
        end

        return sum / count
    end

    if self.caches[namespace] then
        local cache = self.caches[namespace]
        local count = 0
        local sum = 0

        for _, value in pairs(cache) do
            if type(value) ~= "number" then
                error("value is not number: " .. tostring(value))
            end

            count = count + 1
            sum = sum + value
        end

        if count == 0 then
            return 0
        end

        return sum / count
    end

    if self.averages[namespace] then
        local cache = self.averages[namespace]

        if cache.array:length() == 0 then
            return 0
        end

        return cache.sum / cache.array:length()
    end

    error("namespace not found: " .. namespace)
end


---delete key according to cache type
---@param self table the instance of this module
---@param namespace string the name of namespace
---@param key any key
---@return nil
---@raise error if the namespace is not exist
local function internal_delete(self, namespace, key)
    if self.lru_caches[namespace] then
        local cache = self.lru_caches[namespace]
        cache:delete(key)
        return
    end

    if self.caches[namespace] then
        local cache = self.caches[namespace]
        cache[key] = nil
        return
    end

    error("namespace not found: " .. namespace)
end


---similar to the `internal_set`, but never overrides the existing value
---@param self table the instance of this module
---@param namespace string the name of namespace
---@param key any key
---@param value any value
---@return boolean ok
---@return string err
---@raise error if the namespace is not exist
local function internal_safe_set(self, namespace, key, value)
    if internal_get(self, namespace, key) then
        return false, "key already exists"
    end

    internal_set(self, namespace, key, value)

    return true, nil
end


---increments the (numerical) value for key
---@param self table the instance of this module
---@param namespace string the name of namespace
---@param key any key
---@param value? number optional, value (default = 1)
---@param init? number optional, the initial value of the key (default = 0)
---@return number new_value
---@return string err
---@raise error if the namespace is not exist
local function internal_increase(self, namespace, key, value, init)
    local old_value = internal_get(self, namespace, key)

    value = value or 1

    if old_value == nil then
        init = init or 0
        internal_set(self, namespace, key, init + value)
        return init + value, nil
    end

    internal_set(self, namespace, key, old_value + value)

    return old_value + value, nil
end


---increments the (numerical) value for key if it exists
---@param self table the instance of this module
---@param namespace string the name of namespace
---@param key any key
---@param value? number optional, value (default = 1)
---@return number new_value_or_false
---@return string err
---@raise error if the namespace is not exist
local function internal_safe_increase(self, namespace, key, value)
    if not internal_get(self, namespace, key) then
        return false, "key not exists"
    end

    return internal_increase(self, namespace, key, value or 1)
end


---decrements the (numerical) value for key
---@param self table the instance of this module
---@param namespace string the name of namespace
---@param key any key
---@param value? number optional, value (default = 1)
---@param init? number optional, the initial value of the key (default = 0)
---@return number new_value
---@return string err
---@raise error if the namespace is not exist
local function internal_decrease(self, namespace, key, value, init)
    local old_value = internal_get(self, namespace, key)

    value = value or 1

    if old_value == nil then
        init = init or 0
        internal_set(self, namespace, key, init - value)
        return init - value, nil
    end

    internal_set(self, namespace, key, old_value - value)

    return old_value - value, nil
end


---decrements the (numerical) value for key if it exists
---@param self table the instance of this module
---@param namespace string the name of namespace
---@param key any key
---@param value? number optional, value (default = 1)
---@return number new_value_or_false
---@return string err
---@raise error if the namespace is not exist
local function internal_safe_decrease(self, namespace, key, value)
    if not internal_get(self, namespace, key) then
        return false, "key not exists"
    end

    return internal_decrease(self, namespace, key, value or 1)
end


---set key-value for the namespace
---@param namespace string the name of namespace
---@param key any key
---@param value any value
---@return nil
---@raise error if the namespace is not exist
function _M:set(namespace, key, value)
    internal_set(self, namespace, key, value)
end


---set key-value for the namespace, but never overrides the existing value
---@param namespace string the name of namespace
---@param key any key
---@param value any value
---@return boolean ok
---@return string err
---@raise error if the namespace is not exist
function _M:safe_set(namespace, key, value)
    return internal_safe_set(self, namespace, key, value)
end


---get value for the namespace
---@param namespace string the name of namespace
---@param key any key
---@return any value nil means not found
---@raise error if the namespace is not exist
function _M:get(namespace, key)
    return internal_get(self, namespace, key)
end


---increments the (numerical) value for key
---@param namespace string the name of namespace
---@param key any key
---@param value? number optional, value (default = 1)
---@param init? number optional, the initial value of the key (default = 0)
---@return number new_value
---@return string err
---@raise error if the namespace is not exist
function _M:increase(namespace, key, value, init)
    return internal_increase(self, namespace, key, value or 1, init or 0)
end


---increments the (numerical) value for key if it exists
---@param namespace string the name of namespace
---@param key any key
---@param value? number optional, value (default = 1)
---@return number new_value_or_false
---@return string err
---@raise error if the namespace is not exist
function _M:safe_increase(namespace, key, value)
    return internal_safe_increase(self, namespace, key, value or 1)
end


---decrements the (numerical) value for key
---@param namespace string the name of namespace
---@param key any key
---@param value? number optional, value (default = 1)
---@param init? number optional, the initial value of the key (default = 0)
---@return number new_value
---@return string err
---@raise error if the namespace is not exist
function _M:decrease(namespace, key, value, init)
    return internal_decrease(self, namespace, key, value or 1, init)
end


---decrements the (numerical) value for key if it exists
---@param namespace string the name of namespace
---@param key any key
---@param value? number optional, value (default = 1)
---@return number new_value_or_false
---@return string err
---@raise error if the namespace is not exist
function _M:safe_decrease(namespace, key, value)
    return internal_safe_decrease(self, namespace, key, value or 1)
end


---get average from a namespace
---@param namespace string the name of namespace
---@return number average
---@raise error if the namespace is not exist
---@raise error if any value is not a number
function _M:average(namespace)
    return internal_average(self, namespace)
end


---append value to the list for the namespace
---@param namespace string the name of namespace
---@param value number value to append
---@return nil
---@raise error if the namespace is not exist
---@raise error if the value is not a number
function _M:append(namespace, value)
    internal_append(self, namespace, value)
end


---delete key for the namespace
---@param namespace string the name of namespace
---@param key any key
---@return nil
---@raise error if the namespace is not exist
function _M:delete(namespace, key)
    internal_delete(self, namespace, key)
end


---get all keys for the namespace
---@param namespace string the name of namespace
---@return table the keys of the namespace (array-like table)
---@raise error if the namespace is not exist
function _M:keys(namespace)
    return internal_keys(self, namespace)
end


---create a namespace with the given name
---@param namespace string namespace name
---@param store_type? string store.STORE_TYPE_* (default = STORE_TYPE_GENERNAL)
---@param max_items? number optional, only LRU and AVERAGE (default = 1024)
---@return nil
---@raise error if the namespace already exists
---@raise error if max_items is not a number
---@raise error if failed to create lru cache
---@raise error if store_type is not supported
function _M:new_namespace(namespace, store_type, max_items)
    assert(type(namespace) == "string", "namespace must be a string")

    if self.caches[namespace]
    or self.lru_caches[namespace]
    or self.averages[namespace]
    then
        error("namespace already exists: " .. tostring(namespace))
    end

    if max_items and type(max_items) ~= "number" then
        error("max_items must be a number: " .. tostring(max_items))
    end

    if not max_items then
        max_items = 1024
    end

    if not store_type then
        store_type = _M.STORE_TYPE_GENERNAL
    end

    if store_type == _M.STORE_TYPE_GENERNAL then
        self.caches[namespace] = {}
        return
    end

    if store_type == _M.STORE_TYPE_LRU then
        local lru_cache, err = lrucache.new(max_items)

        if not lru_cache then
            error("failed to create lru cache: " .. err)
        end

        self.lru_caches[namespace] = lru_cache

        return
    end

    if store_type == _M.STORE_TYPE_AVERAGE then
        self.averages[namespace] = {
            array = array.new(),
            sum = 0,
            max_items = max_items,
        }
        return
    end

    error("unknown store type: " .. store_type)
end



function _M.new()
    local self = {
        -- lru_caches[namespace] = lrucache.new(<size>)
        lru_caches = {},

        -- caches[namespace] = {}
        caches = {},

        -- averages[namespace] = {
        --     array = array.new(),
        --     sum = <number>,
        --     max_items = <number>,
        -- }
        averages = {},
    }

    return setmetatable(self, meta_table)
end


return _M
