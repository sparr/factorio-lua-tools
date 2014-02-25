#!/usr/bin/env lua

local Loader = require("loader")
local io = require("io")

recipe_colors = {
    crafting = "#cccccc",
    smelting = "#cc9999",
    chemistry = "#99cc99",
    ["oil-processing"] = "#999900",
}
goal_color = "#666666"
language = "en"
output_format='dot'

if pcall(function () require ("gv") end) then
    has_gv=true
else
    has_gv=false
end

valid_output_formats = {png=true,dot=true}

args_to_delete = {}
for a=1,#arg do
    if arg[a] == '-T' then
        output_format = arg[a+1]
        table.insert(args_to_delete,1,a)
        table.insert(args_to_delete,1,a+1)
    end
end

for a=#args_to_delete,1,-1 do
    table.remove(arg,a)
end

function print_usage(err)
    if(err) then
        io.stderr:write(err..'\n')
    end
    io.stderr:write([[This is receipe grapher for factorio. WIP!
Loads contents of several mods and outputs graphs of depencies for all items.

This invocation produces one png for each recipe (and requires the graphviz lua bindings):

    recipes-graph.lua -T png /path/to/data/core /path/to/data/base

This invocation produces a dot file describing every recipe:

    recipes-graph.lua -T dot /path/to/data/core /path/to/data/base

This command produces the dot file and then asks the 'dot' program to render it:

    recipes-graph.lua -T dot /path/to/data/core /path/to/data/base | dot -T png -O

If you have other mods installed, their paths can be added to the end of the command line:

    recipes-graph.lua -T png /path/to/data/core /path/to/data/base /path/to/mods/Industrio /path/to/mods/DyTech

]])
end

if(valid_output_formats[output_format]==nil) then
    print_usage('Invalid output type specified')
    os.exit()
end

if(output_format=='png' and has_gv==false) then
    print_usage('png format requested but graphviz lua lib not available')
    os.exit()
end

Ingredient = {}
function Ingredient:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Ingredient.from_recipe(spec)
    local self = Ingredient:new()
    if spec.type == nil then
        self.type = "item"
        self.name = spec[1]
        self.amount = spec[2]
    else
        self.type = spec.type
        self.name = spec.name
        self.amount = spec.amount
    end
    self:_make_id()

    if self.type == "item" then
        for k, type in ipairs(Loader.item_types) do
            self.item_object = Loader.data[type][self.name]
            if self.item_object ~= nil then break end
        end
    else
        self.item_object = Loader.data[self.type][self.name]
    end

    if not self.item_object then
        error(self.type .. " " .. self.name .. " doesn't exist!")
    end

    self.image = Loader.expand_path(self.item_object.icon)

    return self
end

function Ingredient:_make_id()
    self.id = self.type .. "-" .. self.name
end

function Ingredient:translated_name(language)
    local item_name = Loader.translate(self.type .. "-name." .. self.name, language)
    if item_name then
        return item_name
    end

    if self.item_object.place_result then
        return Loader.translate("entity-name." .. self.item_object.place_result, language)
    else
        return Loader.translate("equipment-name." .. self.item_object.placed_as_equipment_result, language)
    end
end

