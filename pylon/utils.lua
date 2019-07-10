local pairs    = pairs
local type     = type
local string   = string
local str_rep  = string.rep
local str_find = string.find
local tostring = tostring
local ipairs   = ipairs
local table    = table
local table_insert  = table.insert
local table_concat  = table.concat
local str_sub       = string.sub
local encode_base64 = ngx.encode_base64
local sha1_bin      = ngx.sha1_bin
local ffi           = require "ffi"
local ffi_new       = ffi.new
local ffi_str       = ffi.string
local C             = ffi.C

--- @module pylon.utils
local utils = {
    -- luajit extended API
    is_array     = table.isarray,
    count        = table.nkeys,
    shallow_copy = table.clone,
    deep_copy    = table.clone,
}

ffi.cdef[[
int RAND_bytes(unsigned char *buf, int num);

int gethostname(char *name, size_t len);
]]

--- Экспортирует таблицу в строку
--- @param tbl table
--- @param indent number отступ в количествах пробелов
--- @return string
function utils.table_export(tbl, indent)
    if not indent then
        indent = 0
    elseif indent > 16 then
        return "*** too deep ***"
    end
    local output = "";
    local tab = str_rep("  ", indent + 1);
    for k, v in pairs(tbl) do
        local formatting = tab
        if type(k) == 'string' then
            formatting = formatting .. k .. " = "

        end
        if type(v) == "table" then
            if type(k) == "string" and k:sub(1, 1) == "_" then
                output = output .. formatting .. "*** private table ***\n"
            else
                output = output .. formatting .. utils.table_export(v, indent + 1) .. "\n"
            end
        else
            output = output .. formatting .. "("..type(v)..") " .. tostring(v) .. "\n"
        end
    end

    if output ~= "" then
        return "{\n" .. output ..  str_rep("  ", indent) .. "}"
    else
        return "{}"
    end

end

--- Экспортирует занчения в строку
--- @return string
function utils.var_export(...)
    local output = {};
    for _, v in pairs({ ... }) do
        if type(v) == 'table' then
            table_insert(output, utils.table_export(v, 0))
        else
            table_insert(output, tostring(v))
        end
    end

    return table_concat(output, "\n")
end

--- Рекурсивное слияние двух таблиц
--- @param t1 table куда будет прилита таблица
--- @param t2 table что приливаем
--- @return table
function utils.merge_table_recursive(t1, t2)
    for k,v in pairs(t2) do
        if type(v) == "table" then
            if type(t1[k] or false) == "table" then
                utils.merge_table_recursive(t1[k] or {}, t2[k] or {})
            else
                t1[k] = v
            end
        else
            t1[k] = v
        end
    end
    return t1
end

--- простой шаблонизатор вида "Hi, ${username}!". Только для одноуровневых таблиц
--- @param s string шаблон
--- @param vars table таблица переменных
--- @return string
function utils.template(s, vars, options)
    return (s:gsub('($%b{})', function(w)
        if w:find(".") then

        else
            return vars[w:sub(3, -2)] or w
        end
    end))
end

--- Объеденение массивов и таблиц.
---
--- @param t table
--- @param v_delim string делиметер между значениями
--- @param k_delim string делиметер между ключем и значением
--- @return string
function utils.implode(t, v_delim, k_delim)
    if not k_delim then
        return table_concat(t, v_delim)
    else
        local _t = {}
        for k, v in pairs(t) do
            table_insert(_t, k .. k_delim .. tostring(v))
        end
        return table_concat(_t, v_delim)
    end
end

--- Разбивает строку по делимитру
---
--- @param str string
--- @param delimiter string разделитель по которому будет дробить строку
--- @return table
function utils.explode(str, delimiter)
    local result = { }
    local from  = 1
    local delim_from, delim_to = str_find( str, delimiter, from  )
    while delim_from do
        table_insert( result, str_sub( str, from , delim_from-1 ) )
        from  = delim_to + 1
        delim_from, delim_to = str_find( str, delimiter, from  )
    end
    table_insert( result, str_sub( str, from  ) )
    return result
end

--- Checks if a value exists in a table.
---
--- @param t table таблица в которой бедт искаться значение
--- @param value any значение которе ищем
--- @return boolean результат поиска
function utils.in_table(t, value)
    if t then
        for _, v in pairs(t) do
            if v == value then
                return true
            end
        end
    end

    return false
end

if not utils.is_array then
    --- Checks if a table is an array and not an associative array.
    ---
    --- @param t table таблица в которой бедт искаться значение
    --- @param value any значение которе ищем
    --- @return boolean результат поиска
    function utils.is_array(t)
        if type(t) ~= "table" then
            return false
        end
        local i = 0
        for _ in pairs(t) do
            i = i + 1
            if t[i] == nil and t[tostring(i)] == nil then
                return false
            end
        end
        return true
    end
