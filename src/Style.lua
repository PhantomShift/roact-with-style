-- Depends on Roact
-- Current paths assume a fresh Rojo project with Roact placed in the shared directory
local Roact = require(game:GetService("ReplicatedStorage").Common.Roact)

local Style = {}
Style.__index = Style

Style.Styles = {}

type Rule = {[string]: any}
type Rules = {[string]: Rule}

local cachedIsInstance = {}
-- Determines if a given class name has a valid instance
local function isInstance(className: string) : boolean
    if cachedIsInstance[className] ~= nil then
        return cachedIsInstance[className]
    end
    local instance
    local success = pcall(function(name)
        instance = Instance.new(name)
    end, className)
    if instance then
        instance:Destroy()
    end
    cachedIsInstance[className] = success
    return success
end


local cachedInstanceProperty = {}
-- Determines if an Instance has a given property
local function instanceDefaultProperty(className: string, property: string) : boolean
    assert(isInstance(className), className.." is not a valid Instance")
    if not cachedInstanceProperty[className] then
        cachedInstanceProperty[className] = {}
    end
    local cache = cachedInstanceProperty[className]
    if cache[property] ~= nil then
        return true, cache[property]
    end
    local instance = Instance.new(className)
    local success, default = pcall(function()
        return instance[property]
    end)
    instance:Destroy()
    if success then
        cache[property] = default
    end
    return success, cache[property]
end

--[[
    Applies the given style rule to an element
    First applies Global properties,
    then applies component-specific properties,
    and then applies tag-specific properties
]]
function Style:applySingular(element: RoactElement) : RoactElement
    local tag = element.props.Tag
    local component_string = tostring(element.component)
    local toApply = {}

    -- Apply Global rules
    if self.Rules.Global then
        for property, value in pairs(self.Rules.Global) do
            toApply[property] = value
        end
    end

    -- Apply rules specific to Component/Instance class
    if self.Rules[component_string] then
        for property, value in pairs(self.Rules[component_string]) do
            toApply[property] = value
        end
    end

    -- Apply rules specific to given Tag, if present
    if tag and tag ~= "Global" and self.Rules[tag] then
        element.props.Tag = nil
        for property, value in pairs(self.Rules[tag]) do
            toApply[property] = value
        end
    end

    -- Apply all valid properties to the element
    for property, value in pairs(toApply) do
        if isInstance(component_string) then
            local isProperty, default = instanceDefaultProperty(component_string, property)
            if isProperty and typeof(value) == typeof(default) and not element.props[property] then
                element.props[property] = value
            end
        else
            if not element.props[property] then
                element.props[property] = value
            end
        end
    end
    return element
end

-- Calls Style:applySingular on the element and its descendants
function Style:apply(element)
    -- If the given element actually consists of multiple elements (i.e. fragments), apply the styles individually
    if element.elements then
        for i, e in pairs(element.elements) do
            self:applySingular(e)
            if type(e.component) == "table" and e.component.render then
                local old_render = e.component.render
                e.component.render = function(this)
                    local rendered = old_render(this)
                    return self:apply(rendered)
                end
            end
            if e.props[Roact.Children] then
                for b, child in pairs(e.props[Roact.Children]) do
                    self:apply(child)
                end
            end
        end
    else
        self:applySingular(element)
        if type(element.component) == "table" and element.component.render then
            local old_render = element.component.render
            element.component.render = function(this)
                local rendered = old_render(this)
                return self:apply(rendered)
            end
        elseif type(element.component) == "function" then
            local original = element.component
            element.component = function(props)
                local newElement = original(props)
                return self:apply(newElement)
            end
        end
        if element.props[Roact.Children] then
            for i, child in pairs(element.props[Roact.Children]) do
                self:apply(child)
            end
        end
    end
    return element
end

-- Returns a new Style object; errors if there are any bad definitions
function Style.new(styleName: string, rules: Rules)
    local style = {Rules = rules}

    -- Check that, for all rules defined for Roblox instances, the defined properties are actually present in the instance
    for tag: string, rule: Rule in pairs(rules) do
        if isInstance(tag) then
            for property, value in pairs(rule) do
                assert(property ~= Roact.Children, "Cannot use Roact.Children as a property in styles. Style Name: "..styleName)
                local hasProperty, default = instanceDefaultProperty(tag, property)
                assert(hasProperty, tag.." has no property "..property..". Style Name: "..styleName)
                assert(typeof(value) == typeof(default), "Improper value "..tostring(value).." for property "..property.." of "..tag..". Style Name: "..styleName)
            end
        end
    end

    setmetatable(style, Style)
    Style.Styles[styleName] = style

    return style
end

return Style