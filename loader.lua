local lfs = require("lfs")
local io = require("io")

local Loader = {}

Loader._path_substitutions = {}
Loader._translations = {}
Loader.data = {}

function load_language_file(path, language)
    local file = io.open(path, "r")
    for line in file:lines() do
        local group_match = line:match("^%[([^%]]+)%]$")
        if group_match then
            group = group_match
        else
            local key, value = line:match("^([^=]+)=(.*)$")
            if key then
                if group then key = group .. "." .. key end
                Loader._translations[language][key] = value
            end
        end
    end
    file:close()
end

function load_languages(path)
    for language in lfs.dir(path) do
        local language_path = path .. "/" .. language
        if lfs.attributes(language_path, "mode") == "directory" then
            if Loader._translations[language] == nil then
                Loader._translations[language] = {}
            end
            for file in lfs.dir(language_path) do
                local path = path .. "/" .. language .. "/" .. file
                if path:match("%.cfg$") then
                    load_language_file(path, language)
                end
            end
        end
    end
end

--- Loads Factorio data files from a list of mods.
--
-- Paths contain a list of mods that are loaded, first one has to be core.
--
-- This function  hides the global table data, and instead exports
-- whats internaly data.raw as Loader.data
function Loader.load_data(paths)
    local old_data = data
    for i = 1, #paths do
        if i == 1 then
            package.path = paths[i] .. "/lualib/?.lua;" .. package.path
            require("dataloader")
        end

        local old_path = package.path
        package.path = paths[i] .. "/?.lua;" .. package.path

        dofile(paths[i] .. "/data.lua")

        local extended_path = "./" .. paths[i]

        Loader._path_substitutions["__" .. extended_path:gsub("^.*/([^/]+)/?$", "%1") .. "__"] = paths[i]

        load_languages(paths[i] .. "/locale/")

        package.path = old_path
    end
    Loader.data = data.raw
    data = old_data
end

--- Replace __mod__ references in path.
function Loader.expand_path(path)
    return path:gsub("__[a-zA-Z0-9-_]*__", Loader._path_substitutions)
end

function Loader.translate(string, language)
    if not Loader._translations[language] then
        return nil
    end

    return Loader._translations[language][string]
end

Loader.item_types = { "item", "ammo", "blueprint", "capsule",
                      "deconstruction-item", "gun", "module",
                      "armor", "mining-tool", "repair-tool" }

return Loader