Recipe = {}
function Recipe:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Recipe.from_data(spec, name)
    local self = Recipe:new()
    self.name = name
    self.id = 'recipe-' .. name
    self.category = spec.category or "crafting"
    self.ingredients = {}
    for k, v in ipairs(spec.ingredients) do
        self.ingredients[#self.ingredients + 1] = Ingredient.from_recipe(v)
    end
    if spec.results ~= nil then
        self.results = {}
        for k, v in ipairs(spec.results) do
            self.results[#self.results + 1] = Ingredient.from_recipe(v)
        end
    else
        self.results = { Ingredient.from_recipe{spec.result, (spec.result_count or 1)} }
    end
    return self
end

function Recipe:translated_name(language)
    return Loader.translate("recipe-name." .. self.name, language) or self.results[1]:translated_name(language)
end

function enumerate_resource_items()
    resource_items = {}
    for name, resource in pairs(Loader.data.resource) do
        if resource.minable.results ~= nil then
            for k, v in ipairs(resource.minable.results) do
                resource_items[Ingredient.from_recipe(v).id] = 1
            end
        else
            resource_items[Ingredient.from_recipe{resource.minable.result, 1}.id] = 1
        end
    end
end

function enumerate_recipes()
    recipes_by_result = {}
    for name, recipe in pairs(Loader.data.recipe) do
        recipe = Recipe.from_data(recipe, name)
        for k, result in ipairs(recipe.results) do
            if recipes_by_result[result.id] == nil then
                recipes_by_result[result.id] = { recipe }
            else
                recipes_by_result[result.id][#recipes_by_result[result.id] + 1] = recipe
            end
        end
    end
end

function find_recipe(result)
    -- argument is an ingredient, but we ignore amount
    local ret
    for name, recipe in pairs(Loader.data.recipe) do
        recipe = Recipe.from_data(recipe, name)
        for k, v in ipairs(recipe.results) do
            if v.type == result.type and v.name == result.name then
                if ret ~= nil then
                    --error("multiple recipes with the same result (" .. ret_recipe.name .. " and " .. recipe.name .. ")")
                end
                ret = recipe
                ret.amount = result.amount / v.amount
            end
        end
    end

    return ret
end

function add_item_port(list, item, port)
    if list[item.id] == nil then
        list[item.id] = { port }
    else
        list[item.id][#list[item.id] + 1] = port
    end
end

function recipe_node(recipe, closed, waiting, item_sources, item_sinks)
    local ret = ''

    if recipe_colors[recipe.category] == nil then
        error(recipe.category .. " is not a known recipe category (add it to recipe_colors)")
    end
    ret = ret .. '"' .. recipe.id .. '" [ '
    ret = ret .. 'shape = plaintext,'

    local colspan = 0
    ret = ret .. '\nlabel = <<TABLE bgcolor = "' .. recipe_colors[recipe.category] .. '" border="0" cellborder="1" cellspacing="0"><TR>\n'
    for k, result in ipairs(recipe.results) do
        ret = ret .. '<TD port="' .. result.id .. '"><IMG src="' .. result.image .. '" /></TD>\n'

        add_item_port(item_sources, result, '"' .. recipe.id .. '":"' .. result.id .. ':n"')
        colspan = colspan + 1
    end
    ret = ret .. '</TR><TR><TD colspan="' .. colspan .. '">' .. recipe:translated_name(language) .. '</TD>'
    ret = ret .. '</TR></TABLE>>];\n'

    for k, ingredient in ipairs(recipe.ingredients) do
        add_item_port(item_sinks, ingredient, '"' .. recipe.id .. '"')

        if not closed[ingredient.id] then
            waiting[#waiting + 1] = ingredient
        end
    end

    return ret
end

function item_node(item_id, goal)
    local type, name = item_id:match('^(%a+)-(.*)$')
    ingredient = Ingredient.from_recipe{type = type, name = name, amount = 1}
    local ret = '"' .. ingredient.id .. '" ['
    ret = ret .. 'image = "' .. ingredient.image .. '", '
    --ret = ret .. 'xlabel = "' .. ingredient.amount .. ' / s", '
    if type == goal.type and name == goal.name then
        ret = ret .. 'fillcolor = "' .. goal_color .. '", '
        ret = ret .. 'style = filled, '
    end
    ret = ret .. '];\n'
    return ret
end

function graph(goal)
    local ret = 'digraph "' .. goal.id .. '" {\n'
    ret = ret .. 'graph [bgcolor=transparent, rankdir=BT];\n'
    ret = ret .. 'node [label=""];\n'

    local closed = {}
    local waiting = { goal }
    local item_sources = {}
    local item_sinks = {}

    while #waiting > 0 do
        local current = waiting[#waiting]
        waiting[#waiting] = nil
        if closed[current.id] == nil then
            closed[current.id] = current
        end

        if not resource_items[current.id] and recipes_by_result[current.id] ~= nil then
            for k, recipe in pairs(recipes_by_result[current.id]) do
                if not closed[recipe.id] then
                    ret = ret .. recipe_node(recipe, closed, waiting, item_sources, item_sinks)
                    closed[recipe.id] = 1
                end
            end
        end
    end

    for id, source_ports in pairs(item_sources) do
        for k, source_port in pairs(source_ports) do
            sink_ports = item_sinks[id]
            if sink_ports then
                for k, sink_port in ipairs(sink_ports) do
                    ret = ret .. source_port .. ' -> ' .. sink_port .. ';\n'
                end
            else
                ret = ret .. item_node(id, goal)
                ret = ret .. source_port .. ' -> "' .. id .. '";\n'
            end
        end
    end

    for id, sink_ports in pairs(item_sinks) do
        for k, sink_port in pairs(sink_ports) do
            if item_sources[id] == nil then
                ret = ret .. item_node(id, goal)
                ret = ret .. '"' .. id .. '" -> ' .. sink_port .. ';\n'
            end
        end
    end

    ret = ret .. "}"

    if(output_format=='png') then
        print(goal.id)
        g=gv.readstring(ret)
        gv.layout(g, 'dot')
        gv.render(g, 'png', goal.id .. '.png');
    elseif(output_format=='dot') then
        print(ret)
    else
        io.stderr:write('Unknown output format "'..output_format..'". Falling back to dot.\n')
        print(ret)
    end
end

Loader.load_data(arg, "en")
enumerate_resource_items()
enumerate_recipes()

for k, item_type in ipairs(Loader.item_types) do
    for name, item in pairs(Loader.data[item_type]) do
        graph(Ingredient.from_recipe{name = name, type="item", amount=1})
    end
end
for name, item in pairs(Loader.data["fluid"]) do
    graph(Ingredient.from_recipe{name = name, type="fluid", amount=1})
end
