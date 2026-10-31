debug = {

    -- log
    log = function(...)

        spdlog.info(debug.parse(...))

    end,

    -- print
    print = function(...)

        print(debug.parse(...))

    end,

    -- parse arguments
    parse = function(...)

        local args = {}
        for _, v in pairs{debug.null(...)} do
            table.insert(args, debug.parseDeep(v))
        end

        local output = ""
        for i, value in pairs(args) do
            output = output .. tostring(value)
            if i ~= #args then
                output = output .. " "
            end
        end

        return output

    end,

    -- parse deep table
    parseDeep = function(t, max, depth)

        -- convert nil to 'nil'
        t = debug.null(t)

        if type(t) ~= 'table' then

            if type(t) == 'userdata' then
                t = debug.parseUserData(t)
            end

            return t
        end

        max = max or 63
        depth = depth or 4

        local dumpStr = '{\n'
        local indent = string.rep(' ', depth)

        for k, v in pairs(t) do

            -- vars
            local ktype = type(k)
            local vtype = type(v)
            local vstr = ''

            -- key
            local kstr = ''
            if ktype == 'string' then
                kstr = string.format('[%q] = ', k)
            end

            -- string
            if vtype == 'string' then
                vstr = string.format('%q', v)

            -- table
            elseif vtype == 'table' then

                if depth < max then
                    vstr = debug.parseDeep(v, max, depth + 4)
                end

            -- userdata
            elseif vtype == 'userdata' then
                vstr = debug.parseUserData(v)

            -- thread (do nothing)
            elseif vtype == 'thread' then

            -- else
            else
                vstr = tostring(v)
            end

            -- format dump
            if vstr ~= '' then
                dumpStr = string.format('%s%s%s%s,\n', dumpStr, indent, kstr, vstr)
            end
        end

        -- unindent
        local unIndent = indent:sub(1, -5)

        -- return
        return string.format('%s%s}', dumpStr, unIndent)

    end,

    -- parse userdata
    parseUserData = function(t)

        local tstr = tostring(t)

        if tstr:find('^ToCName{') then
            tstr = NameToString(t)
        elseif tstr:find('^userdata:') or tstr:find('^sol%.') then

            local gdump = false
            local ddump = false
            pcall(function() gdump = GameDump(t) end)
            pcall(function() ddump = Dump(t, true) end)

            if gdump then
                tstr = GameDump(t)
            elseif ddump then
                tstr = ddump
            end
        end

        return tstr

    end,

    -- convert nil into 'nil'
    null = function(...)

        local t, n = {...}, select('#', ...)

        for k = 1, n do
            local v = t[k]
            if     v == debug.null then t[k] = 'nil'
            elseif v == nil  then t[k] = debug.null
            end
        end

        return (table.unpack or unpack)(t, 1, n)
    end,

}