end

if not utils.count then
    --- Подсчитать количество элементов в таблице
    ---
    --- @param t table
    --- @return number
    function utils.count(t)
        local c = 0
        for _ in pairs(t) do c = c + 1 end
        return c
    end
end

--- Ищет ключ в таблице по значению
---
--- @param tbl table таблица в которой бедт искаться значение
--- @param value any значение которе ищем
--- @return any|nil результат поиска либо nil если не нашел
function utils.search_key(tbl, value)
    for k,v in pairs(tbl) do
        if value == v then
            return k
        end
    end
    return nil
end

--- Генерирует рандомную строку указанной длины
---
--- @param length number длина конечной строки
--- @param encode boolean произвести кодирование в base64. Строка будет обрезана до длины length
--- @return string, string|nil рандомная строка, текст ошибки
function utils.random_string(length, encode)
    local buf = ffi_new("char[?]", length)
    if C.RAND_bytes(buf, len) == 0 then
        local err_code = C.ERR_get_error()
        if err_code == 0 then
            return nil, "could not get SSL error code from the queue"
        end
        return nil, "could not get random bytes"
    end
    local random = ffi_str(buf, len)
    if encode then
        return str_sub(encode_base64(random, true), 1, length)
    else
        return random
    end
end

if not utils.shallow_copy then
    --- Copies a table into a new table.
    --- neither sub tables nor metatables will be copied.
    ---
    --- @param orig any The table to copy
    --- @return any Returns a copy of the input table
    function _M.shallow_copy(orig)
        local copy
        if type(orig) == "table" then
            copy = {}
            for orig_key, orig_value in pairs(orig) do
                copy[orig_key] = orig_value
            end
        else -- number, string, boolean, etc
            copy = orig
        end
        return copy
    end
end

if not utils.deep_copy then
    --- Returns a new table, recursively copied from the one given.
    ---
    --- @param orig any to be copied
    --- @return any
    function utils.deep_copy(orig)
        local orig_type = type(orig)
        local copy
        if orig_type == "table" then
            copy = {}
            for orig_key, orig_value in next, orig, nil do
                copy[utils.copy_table(orig_key)] = utils.copy_table(orig_value)
            end
        else -- number, string, boolean, etc
            copy = orig
        end
        return copy
    end
end

--- Генерирует хеш пользователя по заголовкам.
--- Может быть не уникальным так что не опирайтесь на него как на уникальный ID пользователя
--- @param headers table список заголовков из ngx.req.get_headers()
--- @param custom string произвольные данные которые надо добавить к хешу и помогут точнее идетифицировать пользователя
--- @return string|nil строка если есть хотя бы один заголовок по которому можено идетифицировать
function utils.get_user_hash(headers, custom)
    local names = {"User-Agent", "Accept", "Accept-Encoding", "Accept-Language", "Cache-Control", "Pragma", "Connection"}
    local values = { }

    for _, name in ipairs(names) do
        local v = headers[name]
        if v then
            if type(v) == "table" then
                v = table_concat(v, "\n")
            end
            table_insert(values, v)
        end
    end

    if #values then
        if custom then
            table_insert(values, custom)
        end
        return encode_base64(sha1_bin(table_concat(values, ";")))
    end
end

--- Конвертирует mongo object_id в дату
--- Первые 4 байта mongo object_id являются штампом времени. Именно ее вычитывает функция и преобразует в дату
--- @param oid string|userdata object_id либо строкой либо объектом cbson.oid
--- @return string дата в фотмате "Wed, 14 Sep 2016 14:18:01 GMT"
function utils.oid_to_date(oid)
    return date("%a, %d %b %Y %H:%m:%S GMT", tonumber("0x"..string.sub(tostring(oid), 1, 8))) -- Wed, 14 Sep 2016 14:18:01 GMT
end

--- Retrieves the hostname of the local machine
--- @return string  The hostname
function get_hostname()
    local result
    local SIZE = 128

    local buf = ffi_new("unsigned char[?]", SIZE)
    local res = C.gethostname(buf, SIZE)

    if res == 0 then
        local hostname = ffi_str(buf, SIZE)
        result = gsub(hostname, "%z+$", "")
    else
        local f = io.popen("/bin/hostname")
        local hostname = f:read("*a") or ""
        f:close()
        result = gsub(hostname, "\n$", "")
    end

    return result
end

utils.hostname = get_hostname()

return utils