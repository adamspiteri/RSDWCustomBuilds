-- Manifest loader: merge piece entries with vanilla donor metadata.

local M = {}

local donors = require("donors")



local cache = nil



local function resolve_pak_first(entry, donor_da)

    if entry.pak_first == true then return true end

    if entry.pak_first == false then return false end

    if entry.da_path and donor_da and entry.da_path ~= donor_da then return true end

    return false

end



local function resolve(entry)

    if type(entry) ~= "table" or type(entry.id) ~= "string" then return nil end

    local d = donors[entry.donor or ""]

    if not d then return nil end

    local donor_da = d.da_path

    local da_path = entry.da_path or donor_da

    local pak_first = resolve_pak_first(entry, donor_da)

    local native = entry.native_placement == true

    return {

        id = entry.id,

        display_name = entry.display_name or entry.id,

        donor = entry.donor,

        da_path = da_path,

        placement_da_path = native and da_path or d.da_path,

        placement_bp_path = entry.bp_path or d.bp_path,

        bp_path = entry.bp_path or d.bp_path,

        mesh_path = entry.mesh_path,

        icon_path = entry.icon_path,

        bp_mark = entry.bp_mark or d.bp_mark,

        runtime_material = entry.runtime_material == true,

        persistence_id = entry.persistence_id,

        catalogue_index = entry.catalogue_index,

        base_tex = entry.base_tex,

        norm_tex = entry.norm_tex,

        pak_first = pak_first,

        native_placement = native,

    }

end



function M.all()

    if cache then return cache end

    local ok, data = pcall(require, "pieces_data")

    if not ok or type(data) ~= "table" or type(data.pieces) ~= "table" then

        cache = {}

        return cache

    end

    cache = {}

    for _, entry in ipairs(data.pieces) do

        local p = resolve(entry)

        if p then cache[#cache + 1] = p end

    end

    return cache

end



function M.by_id(id)

    if type(id) ~= "string" then return nil end

    for _, p in ipairs(M.all()) do

        if p.id == id then return p end

    end

    return nil

end



function M.first()

    return M.all()[1]

end



return M

